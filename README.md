# Walk-and-Talk

An offline audio walking tour, built for the DEV "Touch Grass" challenge.

Pick any spot on the map and the app builds a walking tour around it: places come from OpenStreetMap and Wikipedia, Gemma (an open model, via Ollama) writes a short story per stop, and Piper (open text-to-speech) voices it. The app downloads the finished pack (`tour.json` + one audio file per stop) and plays each story as you walk into range, offline and with the phone locked. Only open models, no accounts, no paid AI APIs.

## How it works

```
iPhone app ──HTTPS──▶ tour server (FastAPI + pipeline + Piper) ──private network──▶ Ollama (Gemma)
     ▲                                  │
     └──────── tour pack (zip) ◀────────┘          then: walk offline
```

1. **Pick a spot**: drop a pin on the map or search an address, then choose a radius (200 m–2 km) and 3–12 stops.
2. **Stories are written and recorded**: the server finds places, ranks them into a walking loop, writes a story for each from real facts only, and records it. The app shows each step; a 10-stop tour takes about 6 minutes on Railway's CPUs, about 1.5 on a Mac.
3. **Review and keep**: see the numbered route on a map, keep it or start again.
4. **Walk**: the app plays each stop's story once as you arrive, even in airplane mode.

The same pipeline also runs from the command line on a Mac to build the tours bundled with the app.

## Layout

```
pipeline/   Python steps that build tour packs (used by the CLI and the server)
server/     Tour server: FastAPI + pipeline + Piper, Docker image for Railway
tours/      Tour packs bundled with the app, one folder per route
ios/        Xcode project (SwiftUI app)
docs/       Notes, setup guides, backend measurements, field test
tests/      Smoke-test output (hello.wav)
```

## Setup (Mac)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r pipeline/requirements.txt -r server/requirements.txt
ollama pull gemma3:4b
python -m piper.download_voices en_US-lessac-medium --data-dir pipeline/voices
python pipeline/check_env.py
```

Settings live in `pipeline/config.py`; a few can be overridden with environment variables (the server uses this).

## Run the tour server locally

```bash
API_KEYS=dev-key DATA_DIR=server/data uvicorn --app-dir server app:app --port 8000
```

Then copy `ios/WalkAndTalk/Secrets.example.swift` to `ios/WalkAndTalk/WalkAndTalk/App/Secrets.swift` (git-ignored). Its defaults point the app at `http://localhost:8000` with key `dev-key`, which the Simulator reaches directly. Endpoints, Railway deployment, and curl examples: [server/README.md](server/README.md). Model choice and Railway vs Mac timings: [docs/backend.md](docs/backend.md).

## Build a tour pack from the command line

```bash
python pipeline/build_tour.py --route mexicali --lat 32.661938 --lon -115.489149 --radius 500 --lang en --exclude way/423032194
```

Steps (one file each in `pipeline/`): `fetch_pois` (OSM Overpass) → `fetch_wiki` (Wikipedia summaries) → `rank` (8–12 stops, walking loop) → `write_stories` (Gemma) → `narrate` (Piper → .m4a). Output goes to `tours/<route>/` (`tour.json`, `audio/`, `build_log.txt`); working files and `review.md` (each story next to its facts) go to `pipeline/work/<route>/`. Every network, LLM, and TTS call is cached in `pipeline/cache/`, so reruns take seconds; `--no-cache` rebuilds from scratch. `python pipeline/validate_tour.py tours/<route>/tour.json` checks the pack.

## iOS

The app in `ios/WalkAndTalk` opens on a home screen with **Create a tour**, your saved tours (each with a mini map of its route), and the bundled `mexicali2` demo. Created tours are saved in `Documents/tours/<id>/` and walk exactly like the bundled one. Every screen has an Xcode preview. First-time Xcode setup: [docs/xcode-setup.md](docs/xcode-setup.md). Tests, GPX simulation, and the field test: [docs/walk-test.md](docs/walk-test.md).

## Status

- **Pipeline:** done. Two bundled packs: `mexicali` (12 stops, passes `validate_tour.py`) and `mexicali2` (5 stops, the demo route; fails the 8-stop minimum because the area has few named places).
- **Tour server:** done and deployed on Railway (Ollama private, API key required, one build per key, packs deleted after 24 h). A cold 10-stop build takes 345 s on Railway vs 94 s on a Mac.
- **iOS app:** done. Create a tour (map pin or address search, radius, stops, language), live build progress, route review, saved tours, offline walk mode with proximity triggers and background audio. 15/15 unit tests pass.
- **Field test prep:** done. The app writes a trigger log (`enter`, `trigger`, `closest` per stop) and exports it with the share sheet. Sheet and demo shot list: [docs/field-test.md](docs/field-test.md).
- **Next:** walk a created tour on a phone in airplane mode, tune triggers and stories from the log, record the demo video. Progress checklist: [docs/MVP.md](docs/MVP.md).
