"""Write a GPX track that walks through every stop in order, for Xcode's location simulation.

  python pipeline/make_gpx.py tours/mexicali/tour.json                  # real pace, waits at each stop
  python pipeline/make_gpx.py tours/mexicali/tour.json --speed 5 --no-wait --out ios/WalkAndTalk/GPX/mexicali-quick.gpx

One point per second. The walk starts 80 m before stop 1 and ends 80 m past the last stop.
With waiting on, it stands at each stop for the story's length plus a few seconds.
"""

import argparse
import json
import math
from datetime import datetime, timedelta, timezone
from pathlib import Path

from geo import distance_m

LEAD_IN_M = 80   # walk-up distance before the first stop and after the last
EXTRA_WAIT_S = 5


def offset(lat, lon, from_lat, from_lon, extra_m):
    """Point `extra_m` beyond (lat, lon), continuing the line from (from_lat, from_lon)."""
    d = distance_m(from_lat, from_lon, lat, lon) or 1
    k = extra_m / d
    return lat + (lat - from_lat) * k, lon + (lon - from_lon) * k


def leg(a, b, speed):
    """Points from a to b (excluding a), one per second at `speed` m/s."""
    steps = max(1, math.ceil(distance_m(*a, *b) / speed))
    return [(a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps) for i in range(1, steps + 1)]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("tour", type=Path)
    parser.add_argument("--speed", type=float, default=1.4, help="walking speed in m/s (default 1.4)")
    parser.add_argument("--no-wait", action="store_true", help="keep walking instead of waiting at each stop")
    parser.add_argument("--out", type=Path, help="default: ios/WalkAndTalk/GPX/<route>-walk.gpx")
    args = parser.parse_args()

    tour = json.loads(args.tour.read_text())
    stops = tour["stops"]
    coords = [(s["lat"], s["lon"]) for s in stops]
    start = offset(*coords[0], *coords[1], LEAD_IN_M)
    end = offset(*coords[-1], *coords[-2], LEAD_IN_M)

    points = [start]
    for i, stop in enumerate(stops):
        points += leg(points[-1], coords[i], args.speed)
        if not args.no_wait:
            points += [coords[i]] * int(stop["duration_s"] + EXTRA_WAIT_S)
    points += leg(points[-1], end, args.speed)

    # Warn if a leg passes inside a stop that isn't due yet: that stop could play out of order.
    prev = start
    for i, stop in enumerate(stops):
        path = leg(prev, coords[i], 1)  # 1 m steps
        for later in stops[i + 1:]:
            closest = min(distance_m(*p, later["lat"], later["lon"]) for p in path)
            if closest <= later["radius_m"]:
                print(f"warning: walking to {stop['name']} passes {closest:.0f} m from later stop {later['name']}")
        prev = coords[i]

    t0 = datetime(2026, 1, 1, tzinfo=timezone.utc)
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<gpx version="1.1" creator="Walk-and-Talk make_gpx.py" xmlns="http://www.topografix.com/GPX/1/1">']
    lines += [f'  <wpt lat="{lat:.7f}" lon="{lon:.7f}"><time>{(t0 + timedelta(seconds=s)).strftime("%Y-%m-%dT%H:%M:%SZ")}</time></wpt>'
              for s, (lat, lon) in enumerate(points)]
    lines.append("</gpx>")

    out = args.out or Path("ios/WalkAndTalk/GPX") / f"{tour['route']}-walk.gpx"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
    print(f"Wrote {out}: {len(points)} points, {len(points) / 60:.1f} min, {len(stops)} stops")


if __name__ == "__main__":
    main()
