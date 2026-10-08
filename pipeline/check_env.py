"""Smoke test: prove the LLM, TTS, Overpass, and Wikipedia all work from this Mac.

Run from repo root:  python pipeline/check_env.py
"""

import time
import wave
from urllib.parse import quote

import requests

import config

TESTS_DIR = config.REPO_DIR / "tests"
HELLO_WAV = TESTS_DIR / "hello.wav"
HEADERS = {"User-Agent": config.USER_AGENT}


def check_llm():
    prompt = "In one sentence, invite a walker to look up at an old building."
    start = time.time()
    resp = requests.post(
        f"{config.OLLAMA_URL}/api/generate",
        json={"model": config.OLLAMA_MODEL, "prompt": prompt, "stream": False},
        timeout=300,
    )
    resp.raise_for_status()
    reply = resp.json()["response"].strip()
    seconds = time.time() - start
    print(f"  model:   {config.OLLAMA_MODEL}")
    print(f"  reply:   {reply}")
    print(f"  seconds: {seconds:.1f}")
    return bool(reply)


def check_tts():
    from piper import PiperVoice  # imported here so other checks still run if Piper is missing

    model_path = config.VOICES_DIR / f"{config.TTS_VOICE}.onnx"
    voice = PiperVoice.load(str(model_path))
    TESTS_DIR.mkdir(exist_ok=True)
    with wave.open(str(HELLO_WAV), "wb") as wav_file:
        voice.synthesize_wav("Hello from the trail", wav_file)

    with wave.open(str(HELLO_WAV), "rb") as wav_file:
        duration = wav_file.getnframes() / wav_file.getframerate()
    print(f"  file:     {HELLO_WAV.relative_to(config.REPO_DIR)}")
    print(f"  duration: {duration:.2f} s")
    return duration > 0.5


def check_overpass():
    query = f"""
    [out:json][timeout:25];
    (
      node(around:300,{config.TEST_LAT},{config.TEST_LON})[name][~"^(tourism|historic|amenity)$"~"."];
      way(around:300,{config.TEST_LAT},{config.TEST_LON})[name][~"^(tourism|historic)$"~"."];
    );
    out center;
    """
    resp = requests.post(config.OVERPASS_URL, data={"data": query}, headers=HEADERS, timeout=60)
    resp.raise_for_status()
    places = resp.json()["elements"]
    print(f"  places within 300 m: {len(places)}")
    for place in places[:3]:
        print(f"    - {place['tags'].get('name')}")
    return len(places) > 0


def check_wikipedia():
    # Step 1: find the nearest article to the point (geosearch).
    resp = requests.get(
        f"{config.WIKIPEDIA_URL}/w/api.php",
        params={
            "action": "query",
            "list": "geosearch",
            "gscoord": f"{config.TEST_LAT}|{config.TEST_LON}",
            "gsradius": 1000,
            "gslimit": 1,
            "format": "json",
        },
        headers=HEADERS,
        timeout=30,
    )
    resp.raise_for_status()
    title = resp.json()["query"]["geosearch"][0]["title"]

    # Step 2: fetch its REST summary.
    resp = requests.get(
        f"{config.WIKIPEDIA_URL}/api/rest_v1/page/summary/{quote(title.replace(' ', '_'))}",
        headers=HEADERS,
        timeout=30,
    )
    resp.raise_for_status()
    summary = resp.json()
    print(f"  title:   {summary['title']}")
    print(f"  extract: {summary['extract'][:120]}...")
    return bool(summary.get("extract"))


def main():
    checks = [
        ("LLM", check_llm),
        ("TTS", check_tts),
        ("Overpass", check_overpass),
        ("Wikipedia", check_wikipedia),
    ]
    results = []
    for name, fn in checks:
        print(f"\n[{name}]")
        try:
            ok = fn()
            error = ""
        except Exception as exc:
            ok = False
            error = f" ({type(exc).__name__}: {exc})"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}{error}")

    print(f"\n{sum(results)}/{len(results)} checks passed")
    raise SystemExit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
