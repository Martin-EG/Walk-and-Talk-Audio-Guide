"""Shared settings for the Walk-and-Talk pipeline. Edit values here, not in scripts."""

from pathlib import Path

# Paths
PIPELINE_DIR = Path(__file__).resolve().parent
REPO_DIR = PIPELINE_DIR.parent
TOURS_DIR = REPO_DIR / "tours"
WORK_DIR = PIPELINE_DIR / "work"    # intermediate JSON per route (stops_raw.json, ...)
NOTES_DIR = PIPELINE_DIR / "notes"  # optional hand-written facts per route: notes/<route>.json
CACHE_DIR = PIPELINE_DIR / "cache"  # HTTP, LLM, and TTS responses; delete to start fresh

# LLM (Gemma via local Ollama)
OLLAMA_URL = "http://localhost:11434"
OLLAMA_MODEL = "gemma3:4b"         # stories for stops with Wikipedia text or notes
THIN_STORY_MODEL = "gemma3:12b"    # stops with only OSM tags: the bigger model obeys "don't invent" better
LLM_TEMPERATURE = 0.3

# Text-to-speech (Piper, local). One voice per tour language.
TTS_ENGINE = "piper"
TTS_VOICES = {
    "en": "en_US-lessac-medium",
    "es": "es_MX-claude-high",
}
TTS_VOICE = TTS_VOICES["en"]  # used by check_env.py
TTS_LENGTH_SCALE = 1.0        # >1.0 speaks slower
VOICES_DIR = PIPELINE_DIR / "voices"  # download with: python -m piper.download_voices <voice> --data-dir pipeline/voices
AAC_BITRATE = "64k"

# Tour defaults
LANGUAGE = "en"
TRIGGER_RADIUS_M = 35
MIN_STOPS = 8
MAX_STOPS = 12
MIN_STOP_SPACING_M = 25
STORY_MIN_WORDS = 80   # stops with Wikipedia text or notes
STORY_MAX_WORDS = 110
THIN_MIN_WORDS = 30    # "thin" stops (only OSM tags): short beats invented
THIN_MAX_WORDS = 80
MAX_AUDIO_SECONDS = 60

# Wikipedia: try the tour language first, then these (Mexicali places are mostly on es.wikipedia).
WIKI_FALLBACK_LANGS = ["es"]
WIKI_MATCH_MAX_M = 1000  # a name-search hit only counts if the article's coordinates are this close

# Test point: Mexicali downtown demo route.
TEST_LAT = 32.661938
TEST_LON = -115.489149

# Public data APIs (free, no keys). Wikimedia asks for a descriptive User-Agent.
OVERPASS_URLS = [  # tried in turn; the public servers often return 504 when busy
    "https://overpass-api.de/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
]
OVERPASS_URL = OVERPASS_URLS[0]  # used by check_env.py
WIKIPEDIA_URL = f"https://{LANGUAGE}.wikipedia.org"
USER_AGENT = "WalkAndTalk/0.1 (https://github.com/Martin-EG/Walk-and-Talk-Audio-Guide)"
