"""Step 1: fetch named points of interest around a center point from OpenStreetMap (Overpass).

Writes pipeline/work/<route>/stops_raw.json: [{id, name, lat, lon, tags}, ...]

Standalone:  python pipeline/fetch_pois.py --route mexicali --lat 32.661938 --lon -115.489149 --radius 500
"""

import argparse
import json
import time

import requests

import cache
import config
from geo import distance_m, simplify_ring

HEADERS = {"User-Agent": config.USER_AGENT}

# Things that carry a wikipedia/wikidata tag but are not walkable stops.
SKIP_KEYS = {"boundary", "admin_level", "place", "timezone", "shop", "brand", "route", "highway", "power"}
SKIP_AMENITIES = {"pharmacy", "bank", "atm", "restaurant", "fast_food", "cafe", "bar", "pub", "fuel",
                  "parking", "clinic", "dentist", "doctors", "car_rental", "bureau_de_change"}
# Exceptions to SKIP_KEYS: public squares (place=square, pedestrian plazas) and malls, which
# rank.py scores as filler. A mall may carry a brand tag; that doesn't make it a chain store.
# Outlines are simplified to this many meters, which keeps tour.json small.
OUTLINE_TOLERANCE_M = 3
KEEP_TAGS = {("place", "square"), ("highway", "pedestrian"), ("shop", "mall")}


def skipped(tags):
    keys = SKIP_KEYS & tags.keys()
    if tags.get("shop") == "mall":
        keys -= {"shop", "brand"}
    # A pedestrian street is a line; only a pedestrian area is a plaza you can stand in.
    keys = {k for k in keys if (k, tags[k]) not in KEEP_TAGS or (k == "highway" and tags.get("area") != "yes")}
    return bool(keys) or tags.get("type") == "boundary" or tags.get("amenity") in SKIP_AMENITIES


def build_query(lat, lon, radius):
    return f"""
[out:json][timeout:90];
nwr(around:{radius},{lat},{lon})[name]->.named;
(
  nwr.named[historic];
  nwr.named[tourism~"^(attraction|museum|artwork|viewpoint)$"];
  nwr.named[amenity~"^(place_of_worship|theatre)$"];
  nwr.named[leisure=park];
  nwr.named[leisure~"^(sports_centre|stadium|recreation_ground)$"];
  nwr.named[landuse=recreation_ground];
  nwr.named[place=square];
  nwr.named[highway=pedestrian][area=yes];
  nwr.named[shop=mall];
  nwr.named[wikipedia];
  nwr.named[wikidata];
);
out geom tags;
"""


def overpass(query):
    """POST the query, cached. Overpass is often busy (504/429), so retry with backoff across mirrors."""
    cached = cache.get_json("overpass", query)
    if cached is not None:
        return cached

    last_error = None
    for attempt in range(10):
        url = config.OVERPASS_URLS[attempt % len(config.OVERPASS_URLS)]
        try:
            resp = requests.post(url, data={"data": query}, headers=HEADERS, timeout=120)
            if resp.ok:
                return cache.put_json("overpass", query, resp.json())
            last_error = f"HTTP {resp.status_code} from {url}"
        except requests.RequestException as exc:
            last_error = f"{type(exc).__name__} from {url}"
        wait = 3 + 2 * attempt
        print(f"  overpass busy ({last_error}); retrying in {wait}s")
        time.sleep(wait)
    raise RuntimeError(f"Overpass failed after retries: {last_error}")


def closed_rings(lines):
    """Join way pieces end to end into closed rings; pieces that never close are dropped."""
    pieces = [list(line) for line in lines if len(line) >= 2]
    rings = []
    while pieces:
        ring = pieces.pop()
        while ring[0] != ring[-1]:
            for i, piece in enumerate(pieces):
                if piece[0] == ring[-1]:
                    ring += piece[1:]
                elif piece[-1] == ring[-1]:
                    ring += piece[-2::-1]
                else:
                    continue
                pieces.pop(i)
                break
            else:
                break  # no piece continues this one
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring)
    return rings


def outline(element):
    """The place's outer rings as [[lat, lon], ...] lists, simplified; None for points and lines."""
    if element["type"] == "way":
        lines = [element.get("geometry", [])]
    elif element["type"] == "relation":
        lines = [m.get("geometry", []) for m in element.get("members", [])
                 if m.get("type") == "way" and m.get("role") == "outer"]
    else:
        return None
    lines = [[(round(p["lat"], 6), round(p["lon"], 6)) for p in line if p] for line in lines]
    rings = [simplify_ring(r, OUTLINE_TOLERANCE_M) for r in closed_rings(lines)]
    rings = [[list(p) for p in r] for r in rings if len(r) >= 4]
    return rings or None


def to_stop(element):
    # Nodes have lat/lon; ways and relations get the middle of their bounding box, like
    # Overpass's `out center`.
    if "lat" in element:
        point = element
    elif element.get("bounds"):
        b = element["bounds"]
        point = {"lat": (b["minlat"] + b["maxlat"]) / 2, "lon": (b["minlon"] + b["maxlon"]) / 2}
    else:
        return None
    stop = {
        "id": f"{element['type']}/{element['id']}",
        "name": element["tags"]["name"],
        "lat": point["lat"],
        "lon": point["lon"],
        "tags": element["tags"],
    }
    area = outline(element)
    if area:
        stop["area"] = area
    return stop


def run(work_dir, lat, lon, radius):
    data = overpass(build_query(lat, lon, radius))
    stops = []
    for element in data["elements"]:
        tags = element.get("tags", {})
        if skipped(tags):
            continue
        stop = to_stop(element)
        # Big ways/relations can match `around` while their center is far away.
        if stop and distance_m(lat, lon, stop["lat"], stop["lon"]) <= radius:
            stops.append(stop)

    work_dir.mkdir(parents=True, exist_ok=True)
    (work_dir / "stops_raw.json").write_text(json.dumps(stops, ensure_ascii=False, indent=2))
    print(f"  {len(data['elements'])} elements from Overpass, {len(stops)} kept")
    return stops


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--route", required=True)
    parser.add_argument("--lat", type=float, required=True)
    parser.add_argument("--lon", type=float, required=True)
    parser.add_argument("--radius", type=int, default=500)
    args = parser.parse_args()
    run(config.WORK_DIR / args.route, args.lat, args.lon, args.radius)
