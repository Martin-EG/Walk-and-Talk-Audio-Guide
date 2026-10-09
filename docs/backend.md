# Tour backend: notes and measurements

The app can now build a tour anywhere: it sends a start point to the server in `server/`, which runs the same pipeline as the Mac (OpenStreetMap + Wikipedia → Gemma via Ollama → Piper), and downloads the pack to walk offline. Setup and API: [server/README.md](../server/README.md).

## Railway setup, and what differed from the plan

- Two services in one project: `ollama` (official image `ollama/ollama:0.40.0`, volume for models, no public domain) and `api` (FastAPI + pipeline + Piper, `server/Dockerfile`, volume for packs). The API calls `http://ollama.railway.internal:11434`; Railway's private network needs plain `http://`.
- Volumes and the private network exist only at runtime, so the model is pulled into Ollama's volume by the API on the first build (54 s for `gemma3:4b`), not baked into an image.
- The Hobby plan is required: Trial/Free allow 0.5–1 GB RAM and 0.5 GB volumes, too small for a 3.3 GB model.
- The API service didn't start until its Dockerfile path was set in the service settings and uvicorn bound to `0.0.0.0` (it printed nothing at all before that).
- **The big one:** inside the container Ollama sees all 48 host cores and starts 48 threads, but the container gets about 8 vCPUs. Prompt processing crawled at 3–8 tokens/s (a single story took over 10 minutes). Setting `OLLAMA_NUM_THREAD=8` (passed as Ollama's `num_thread` option) brought it to ~200 tokens/s.

## Choosing the story model

Same 10 Mexicali stops, one model for every stop, measured with `server/bench_models.py` on the Mac (M-series, Metal GPU):

| model | s/story | output tok/s | prompt tok/s | needed retry | still failing a check | flagged names |
|---|---|---|---|---|---|---|
| gemma3:1b | 1.1 | 118.6 | 3371 | 4 | 3 | 8 |
| gemma3n:e2b | 3.2 | 53.4 | 981 | 3 | 3 | 14 |
| **gemma3:4b** | 3.2 | 42.6 | 1066 | 7 | **0** | **7** |

`gemma3:1b` is three times faster but invents things (a "unique architectural style that remains remarkably intact" that is in no source) and labels its "surprising fact". `gemma3n:e2b` is flat and short. `gemma3:4b` is the smallest model that sticks to the facts, so the server uses it for every stop. (The Mac pipeline still uses `gemma3:12b` for thin stops; it's too slow and too big for the 5 GB Hobby volume on CPU.)

## Railway CPU vs the Mac

10-stop tours, `gemma3:4b`, Piper `en_US-lessac-medium`:

| step | Mac, cold (Mexicali) | Railway, cold (San Diego Gaslamp) | Railway, places cached (Mexicali) |
|---|---|---|---|
| fetch_pois | 26.1 s | 14.9 s | 0 s |
| fetch_wiki | 18.9 s | 48.6 s | 0 s |
| write_stories | 38.4 s | 194.7 s | 152.1 s |
| narrate | 10.7 s | 86.8 s | 50.4 s |
| **total** | **94.3 s** | **345.0 s (5.8 min)** | **202.5 s (3.4 min)** |
| Gemma prompt tok/s | 1129 | 203 | 205 |
| Gemma output tok/s | 40.2 | 13.5 | 14.9 |

Railway is about 3.7× slower end to end and 5× slower at generating text, and still well under the 10-minute target. Story writing dominates; more vCPUs on the `ollama` service (and a matching `OLLAMA_NUM_THREAD`) would cut it further.

The Mexicali Railway pack passes `validate_tour.py`. The San Diego pack fails one check: one story came out at 113 words (limit 110). That's the pipeline's existing word-count rule; `write_stories` keeps its best attempt even when it's slightly over.
