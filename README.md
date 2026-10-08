# Walk-and-Talk

An offline audio walking tour, built for the DEV "Touch Grass" challenge.

Python scripts on a Mac pull points of interest from OpenStreetMap and Wikipedia, Gemma (local, via Ollama) writes a short story per stop, and Piper (local) voices it. The result is a tour pack (`tour.json` + one audio file per stop) that a SwiftUI iPhone app bundles and plays when you walk within range. No backend, no accounts, no paid AI APIs.

## Layout

```
pipeline/   Python scripts that build tour packs
tours/      Generated tour packs, one folder per route
ios/        Xcode project (SwiftUI app)
docs/       Notes, setup guides, field test
tests/      Smoke-test output (hello.wav)
```

## Setup (Mac)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r pipeline/requirements.txt
ollama pull gemma3:4b
python -m piper.download_voices en_US-lessac-medium --data-dir pipeline/voices
python pipeline/check_env.py
```

Settings live in `pipeline/config.py`.

## Build a tour pack

```bash
python pipeline/build_tour.py --route mexicali --lat 32.661938 --lon -115.489149 --radius 500 --lang en --exclude way/423032194
```

Steps (one file each in `pipeline/`): `fetch_pois` (OSM Overpass) → `fetch_wiki` (Wikipedia summaries) → `rank` (8–12 stops, walking loop) → `write_stories` (Gemma) → `narrate` (Piper → .m4a). Output goes to `tours/<route>/` (`tour.json`, `audio/`, `build_log.txt`); working files and `review.md` (each story next to its facts) go to `pipeline/work/<route>/`. Every network, LLM, and TTS call is cached in `pipeline/cache/`, so reruns take seconds; `--no-cache` rebuilds from scratch. `python pipeline/validate_tour.py tours/<route>/tour.json` checks the pack.

## iOS

See [docs/xcode-setup.md](docs/xcode-setup.md).

## Status

Day 1: toolchain smoke test. Tour generation and location triggers coming next.
