"""Build a complete tour pack with one command: fetch -> wiki -> rank -> stories -> audio -> tour.json.

  python pipeline/build_tour.py --route mexicali --lat 32.661938 --lon -115.489149 --radius 500 --lang en

Output:  tours/<route>/tour.json, tours/<route>/audio/*.m4a, tours/<route>/build_log.txt (appended each run)
Working files (stops_raw.json, review.md, ...):  pipeline/work/<route>/
Every network/LLM/TTS call is cached in pipeline/cache/; pass --no-cache to rebuild from scratch.
"""

import argparse
import json
import time
from datetime import datetime

import cache
import config
import fetch_pois
import fetch_wiki
import narrate
import rank
import validate_tour
import write_stories


def write_tour_json(work_dir, tour_dir, route, lang, lat, lon, radius):
    """Assemble tour.json from the step outputs. Also used by server/app.py."""
    stops = json.loads((work_dir / "stops_ranked.json").read_text())
    stories = json.loads((work_dir / "stories.json").read_text())
    audio = json.loads((work_dir / "narration.json").read_text())
    story_model = config.OLLAMA_MODEL if config.OLLAMA_MODEL == config.THIN_STORY_MODEL else \
        f"{config.OLLAMA_MODEL} + {config.THIN_STORY_MODEL} for thin stops"
    tour = {
        "route": route,
        "language": lang,
        "center": {"lat": lat, "lon": lon},
        "radius_m": radius,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "models": {"story": f"{story_model} (Ollama)", "voice": f"{config.TTS_VOICES[lang]} (Piper)"},
        "stops": [
            {
                "id": stop["id"],
                "name": stop["name"],
                "lat": round(stop["lat"], 7),
                "lon": round(stop["lon"], 7),
                "radius_m": config.TRIGGER_RADIUS_M,
                "audio": sound["audio"],
                "duration_s": sound["duration_s"],
                "story": story["story"],
                "thin_facts": story["thin_facts"],
                "sources": story["sources"],
            }
            for stop, story, sound in zip(stops, stories, audio)
        ],
    }
    tour_path = tour_dir / "tour.json"
    tour_path.write_text(json.dumps(tour, ensure_ascii=False, indent=2))
    return tour_path


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--route", required=True, help='route name, e.g. mexicali or "Los Angeles" (becomes los-angeles)')
    parser.add_argument("--lat", type=float, required=True)
    parser.add_argument("--lon", type=float, required=True)
    parser.add_argument("--radius", type=int, default=500, help="search radius in meters")
    parser.add_argument("--lang", default=config.LANGUAGE, choices=sorted(config.TTS_VOICES))
    parser.add_argument("--exclude", nargs="*", default=[], help="OSM ids to leave out, e.g. way/423032194")
    parser.add_argument("--no-cache", action="store_true", help="ignore cached responses (still refreshes the cache)")
    args = parser.parse_args()
    args.route = narrate.slug(args.route)  # folder-safe: "Los Angeles" -> los-angeles

    cache.ENABLED = not args.no_cache
    work_dir = config.WORK_DIR / args.route
    tour_dir = config.TOURS_DIR / args.route
    work_dir.mkdir(parents=True, exist_ok=True)
    tour_dir.mkdir(parents=True, exist_ok=True)

    steps = [
        ("fetch_pois", lambda: fetch_pois.run(work_dir, args.lat, args.lon, args.radius)),
        ("fetch_wiki", lambda: fetch_wiki.run(work_dir, args.lang, args.lat, args.lon, args.radius)),
        ("rank", lambda: rank.run(work_dir, args.lat, args.lon, set(args.exclude))),
        ("write_stories", lambda: write_stories.run(work_dir, args.lang)),
        ("narrate", lambda: narrate.run(work_dir, tour_dir, args.lang)),
    ]
    timings = []
    started = time.time()
    for name, step in steps:
        print(f"\n[{name}]")
        cache.reset_stats()
        t0 = time.time()
        step()
        timings.append((name, time.time() - t0, dict(cache.stats)))
        print(f"  done in {timings[-1][1]:.1f} s (cache {cache.stats['hits']} hits / {cache.stats['misses']} misses)")

    tour_path = write_tour_json(work_dir, tour_dir, args.route, args.lang, args.lat, args.lon, args.radius)
    tour = json.loads(tour_path.read_text())
    total = time.time() - started

    # Append this run's timings to build_log.txt (kept across runs so first build vs rerun can be compared).
    audio_total = sum(s["duration_s"] for s in tour["stops"])
    lines = [
        f"=== {tour['generated_at']}  route={args.route} lat={args.lat} lon={args.lon} radius={args.radius} "
        f"lang={args.lang} cache={'off' if args.no_cache else 'on'}",
        f"models: {tour['models']['story']}, {tour['models']['voice']}",
    ]
    for name, seconds, stats in timings:
        lines.append(f"{name:<14} {seconds:7.1f} s   cache {stats['hits']} hits / {stats['misses']} misses")
    lines += [
        f"{'total':<14} {total:7.1f} s",
        f"stops: {len(tour['stops'])}, audio: {audio_total:.0f} s total, "
        f"avg story {sum(len(s['story'].split()) for s in tour['stops']) / max(len(tour['stops']), 1):.0f} words",
        "",
    ]
    with open(tour_dir / "build_log.txt", "a") as log:
        log.write("\n".join(lines) + "\n")
    print("\n" + "\n".join(lines))
    print(f"Wrote {tour_path.relative_to(config.REPO_DIR)}. Review stories in {(work_dir / 'review.md').relative_to(config.REPO_DIR)}")

    print("\n[validate]")
    raise SystemExit(validate_tour.validate(tour_path))


if __name__ == "__main__":
    main()
