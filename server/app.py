"""Walk-and-Talk tour server: builds tour packs on request by running the pipeline in ../pipeline.

  POST /tours              {lat, lon, radius_m, max_stops, lang} -> {tour_id}, starts a background build
  GET  /tours/{id}         status, progress ("3/10"), stops_found, error
  GET  /tours/{id}/preview stop names and coordinates, as soon as ranking finishes
  GET  /tours/{id}/pack    zip of tour.json + audio/ (+ build_log.txt)

Every /tours request needs the header  X-API-Key: <one of API_KEYS>.
Builds run one at a time (the CPU is the bottleneck; two builds would just slow each other down),
and each key can have only one build queued or running.

Run locally (from the repo root, with Ollama running):
  API_KEYS=dev-key DATA_DIR=server/data uvicorn --app-dir server app:app --port 8000

Environment:
  API_KEYS        comma-separated shared secrets (required)
  DATA_DIR        where tours, jobs, work files and the cache live (a Railway volume in production)
  OLLAMA_URL      e.g. http://ollama.railway.internal:11434
  OLLAMA_MODEL    story model for every stop, e.g. gemma3:4b
  PACK_TTL_HOURS  packs older than this are deleted (default 24)
"""

import hashlib
import hmac
import json
import logging
import os
import queue
import shutil
import sys
import threading
import time
import uuid
import zipfile
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from typing import Literal

import requests
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

# --- Paths and pipeline settings. Set before importing the pipeline: config.py reads them at import time.
SERVER_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.environ.get("DATA_DIR", SERVER_DIR / "data")).resolve()
TOURS_DIR = DATA_DIR / "tours"
JOBS_DIR = DATA_DIR / "jobs"
os.environ["WT_TOURS_DIR"] = str(TOURS_DIR)
os.environ["WT_WORK_DIR"] = str(DATA_DIR / "work")
os.environ["WT_CACHE_DIR"] = str(DATA_DIR / "cache")
# One model for every stop: the pipeline's bigger "thin stop" model is too slow on a CPU-only server.
os.environ.setdefault("THIN_STORY_MODEL", os.environ.get("OLLAMA_MODEL", "gemma3:4b"))
sys.path.insert(0, str(SERVER_DIR.parent / "pipeline"))

import build_tour  # noqa: E402  (pipeline modules, imported after the env is set)
import cache  # noqa: E402
import config  # noqa: E402
import fetch_pois  # noqa: E402
import fetch_wiki  # noqa: E402
import narrate  # noqa: E402
import rank  # noqa: E402
import write_stories  # noqa: E402

API_KEYS = [k.strip() for k in os.environ.get("API_KEYS", "").split(",") if k.strip()]
PACK_TTL_S = float(os.environ.get("PACK_TTL_HOURS", "24")) * 3600
ACTIVE = {"queued", "finding_places", "writing_stories", "recording"}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("walkandtalk")

jobs = {}  # tour_id -> job dict (also saved as JOBS_DIR/<id>.json so status survives a restart)
jobs_lock = threading.Lock()
build_queue = queue.Queue()


# --- Requests and auth

class TourRequest(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    radius_m: int = Field(ge=200, le=2000)
    max_stops: int = Field(ge=3, le=12)
    lang: Literal["en", "es"] = "en"


def key_id(key):
    """Short hash of a key, so job files never contain the key itself."""
    return hashlib.sha256(key.encode()).hexdigest()[:12]


def require_key(x_api_key: str = Header(default="")):
    if not any(hmac.compare_digest(x_api_key, k) for k in API_KEYS):
        raise HTTPException(401, "Missing or wrong X-API-Key header.")
    return key_id(x_api_key)


# --- Job state

def save(job):
    """Write a job to disk. Call with jobs_lock held."""
    path = JOBS_DIR / f"{job['tour_id']}.json"
    path.with_suffix(".tmp").write_text(json.dumps(job, indent=1))
    path.with_suffix(".tmp").replace(path)


def update(tour_id, **fields):
    with jobs_lock:
        jobs[tour_id].update(fields)
        save(jobs[tour_id])


def get_job(tour_id, key):
    with jobs_lock:
        job = jobs.get(tour_id)
        if not job or job["key"] != key:
            raise HTTPException(404, "No tour with that id (packs are deleted after 24 hours).")
        return dict(job)


# --- The build, one step at a time

def ensure_model(model):
    """Pull the story model into Ollama's volume if it isn't there yet (first build only)."""
    tags = requests.get(f"{config.OLLAMA_URL}/api/tags", timeout=10).json()
    if any(m["name"] == model for m in tags.get("models", [])):
        return
    log.info("pulling %s into Ollama (first build only)", model)
    resp = requests.post(f"{config.OLLAMA_URL}/api/pull", json={"model": model, "stream": False}, timeout=1800)
    resp.raise_for_status()


def build(job):
    tour_id, req = job["tour_id"], job["request"]
    work_dir = config.WORK_DIR / tour_id
    tour_dir = TOURS_DIR / tour_id
    work_dir.mkdir(parents=True, exist_ok=True)
    tour_dir.mkdir(parents=True, exist_ok=True)
    timings = []

    def step(name, fn):
        cache.reset_stats()
        t0 = time.time()
        result = fn()
        seconds = time.time() - t0
        timings.append((name, seconds, dict(cache.stats)))
        log.info("tour %s step %-14s %7.1f s  cache %d hits / %d misses",
                 tour_id, name, seconds, cache.stats["hits"], cache.stats["misses"])
        return result

    def progress(done, total):
        update(tour_id, progress=f"{done}/{total}")

    started = time.time()
    update(tour_id, status="finding_places", started_at=started)
    try:
        step("ollama_ready", lambda: ensure_model(config.OLLAMA_MODEL))
    except requests.RequestException as e:
        raise RuntimeError(f"The story model isn't reachable at {config.OLLAMA_URL}: {e}")
    step("fetch_pois", lambda: fetch_pois.run(work_dir, req["lat"], req["lon"], req["radius_m"]))
    step("fetch_wiki", lambda: fetch_wiki.run(work_dir, req["lang"], req["lat"], req["lon"], req["radius_m"]))
    route = step("rank", lambda: rank.run(work_dir, req["lat"], req["lon"], max_stops=req["max_stops"]))
    if not route:
        raise RuntimeError(f"No places found within {req['radius_m']} m. Try a bigger radius or another start point.")
    preview = [{"id": s["id"], "name": s["name"], "lat": s["lat"], "lon": s["lon"]} for s in route]
    update(tour_id, status="writing_stories", progress=f"0/{len(route)}", stops_found=len(route), preview=preview)

    step("write_stories", lambda: write_stories.run(work_dir, req["lang"], on_progress=progress))
    update(tour_id, status="recording", progress=f"0/{len(route)}")
    step("narrate", lambda: narrate.run(work_dir, tour_dir, req["lang"], on_progress=progress))

    tour_path = build_tour.write_tour_json(work_dir, tour_dir, tour_id, req["lang"],
                                           req["lat"], req["lon"], req["radius_m"])
    total = time.time() - started
    write_log(tour_dir, tour_id, req, json.loads(tour_path.read_text()), timings, total)
    with zipfile.ZipFile(tour_dir.with_suffix(".zip"), "w", zipfile.ZIP_DEFLATED) as pack:
        for path in sorted(tour_dir.rglob("*")):
            if path.is_file():
                pack.write(path, path.relative_to(tour_dir).as_posix())
    update(tour_id, status="done", total_s=round(total, 1),
           step_s={name: round(seconds, 1) for name, seconds, _ in timings})
    log.info("tour %s done in %.1f s, %d stops", tour_id, total, len(route))


def write_log(tour_dir, tour_id, req, tour, timings, total):
    """Same format as the pipeline's build_log.txt, plus the server's CPU count and Gemma's speed."""
    calls = write_stories.llm_calls
    out_tokens = sum(c["output_tokens"] for c in calls)
    out_s = sum(c["output_s"] for c in calls)
    prompt_tokens = sum(c["prompt_tokens"] for c in calls)
    prompt_s = sum(c["prompt_s"] for c in calls)
    lines = [
        f"=== {tour['generated_at']}  route={tour_id} lat={req['lat']} lon={req['lon']} radius={req['radius_m']} "
        f"max_stops={req['max_stops']} lang={req['lang']} host={os.environ.get('RAILWAY_SERVICE_NAME', 'local')} "
        f"host_cpus={os.cpu_count()} ollama_threads={config.LLM_NUM_THREAD or 'auto'}",
        f"models: {tour['models']['story']}, {tour['models']['voice']}",
    ]
    for name, seconds, stats in timings:
        lines.append(f"{name:<14} {seconds:7.1f} s   cache {stats['hits']} hits / {stats['misses']} misses")
    lines += [
        f"{'total':<14} {total:7.1f} s",
        f"stops: {len(tour['stops'])}, audio: {sum(s['duration_s'] for s in tour['stops']):.0f} s total",
        f"gemma: {len(calls)} calls, prompt {prompt_tokens} tok at {prompt_tokens / max(prompt_s, 1e-9):.1f} tok/s, "
        f"output {out_tokens} tok at {out_tokens / max(out_s, 1e-9):.1f} tok/s",
        "",
    ]
    (tour_dir / "build_log.txt").write_text("\n".join(lines) + "\n")
    log.info("tour %s timings:\n%s", tour_id, "\n".join(lines))


def worker():
    while True:
        tour_id = build_queue.get()
        with jobs_lock:
            job = dict(jobs.get(tour_id) or {})
        if not job:
            continue  # cleaned up while queued
        try:
            build(job)
        except (Exception, SystemExit) as e:  # pipeline steps raise SystemExit for setup problems
            log.exception("tour %s failed", tour_id)
            update(tour_id, status="failed", error=str(e) or type(e).__name__)


def cleanup():
    """Delete packs, work files and cache entries older than PACK_TTL_HOURS. Runs hourly."""
    while True:
        cutoff = time.time() - PACK_TTL_S
        with jobs_lock:
            expired = [j for j in jobs.values() if j["created_at"] < cutoff and j["status"] not in ACTIVE]
            for job in expired:
                jobs.pop(job["tour_id"])
                (JOBS_DIR / f"{job['tour_id']}.json").unlink(missing_ok=True)
        for job in expired:
            shutil.rmtree(TOURS_DIR / job["tour_id"], ignore_errors=True)
            (TOURS_DIR / f"{job['tour_id']}.zip").unlink(missing_ok=True)
            shutil.rmtree(config.WORK_DIR / job["tour_id"], ignore_errors=True)
        for path in config.CACHE_DIR.rglob("*"):
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink(missing_ok=True)
        if expired:
            log.info("cleanup: deleted %d expired tours", len(expired))
        time.sleep(3600)


@asynccontextmanager
async def lifespan(app):
    if not API_KEYS:
        raise RuntimeError("Set API_KEYS (comma-separated shared secrets) before starting the server.")
    for folder in (TOURS_DIR, JOBS_DIR, config.WORK_DIR, config.CACHE_DIR):
        folder.mkdir(parents=True, exist_ok=True)
    for path in JOBS_DIR.glob("*.json"):
        job = json.loads(path.read_text())
        if job["status"] in ACTIVE:  # the server restarted mid-build
            job.update(status="failed", error="The server restarted during the build. Please try again.")
        jobs[job["tour_id"]] = job
        save(job)
    threading.Thread(target=worker, daemon=True).start()
    threading.Thread(target=cleanup, daemon=True).start()
    log.info("ready: data=%s ollama=%s model=%s keys=%d", DATA_DIR, config.OLLAMA_URL, config.OLLAMA_MODEL, len(API_KEYS))
    yield


app = FastAPI(title="Walk-and-Talk tour server", lifespan=lifespan)


# --- Endpoints

@app.get("/health")
def health():
    return {"ok": True}


@app.post("/tours")
def create_tour(req: TourRequest, key: str = Depends(require_key)):
    with jobs_lock:
        running = [j for j in jobs.values() if j["key"] == key and j["status"] in ACTIVE]
        if running:
            # The app uses tour_id to go back to watching that build instead of starting another.
            raise HTTPException(409, {"message": "A tour is already building.", "tour_id": running[0]["tour_id"]})
        tour_id = datetime.now().strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:6]
        jobs[tour_id] = {
            "tour_id": tour_id, "key": key, "request": req.model_dump(), "created_at": time.time(),
            "status": "queued", "progress": "", "stops_found": None, "error": None, "preview": None,
        }
        save(jobs[tour_id])
    build_queue.put(tour_id)
    log.info("tour %s queued: %s", tour_id, req.model_dump())
    return {"tour_id": tour_id}


@app.get("/tours/{tour_id}")
def tour_status(tour_id: str, key: str = Depends(require_key)):
    job = get_job(tour_id, key)
    return {"tour_id": tour_id, "status": job["status"], "progress": job["progress"],
            "stops_found": job["stops_found"], "error": job["error"],
            "total_s": job.get("total_s"), "step_s": job.get("step_s")}


@app.get("/tours/{tour_id}/preview")
def tour_preview(tour_id: str, key: str = Depends(require_key)):
    job = get_job(tour_id, key)
    if job["preview"] is None:
        raise HTTPException(409, f"Stops aren't ranked yet (status: {job['status']}).")
    return {"tour_id": tour_id, "stops": job["preview"]}


@app.get("/tours/{tour_id}/pack")
def tour_pack(tour_id: str, key: str = Depends(require_key)):
    job = get_job(tour_id, key)
    if job["status"] != "done":
        raise HTTPException(409, f"The pack isn't ready (status: {job['status']}).")
    return FileResponse(TOURS_DIR / f"{tour_id}.zip", media_type="application/zip", filename=f"{tour_id}.zip")
