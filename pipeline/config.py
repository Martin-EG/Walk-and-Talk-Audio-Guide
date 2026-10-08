"""Shared settings for the Walk-and-Talk pipeline. Edit values here, not in scripts."""

from pathlib import Path

# Paths
PIPELINE_DIR = Path(__file__).resolve().parent
REPO_DIR = PIPELINE_DIR.parent

# LLM (Gemma via local Ollama)
OLLAMA_URL = "http://localhost:11434"
OLLAMA_MODEL = "gemma3:4b"

# Text-to-speech (Piper, local)
TTS_ENGINE = "piper"
TTS_VOICE = "en_US-lessac-medium"
VOICES_DIR = PIPELINE_DIR / "voices"  # download with: python -m piper.download_voices <voice> --data-dir pipeline/voices

# Tour defaults
LANGUAGE = "en"
TRIGGER_RADIUS_M = 35

# Test point (placeholder: San Francisco Ferry Building). Change to your route start.
TEST_LAT = 37.7955
TEST_LON = -122.3937

# Public data APIs (free, no keys). Wikimedia asks for a descriptive User-Agent.
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
WIKIPEDIA_URL = f"https://{LANGUAGE}.wikipedia.org"
USER_AGENT = "WalkAndTalk/0.1 (https://github.com/Martin-EG/Walk-and-Talk-Audio-Guide)"
