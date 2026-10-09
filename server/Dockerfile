# Walk-and-Talk API: FastAPI + the pipeline + Piper. Build from the repo root:
#   Railway: set RAILWAY_DOCKERFILE_PATH=server/Dockerfile on the api service.
FROM python:3.12-slim

# ffmpeg converts Piper's WAV to .m4a (narrate.py); macOS's afconvert isn't available on Linux.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pipeline/requirements.txt pipeline/requirements.txt
COPY server/requirements.txt server/requirements.txt
RUN pip install --no-cache-dir -r pipeline/requirements.txt -r server/requirements.txt

# Voices are baked into the image (downloads work at build time; volumes and private networking don't).
ENV WT_VOICES_DIR=/app/voices
RUN python -m piper.download_voices en_US-lessac-medium es_MX-claude-high --data-dir /app/voices

COPY pipeline pipeline
COPY server server

ENV DATA_DIR=/data PYTHONUNBUFFERED=1
# Public traffic arrives over IPv4 through Railway's proxy. Railway sets PORT.
CMD ["sh", "-c", "echo \"starting api on port ${PORT:-8000}\" && exec uvicorn --app-dir server app:app --host 0.0.0.0 --port ${PORT:-8000}"]
