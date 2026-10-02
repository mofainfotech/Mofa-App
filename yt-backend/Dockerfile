FROM python:3.11-slim

# Prevent python from writing pyc files and buffering stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install system dependencies: ffmpeg, curl, nodejs (for yt-dlp JS player deciphering)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY . /app/

# Ensure downloads directory exists with full permissions
RUN mkdir -p /app/downloads && chmod 777 /app/downloads

# Startup script: dynamically binds to $PORT from Render, upgrades yt-dlp, and launches uvicorn
RUN echo '#!/bin/sh' > /start.sh \
    && echo 'PORT="${PORT:-8080}"' >> /start.sh \
    && echo '# Always update yt-dlp on startup to bypass recent YouTube changes' >> /start.sh \
    && echo 'pip install --no-cache-dir --upgrade yt-dlp || true' >> /start.sh \
    && echo 'exec uvicorn main:app --host 0.0.0.0 --port "$PORT" --workers 2' >> /start.sh \
    && chmod +x /start.sh

EXPOSE 8080
CMD ["/start.sh"]
