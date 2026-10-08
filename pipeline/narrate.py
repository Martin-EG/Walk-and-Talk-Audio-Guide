"""Step 5: voice each story with Piper (local) and convert it to a small .m4a (AAC).

WAVs are cached by (voice, text), so an unchanged story is never re-synthesized.
Conversion uses ffmpeg when it's installed, otherwise macOS's built-in afconvert.

Reads stories.json and stops_ranked.json, writes tours/<route>/audio/NN-name.m4a and narration.json.

Standalone:  python pipeline/narrate.py --route mexicali --lang en
"""

import argparse
import json
import re
import shutil
import subprocess
import unicodedata
import wave

import cache
import config


def slug(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")[:40]


def load_voice(lang):
    from piper import PiperVoice  # imported here so the other steps don't need Piper

    name = config.TTS_VOICES.get(lang)
    model = config.VOICES_DIR / f"{name}.onnx"
    if not name or not model.exists():
        raise SystemExit(f"No Piper voice for '{lang}'. Download one:\n"
                         f"  python -m piper.download_voices {name or '<voice>'} --data-dir pipeline/voices")
    return name, PiperVoice.load(str(model))


def synthesize(voice_name, voice, text):
    """Return a cached WAV path for this text, rendering it only on a cache miss."""
    from piper import SynthesisConfig

    path = cache.path_for("tts", {"voice": voice_name, "text": text, "length_scale": config.TTS_LENGTH_SCALE}, "wav")
    if cache.ENABLED and path.exists():
        cache.stats["hits"] += 1
        return path
    cache.stats["misses"] += 1
    with wave.open(str(path), "wb") as wav_file:
        voice.synthesize_wav(text, wav_file, syn_config=SynthesisConfig(length_scale=config.TTS_LENGTH_SCALE))
    return path


def to_m4a(wav_path, m4a_path):
    if shutil.which("ffmpeg"):
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path),
               "-c:a", "aac", "-b:a", config.AAC_BITRATE, str(m4a_path)]
    else:  # macOS built-in: m4af container, AAC codec
        bitrate = str(int(config.AAC_BITRATE.rstrip("k")) * 1000)
        cmd = ["afconvert", "-f", "m4af", "-d", "aac", "-b", bitrate, str(wav_path), str(m4a_path)]
    subprocess.run(cmd, check=True)


def run(work_dir, tour_dir, lang):
    stops = json.loads((work_dir / "stops_ranked.json").read_text())
    stories = json.loads((work_dir / "stories.json").read_text())
    voice_name, voice = load_voice(lang)

    audio_dir = tour_dir / "audio"
    if audio_dir.exists():
        shutil.rmtree(audio_dir)  # generated files only; avoids stale audio from an earlier stop list
    audio_dir.mkdir(parents=True)

    results = []
    for i, (stop, story) in enumerate(zip(stops, stories), 1):
        wav_path = synthesize(voice_name, voice, story["story"])
        with wave.open(str(wav_path), "rb") as wav_file:
            duration = wav_file.getnframes() / wav_file.getframerate()
        m4a_name = f"{i:02d}-{slug(stop['name'])}.m4a"
        to_m4a(wav_path, audio_dir / m4a_name)
        size_kb = (audio_dir / m4a_name).stat().st_size / 1024
        results.append({"id": stop["id"], "audio": f"audio/{m4a_name}", "duration_s": round(duration, 1)})
        print(f"  {m4a_name}: {duration:.1f} s, {size_kb:.0f} KB")
    (work_dir / "narration.json").write_text(json.dumps(results, indent=2))
    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--route", required=True)
    parser.add_argument("--lang", default=config.LANGUAGE)
    args = parser.parse_args()
    run(config.WORK_DIR / args.route, config.TOURS_DIR / args.route, args.lang)
