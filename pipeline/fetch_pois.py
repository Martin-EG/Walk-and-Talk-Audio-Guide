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
from geo import distance_m

HEADERS = {"User-Agent": config.USER_AGENT}

# Things that carry a wikipedia/wikidata tag but are not walkable stops.
SKIP_KEYS = {"boundary", "admin_level", "place", "timezone", "shop", "brand", "route", "highway", "power"}
SKIP_AMENITIES = {"pharmacy", "bank", "atm", "restaurant", "fast_food", "cafe", "bar", "pub", "fuel",
                  "parking", "clinic", "dentist", "doctors", "car_rental", "bureau_de_change"}


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
  nwr.named[wikipedia];
  nwr.named[wikidata];
);
out center tags;
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


def to_stop(element):
    # Nodes have lat/lon; ways and relations get a "center" from `out center`.
    point = element if "lat" in element else element.get("center")
    if not point:
        return None
    return {
        "id": f"{element['type']}/{element['id']}",
        "name": element["tags"]["name"],
        "lat": point["lat"],
        "lon": point["lon"],
        "tags": element["tags"],
    }


def run(work_dir, lat, lon, radius):
    data = overpass(build_query(lat, lon, radius))
    stops = []
    for element in data["elements"]:
        tags = element.get("tags", {})
        if SKIP_KEYS & tags.keys() or tags.get("type") == "boundary" or tags.get("amenity") in SKIP_AMENITIES:
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
