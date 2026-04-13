FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for torch/whisper
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy server code and bundled model
COPY server/ ./server/

# Environment variables (defaults match .env.example / config.py)
ENV AMBIENT_HOST=0.0.0.0
ENV AMBIENT_PORT=8200
ENV AMBIENT_API_KEY=""
ENV WHISPER_MODEL=tiny.en.pt
ENV WHISPER_LANGUAGE=en
ENV OPENAI_API_KEY=""
ENV OPENAI_MODEL=gpt-4o-mini
ENV OPENAI_BASE_URL=https://api.openai.com/v1
ENV AUTO_EXECUTE_THRESHOLD=0.8
ENV SUGGESTION_THRESHOLD=0.5
ENV TRANSCRIPT_BUFFER_SECONDS=45
ENV DEDUP_WINDOW_SECONDS=300
ENV UNDO_WINDOW_SECONDS=1800

EXPOSE 8200

CMD ["python3", "server/main.py"]
