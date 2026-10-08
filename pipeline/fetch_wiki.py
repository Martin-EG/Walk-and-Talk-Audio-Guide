"""Step 2: attach a Wikipedia summary to each place when we can find a confident match.

Match order: the OSM wikipedia tag, then the Wikidata sitelinks, then a name search
(accepted only if the article's coordinates are close AND its title shares most of the place's words),
then a geosearch (an article geotagged right next to the place whose title shares a word with it).
Languages: the tour language first, then config.WIKI_FALLBACK_LANGS.

It also collects "area" articles: every article geotagged inside the tour radius that isn't one of
the stops (e.g. a neighborhood). Stories can mention them as nearby context.

Reads stops_raw.json, writes stops_wiki.json (each stop gains "wiki": {...} or None) and area.json.

Standalone:  python pipeline/fetch_wiki.py --route mexicali --lang en --lat 32.661938 --lon -115.489149 --radius 500
"""

import argparse
import json
import re
import unicodedata
from urllib.parse import quote

import requests

import cache
import config
from geo import distance_m

HEADERS = {"User-Agent": config.USER_AGENT}
GEO_MATCH_M = 150
STOPWORDS = {"de", "del", "la", "el", "los", "las", "y", "the", "of", "and", "a"}


def get_json(url, params=None):
    """GET with an on-disk cache. 404s are cached too (as None) so misses stay fast."""
    key = {"url": url, "params": params}
    cached = cache.get_json("wiki", key)
    if cached is not None:
        return cached["body"]
    resp = requests.get(url, params=params, headers=HEADERS, timeout=30)
    if resp.status_code == 404:
        body = None
    else:
        resp.raise_for_status()
        body = resp.json()
    cache.put_json("wiki", key, {"body": body})
    return body


def words(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return {w for w in re.findall(r"[a-z0-9]+", text) if w not in STOPWORDS}


def summary(lang, title):
    """REST summary for one article, or None if missing / disambiguation / empty."""
    url = f"https://{lang}.wikipedia.org/api/rest_v1/page/summary/{quote(title.replace(' ', '_'), safe='')}"
    data = get_json(url)
    if not data or data.get("type") == "disambiguation" or not data.get("extract"):
        return None
    return {
        "lang": lang,
        "title": data["title"],
        "extract": data["extract"],
        "url": data["content_urls"]["desktop"]["page"],
    }


def wikidata(qid, langs):
    data = get_json(
        "https://www.wikidata.org/w/api.php",
        {"action": "wbgetentities", "ids": qid, "props": "sitelinks|descriptions",
         "languages": "|".join(langs), "format": "json"},
    )
    entity = (data or {}).get("entities", {}).get(qid, {})
    titles = [(lang, entity["sitelinks"][f"{lang}wiki"]["title"])
              for lang in langs if f"{lang}wiki" in entity.get("sitelinks", {})]
    description = next((entity["descriptions"][l]["value"] for l in langs if l in entity.get("descriptions", {})), None)
    return titles, description


def search(lang, stop):
    """Name search; keep the closest geotagged hit that also shares most of the place's words."""
    data = get_json(
        f"https://{lang}.wikipedia.org/w/api.php",
        {"action": "query", "generator": "search", "gsrsearch": stop["name"], "gsrlimit": 5,
         "prop": "coordinates", "format": "json"},
    )
    name_words = words(stop["name"])
    best = None
    for page in (data or {}).get("query", {}).get("pages", {}).values():
        coords = page.get("coordinates")
        if not coords or not name_words:
            continue
        dist = distance_m(stop["lat"], stop["lon"], coords[0]["lat"], coords[0]["lon"])
        overlap = len(name_words & words(page["title"])) / len(name_words)
        if dist <= config.WIKI_MATCH_MAX_M and overlap >= 0.5 and (best is None or dist < best[0]):
            best = (dist, page["title"])
    return best[1] if best else None


def geosearch(lang, stop):
    """Articles geotagged within GEO_MATCH_M of the place whose title shares a real word (4+ letters)."""
    data = get_json(
        f"https://{lang}.wikipedia.org/w/api.php",
        {"action": "query", "list": "geosearch", "gscoord": f"{stop['lat']}|{stop['lon']}",
         "gsradius": GEO_MATCH_M, "gslimit": 10, "format": "json"},
    )
    name_words = {w for w in words(stop["name"]) if len(w) >= 4}
    for page in (data or {}).get("query", {}).get("geosearch", []):  # sorted nearest first
        if name_words & words(page["title"]):
            return page["title"]
    return None


def find_wiki(stop, langs):
    tags = stop["tags"]
    candidates = []  # (lang, title, how we found it)
    if ":" in tags.get("wikipedia", ""):
        lang, title = tags["wikipedia"].split(":", 1)
        candidates.append((lang, title, "osm_tag"))
    description = None
    if tags.get("wikidata"):
        titles, description = wikidata(tags["wikidata"], langs)
        candidates += [(lang, title, "wikidata") for lang, title in titles]

    # Prefer the tour language; drop languages we don't want.
    candidates = sorted((c for c in candidates if c[0] in langs), key=lambda c: langs.index(c[0]))
    for lang, title, how in candidates:
        found = summary(lang, title)
        if found:
            return dict(found, match=how), description

    for how, finder in (("search", search), ("geosearch", geosearch)):
        for lang in langs:
            title = finder(lang, stop)
            found = summary(lang, title) if title else None
            if found:
                return dict(found, match=how), description
    return None, description


def area_articles(lat, lon, radius, langs, taken_urls):
    """Geotagged articles inside the tour radius that aren't already a stop's article."""
    articles = []
    for lang in langs:
        data = get_json(
            f"https://{lang}.wikipedia.org/w/api.php",
            {"action": "query", "list": "geosearch", "gscoord": f"{lat}|{lon}",
             "gsradius": min(radius, 10000), "gslimit": 20, "format": "json"},
        )
        for page in (data or {}).get("query", {}).get("geosearch", []):
            found = summary(lang, page["title"])
            if found and found["url"] not in taken_urls:
                articles.append(dict(found, lat=page["lat"], lon=page["lon"]))
                taken_urls.add(found["url"])
    return articles


def run(work_dir, lang, lat, lon, radius):
    langs = [lang] + [l for l in config.WIKI_FALLBACK_LANGS if l != lang]
    stops = json.loads((work_dir / "stops_raw.json").read_text())
    for stop in stops:
        stop["wiki"], stop["wikidata_description"] = find_wiki(stop, langs)
        label = f"{stop['wiki']['lang']}:{stop['wiki']['title']} ({stop['wiki']['match']})" if stop["wiki"] else "-"
        print(f"  {stop['name']}: {label}")
    (work_dir / "stops_wiki.json").write_text(json.dumps(stops, ensure_ascii=False, indent=2))
    print(f"  {sum(1 for s in stops if s['wiki'])}/{len(stops)} places matched a Wikipedia article")

    area = area_articles(lat, lon, radius, langs, {s["wiki"]["url"] for s in stops if s["wiki"]})
    (work_dir / "area.json").write_text(json.dumps(area, ensure_ascii=False, indent=2))
    print(f"  {len(area)} area articles: {', '.join(a['title'] for a in area) or '-'}")
    return stops


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--route", required=True)
    parser.add_argument("--lang", default=config.LANGUAGE)
    parser.add_argument("--lat", type=float, required=True)
    parser.add_argument("--lon", type=float, required=True)
    parser.add_argument("--radius", type=int, default=500)
    args = parser.parse_args()
    run(config.WORK_DIR / args.route, args.lang, args.lat, args.lon, args.radius)
