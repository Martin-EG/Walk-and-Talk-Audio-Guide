"""Tiny on-disk cache. Every network, LLM, and TTS call goes through here so reruns are fast.

Keys are hashed into file names under pipeline/cache/<kind>/. Set ENABLED = False
(build_tour.py --no-cache) to ignore existing entries and rebuild from scratch.
"""

import hashlib
import json

import config

ENABLED = True
stats = {"hits": 0, "misses": 0}


def path_for(kind, key, ext):
    digest = hashlib.sha1(json.dumps(key, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    folder = config.CACHE_DIR / kind
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{digest}.{ext}"


def get_json(kind, key):
    """Return the cached value, or None on a miss."""
    path = path_for(kind, key, "json")
    if ENABLED and path.exists():
        stats["hits"] += 1
        return json.loads(path.read_text())
    stats["misses"] += 1
    return None


def put_json(kind, key, value):
    path_for(kind, key, "json").write_text(json.dumps(value, ensure_ascii=False, indent=1))
    return value


def reset_stats():
    stats["hits"] = 0
    stats["misses"] = 0
