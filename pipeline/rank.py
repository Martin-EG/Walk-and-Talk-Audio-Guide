"""Step 3: score places, drop near-duplicates, keep the best 8-12, and order them as a walking loop.

Score = facts we can narrate (Wikipedia text, informative OSM tags) + how "tour-worthy" the tags are.
Selection is greedy: each pick also gets a bonus for being far from the stops already picked,
so the tour spreads out instead of clustering on one block. Order is nearest-neighbor starting
from the stop closest to the center; the walk ends back near where it started.

Reads stops_wiki.json, writes stops_ranked.json.

Standalone:  python pipeline/rank.py --route mexicali --lat 32.661938 --lon -115.489149 [--exclude way/423032194]
"""

import argparse
import json

import config
from geo import distance_m

TAG_POINTS = {
    ("historic", None): 2.0,
    ("tourism", "museum"): 1.5,
    ("tourism", "attraction"): 1.5,
    ("amenity", "place_of_worship"): 1.5,
    ("tourism", "artwork"): 1.0,
    ("tourism", "viewpoint"): 1.0,
    ("amenity", "theatre"): 1.0,
    ("leisure", "park"): 0.5,
    ("leisure", "sports_centre"): 0.5,
    ("leisure", "stadium"): 0.5,
    ("leisure", "recreation_ground"): 0.5,
    ("landuse", "recreation_ground"): 0.5,
    ("wikidata", None): 0.5,
}
# Tags that give the story writer something real to say.
FACT_TAGS = ["start_date", "artist_name", "inscription", "description", "architect",
             "material", "denomination", "artwork_type", "memorial", "subject"]
SPREAD_FULL_BONUS_M = 150  # a candidate this far from every picked stop gets the full +1 bonus


def score(stop):
    points = 0.0
    if stop.get("wiki"):
        points += 3 + min(len(stop["wiki"]["extract"]) / 400, 2)
    for (key, value), bonus in TAG_POINTS.items():
        if key in stop["tags"] and (value is None or stop["tags"][key] == value):
            points += bonus
    points += 0.25 * sum(1 for tag in FACT_TAGS if tag in stop["tags"])
    return round(points, 2)


def dist(a, b):
    return distance_m(a["lat"], a["lon"], b["lat"], b["lon"])


def drop_duplicates(stops):
    """Keep the higher-scoring stop of any pair closer than MIN_STOP_SPACING_M, and one per name."""
    kept = []
    for stop in sorted(stops, key=lambda s: -s["score"]):
        too_close = any(dist(stop, k) < config.MIN_STOP_SPACING_M for k in kept)
        same_name = any(stop["name"].lower() == k["name"].lower() for k in kept)
        if not too_close and not same_name:
            kept.append(stop)
    return kept


def pick_spread(stops, count):
    picked, pool = [], list(stops)
    while pool and len(picked) < count:
        def value(s):
            if not picked:
                return s["score"]
            nearest = min(dist(s, p) for p in picked)
            return s["score"] + min(nearest, SPREAD_FULL_BONUS_M) / SPREAD_FULL_BONUS_M
        best = max(pool, key=value)
        picked.append(best)
        pool.remove(best)
    return picked


def order_loop(stops, lat, lon):
    center = {"lat": lat, "lon": lon}
    remaining = list(stops)
    current = min(remaining, key=lambda s: dist(s, center))
    route = []
    while remaining:
        remaining.remove(current)
        route.append(current)
        if remaining:
            current = min(remaining, key=lambda s: dist(s, current))
    return route


def run(work_dir, lat, lon, exclude=(), max_stops=config.MAX_STOPS):
    stops = json.loads((work_dir / "stops_wiki.json").read_text())
    stops = [s for s in stops if s["id"] not in exclude]
    for stop in stops:
        stop["score"] = score(stop)

    unique = drop_duplicates(stops)
    picked = pick_spread(unique, max_stops)
    route = order_loop(picked, lat, lon) if picked else []

    if len(route) < config.MIN_STOPS:
        print(f"  WARNING: only {len(route)} stops; the tour needs {config.MIN_STOPS}. Try a bigger --radius.")
    walk_m = sum(dist(a, b) for a, b in zip(route, route[1:] + route[:1]))
    (work_dir / "stops_ranked.json").write_text(json.dumps(route, ensure_ascii=False, indent=2))
    for i, stop in enumerate(route, 1):
        print(f"  {i:2}. {stop['name']} (score {stop['score']})")
    print(f"  {len(stops)} candidates, {len(unique)} after dedupe, {len(route)} picked, loop ~{walk_m:.0f} m")
    return route


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--route", required=True)
    parser.add_argument("--lat", type=float, required=True)
    parser.add_argument("--lon", type=float, required=True)
    parser.add_argument("--exclude", nargs="*", default=[], help="OSM ids to drop, e.g. way/423032194")
    args = parser.parse_args()
    run(config.WORK_DIR / args.route, args.lat, args.lon, set(args.exclude))
