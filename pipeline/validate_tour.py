"""Check a tour pack against the rules and fail loudly. Exit code 0 = valid, 1 = problems found.

  python pipeline/validate_tour.py tours/mexicali/tour.json
"""

import argparse
import itertools
import json
import re
import subprocess
from pathlib import Path

import config
from geo import distance_m

STOP_FIELDS = {"id": str, "name": str, "lat": float, "lon": float, "radius_m": (int, float),
               "audio": str, "duration_s": (int, float), "story": str, "thin_facts": bool, "sources": list}


def audio_seconds(path):
    """Real duration from macOS afinfo; also proves the file decodes. None if unreadable."""
    try:
        out = subprocess.run(["afinfo", str(path)], capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    match = re.search(r"estimated duration: ([\d.]+) sec", out)
    return float(match.group(1)) if match else None


def check(tour, tour_dir):
    errors = []
    for field in ("route", "language", "stops"):
        if field not in tour:
            errors.append(f"tour.json: missing '{field}'")
    stops = tour.get("stops", [])
    if not config.MIN_STOPS <= len(stops) <= config.MAX_STOPS:
        errors.append(f"tour has {len(stops)} stops; need {config.MIN_STOPS}-{config.MAX_STOPS}")

    ids = [s.get("id") for s in stops]
    for dup in {i for i in ids if ids.count(i) > 1}:
        errors.append(f"duplicate stop id {dup}")

    for n, stop in enumerate(stops, 1):
        label = f"stop {n} ({stop.get('name', '?')})"
        missing = [f for f, kind in STOP_FIELDS.items() if not isinstance(stop.get(f), kind)]
        if missing:
            errors.append(f"{label}: missing or wrong type: {', '.join(missing)}")
            continue
        if not (-90 <= stop["lat"] <= 90 and -180 <= stop["lon"] <= 180):
            errors.append(f"{label}: bad coordinates {stop['lat']}, {stop['lon']}")
        if stop["radius_m"] != config.TRIGGER_RADIUS_M:
            errors.append(f"{label}: radius_m is {stop['radius_m']}, expected {config.TRIGGER_RADIUS_M}")

        # Stops with real facts (Wikipedia or notes) get a full story; thin stops are kept short on purpose.
        low, high = ((config.THIN_MIN_WORDS, config.THIN_MAX_WORDS) if stop["thin_facts"]
                     else (config.STORY_MIN_WORDS, config.STORY_MAX_WORDS))
        words = len(stop["story"].split())
        if not low <= words <= high:
            kind = "thin-facts story" if stop["thin_facts"] else "story"
            errors.append(f"{label}: {kind} is {words} words; need {low}-{high}")

        if not stop["sources"] or not all(str(u).startswith("https://") for u in stop["sources"]):
            errors.append(f"{label}: sources must be a non-empty list of https URLs")

        audio_path = tour_dir / stop["audio"]
        if not stop["audio"].endswith(".m4a"):
            errors.append(f"{label}: audio should be .m4a, got {stop['audio']}")
        if not audio_path.exists():
            errors.append(f"{label}: audio file missing: {stop['audio']}")
            continue
        real = audio_seconds(audio_path)
        if real is None:
            errors.append(f"{label}: audio file doesn't decode: {stop['audio']}")
        elif real >= config.MAX_AUDIO_SECONDS:
            errors.append(f"{label}: audio is {real:.1f} s; must be under {config.MAX_AUDIO_SECONDS} s")
        elif abs(real - stop["duration_s"]) > 1.0:
            errors.append(f"{label}: duration_s says {stop['duration_s']} but the file is {real:.1f} s")

    for a, b in itertools.combinations([s for s in stops if isinstance(s.get("lat"), float)], 2):
        gap = distance_m(a["lat"], a["lon"], b["lat"], b["lon"])
        if gap < config.MIN_STOP_SPACING_M:
            errors.append(f"'{a['name']}' and '{b['name']}' are {gap:.0f} m apart; need {config.MIN_STOP_SPACING_M} m")
    return errors


def validate(tour_path):
    tour_path = Path(tour_path)
    errors = check(json.loads(tour_path.read_text()), tour_path.parent)
    if errors:
        print(f"FAIL  {tour_path}: {len(errors)} problem(s)")
        for error in errors:
            print(f"  ✗ {error}")
        return 1
    print(f"PASS  {tour_path}")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("tour_json", help="path to tours/<route>/tour.json")
    raise SystemExit(validate(parser.parse_args().tour_json))
