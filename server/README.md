# Tour server

Builds tour packs on request with the pipeline in `../pipeline/`: Gemma (Ollama) writes the stories, Piper voices them. The iOS app asks for a tour, polls progress, downloads the pack, and walks it offline.

```
iPhone ──HTTPS──▶ api (FastAPI + pipeline + Piper, volume /data) ──private network──▶ ollama (Gemma, volume /root/.ollama)
```

## Endpoints

Every `/tours` request needs `X-API-Key: <key>`.

| Method | Path | Returns |
|---|---|---|
| POST | `/tours` `{lat, lon, radius_m, max_stops, lang}` | `{tour_id}` and starts the build. 422 if radius isn't 200–2000 or stops aren't 3–12; 409 `{message, tour_id}` if this key already has a build running |
| GET | `/tours/{id}` | `{status, progress, stops_found, error, total_s, step_s}`; status is `queued`, `finding_places`, `writing_stories`, `recording`, `done` or `failed` |
| GET | `/tours/{id}/preview` | stop names and coordinates, once ranking is done (409 before) |
| GET | `/tours/{id}/pack` | zip of `tour.json`, `audio/`, `build_log.txt` (409 until done) |
| GET | `/health` | `{ok: true}`, no key needed |

Builds run one at a time. If an area has fewer places than `max_stops`, the tour uses what it finds (`stops_found`); zero places fails with "No places found". Packs, work files and cache entries are deleted after 24 hours. Each build logs its step times and Gemma's tokens/s to the Railway logs and to the pack's `build_log.txt`.

## Run locally (Mac)

```bash
source .venv/bin/activate
pip install -r server/requirements.txt
API_KEYS=dev-key DATA_DIR=server/data uvicorn --app-dir server app:app --port 8000
```

In the app, `ios/WalkAndTalk/WalkAndTalk/App/Secrets.swift` (git-ignored; copy `ios/WalkAndTalk/Secrets.example.swift`) points at `http://localhost:8000` with key `dev-key`.

## Railway

Project `walk-and-talk`, two services in `production`:

- **ollama**: image `ollama/ollama:0.40.0`, volume at `/root/.ollama`, **no public domain** (reachable only at `ollama.railway.internal`). Variables: `OLLAMA_HOST=[::]:11434` (listen on the private network, IPv4 and IPv6), `OLLAMA_KEEP_ALIVE=5m` (unload the model when idle), `OLLAMA_NUM_PARALLEL=1`.
- **api**: built from `server/Dockerfile` (`RAILWAY_DOCKERFILE_PATH=server/Dockerfile`), volume at `/data`, public Railway domain, health check `/health`. Variables: `API_KEYS`, `OLLAMA_URL=http://ollama.railway.internal:11434`, `OLLAMA_MODEL=gemma3:4b`, `OLLAMA_NUM_THREAD=8` (match the vCPUs Ollama really gets; without it Ollama uses every host core and slows to a crawl), `PORT=8080`. In service settings: Dockerfile path `server/Dockerfile`.

Deploy the API from the repo root:

```bash
railway up --service api --detach
```

The first build pulls the model into Ollama's volume (about 3 GB, once). Private networking and volumes only exist at runtime, which is why the model is pulled by the API on first use rather than baked into an image.

Try it:

```bash
export API=https://<api domain> KEY=<API_KEYS value>
curl -s -X POST $API/tours -H "X-API-Key: $KEY" -H 'content-type: application/json' \
  -d '{"lat":32.661938,"lon":-115.489149,"radius_m":600,"max_stops":10,"lang":"en"}'
curl -s $API/tours/<tour_id> -H "X-API-Key: $KEY"
curl -s -o pack.zip $API/tours/<tour_id>/pack -H "X-API-Key: $KEY"
unzip -o pack.zip -d pack && python pipeline/validate_tour.py pack/tour.json
```

## Choosing the model

`server/bench_models.py <work_dir> <models...>` runs `write_stories` for each model on the same ranked stops and prints speed and how many stories broke the pipeline's checks. Results are in [docs/backend.md](../docs/backend.md).
