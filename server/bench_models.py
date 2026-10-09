"""Compare story models on one ranked stop list: speed, and how often stories break the pipeline's checks.

  python server/bench_models.py <work_dir> gemma3:1b gemma3:4b gemma3n:e2b [--lang en]

<work_dir> is a finished build's work folder (it has stops_ranked.json), e.g. server/data/work/<tour_id>
locally or /data/work/<tour_id> on Railway (run it there with `railway ssh --service api`).
Missing models are pulled first. The LLM cache is ignored so every story is really generated.
Each model's stories go to bench/<model>/review.md next to the work folder, for reading side by side.
"""

import argparse
import os
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "pipeline"))

import requests  # noqa: E402

import cache  # noqa: E402
import config  # noqa: E402
import write_stories  # noqa: E402


def pull(model):
    tags = requests.get(f"{config.OLLAMA_URL}/api/tags", timeout=10).json()
    if not any(m["name"] == model for m in tags.get("models", [])):
        print(f"pulling {model} ...")
        requests.post(f"{config.OLLAMA_URL}/api/pull", json={"model": model, "stream": False}, timeout=1800).raise_for_status()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("models", nargs="+")
    parser.add_argument("--lang", default="en")
    args = parser.parse_args()
    cache.ENABLED = False

    rows = []
    for model in args.models:
        pull(model)
        config.OLLAMA_MODEL = config.THIN_STORY_MODEL = model  # one model for every stop, like the server
        out = args.work_dir.parent / "bench" / model.replace(":", "-")
        shutil.rmtree(out, ignore_errors=True)
        out.mkdir(parents=True)
        for name in ("stops_ranked.json", "area.json"):
            if (args.work_dir / name).exists():
                shutil.copy(args.work_dir / name, out / name)

        # Warm-up call so model load time isn't counted against the first story.
        write_stories.chat([{"role": "user", "content": "Say OK."}], model)
        print(f"\n[{model}]")
        t0 = time.time()
        stories = write_stories.run(out, args.lang)
        seconds = time.time() - t0
        calls = write_stories.llm_calls
        out_tok = sum(c["output_tokens"] for c in calls)
        prompt_tok = sum(c["prompt_tokens"] for c in calls)
        rows.append({
            "model": model, "stories": len(stories), "seconds": seconds,
            "per_story": seconds / max(len(stories), 1),
            "out_tps": out_tok / max(sum(c["output_s"] for c in calls), 1e-9),
            "prompt_tps": prompt_tok / max(sum(c["prompt_s"] for c in calls), 1e-9),
            "retries": sum(1 for s in stories if s["attempts"] > 1),
            "problems": sum(1 for s in stories if s["problems"]),
            "flagged": sum(len(s["check_names"]) for s in stories),
            "words": sum(s["words"] for s in stories) / max(len(stories), 1),
        })

    print(f"\nhost={os.environ.get('RAILWAY_SERVICE_NAME', 'local')} cpus={os.cpu_count()} ollama={config.OLLAMA_URL}")
    print(f"{'model':<14} {'stories':>7} {'total s':>8} {'s/story':>8} {'out tok/s':>9} {'prompt tok/s':>12} "
          f"{'retried':>7} {'failed':>6} {'flagged':>7} {'avg words':>9}")
    for r in rows:
        print(f"{r['model']:<14} {r['stories']:>7} {r['seconds']:>8.1f} {r['per_story']:>8.1f} {r['out_tps']:>9.1f} "
              f"{r['prompt_tps']:>12.1f} {r['retries']:>7} {r['problems']:>6} {r['flagged']:>7} {r['words']:>9.0f}")
    print("\nretried = needed the second attempt; failed = still broke a check after it; "
          "flagged = capitalized words not in the facts (possible invented names).")
    print(f"Read the stories: {args.work_dir.parent / 'bench'}/<model>/review.md")


if __name__ == "__main__":
    main()
