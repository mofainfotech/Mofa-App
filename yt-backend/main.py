import os
import re
import sys
import time
import glob
import shutil
import hashlib
import asyncio
import platform
import subprocess
from urllib.parse import quote, unquote
from typing import Optional

from fastapi import FastAPI, Request, Query, Form, UploadFile, File, HTTPException, Header
from fastapi.responses import HTMLResponse, JSONResponse, FileResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

import yt_dlp
import yt_dlp.version

# Base directories
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DOWNLOADS_DIR = os.path.join(BASE_DIR, "downloads")
COOKIE_FILE = os.path.join(BASE_DIR, "cookies.txt")

os.makedirs(DOWNLOADS_DIR, exist_ok=True)

# Cookie Handling (Environment variable takes precedence over existing local file)
env_cookies = os.getenv("YOUTUBE_COOKIES")
if env_cookies and env_cookies.strip():
    try:
        with open(COOKIE_FILE, "w", encoding="utf-8") as f:
            f.write(env_cookies.strip() + "\n")
    except Exception as e:
        print(f"Warning: Could not write YOUTUBE_COOKIES to cookie file: {e}")

# Tool & runtime detection
FFMPEG_PATH = shutil.which("ffmpeg")
if not FFMPEG_PATH and os.name == "nt":
    win_ffmpeg = r"C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe"
    if os.path.exists(win_ffmpeg):
        FFMPEG_PATH = win_ffmpeg

NODE_PATH = shutil.which("node")
NODE_VERSION = None
if NODE_PATH:
    try:
        node_out = subprocess.check_output([NODE_PATH, "--version"], stderr=subprocess.DEVNULL).decode().strip()
        NODE_VERSION = node_out
    except Exception:
        NODE_VERSION = None

EJS_VERSION = None
try:
    import yt_dlp_ejs
    EJS_VERSION = getattr(yt_dlp_ejs, "__version__", getattr(yt_dlp_ejs, "version", "available"))
except ImportError:
    EJS_VERSION = None

# Startup Diagnostics (Safe: NEVER log cookie content or secrets)
print("=" * 60)
print("Starting PulseTube Python Backend...")
print(f"  Python:          {platform.python_version()}")
print(f"  yt-dlp:          {yt_dlp.version.__version__}")
print(f"  yt-dlp-ejs:      {EJS_VERSION if EJS_VERSION else 'missing'}")
print(f"  FFmpeg:          {'installed (' + FFMPEG_PATH + ')' if FFMPEG_PATH else 'missing'}")
print(f"  Node.js:         {f'{NODE_VERSION} ({NODE_PATH})' if NODE_VERSION else 'missing'}")
print(f"  PO Token status: none (not required for standard clients)")
if os.path.exists(COOKIE_FILE) and os.path.getsize(COOKIE_FILE) > 10:
    print(f"  YouTube cookies: available (Cookie file: {COOKIE_FILE}, size: {os.path.getsize(COOKIE_FILE)} bytes)")
else:
    print("  WARNING: YouTube cookies are not configured.")
print("=" * 60)

app = FastAPI(
    title="PulseTube Python YouTube Downloader Backend",
    description="High-performance YouTube Downloader & Streamer API built with FastAPI, yt-dlp & FFmpeg",
    version="2.0.0"
)

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount downloads directory for direct static access with Range header support
app.mount("/downloads", StaticFiles(directory=DOWNLOADS_DIR), name="downloads")


def get_cookie_file() -> Optional[str]:
    """Returns cookie file path if valid."""
    if os.path.exists(COOKIE_FILE) and os.path.getsize(COOKIE_FILE) > 10:
        return COOKIE_FILE
    return None


def sanitize_filename(name: str) -> str:
    """Sanitize title for safe filesystem and HTTP header usage."""
    cleaned = re.sub(r'[^\w\s\-\.\(\)]', '_', name)
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    return cleaned or "YouTube_Media"


def clean_youtube_url(url: str) -> str:
    """Strip playlist and tracking query parameters."""
    url = re.sub(r'&list=[^&]+', '', url)
    url = re.sub(r'&index=[^&]+', '', url)
    url = re.sub(r'&start_radio=[^&]+', '', url)
    return url


def download_cdn_file(url: str, target_path: str) -> bool:
    """Downloads a direct stream from GoogleVideo CDN using streaming requests with curl fallback."""
    user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    try:
        import requests
        with requests.get(url, headers={"User-Agent": user_agent}, stream=True, timeout=120) as r:
            r.raise_for_status()
            with open(target_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        f.write(chunk)
        if os.path.exists(target_path) and os.path.getsize(target_path) > 0:
            return True
    except Exception as e:
        print(f"requests download encountered {e}, attempting curl fallback...")

    # Fallback to curl
    subprocess.run(["curl", "-sL", "-A", user_agent, url, "-o", target_path], check=False)
    return os.path.exists(target_path) and os.path.getsize(target_path) > 0


def cleanup_old_downloads(max_age_seconds: int = 7200, max_dir_size_mb: int = 2048):
    """Periodically cleans up old files from downloads directory."""
    try:
        now = time.time()
        total_size = 0
        files = []
        for entry in os.scandir(DOWNLOADS_DIR):
            if entry.is_file():
                stat = entry.stat()
                total_size += stat.st_size
                files.append((entry.path, stat.st_mtime, stat.st_size))

        # Delete files older than max_age_seconds
        for path, mtime, size in files:
            if now - mtime > max_age_seconds:
                try:
                    os.remove(path)
                    total_size -= size
                except Exception:
                    pass

        # If still exceeding size limit, delete oldest files first
        if total_size > max_dir_size_mb * 1024 * 1024:
            files.sort(key=lambda x: x[1])
            for path, _, size in files:
                try:
                    os.remove(path)
                    total_size -= size
                    if total_size <= (max_dir_size_mb * 0.7) * 1024 * 1024:
                        break
                except Exception:
                    pass
    except Exception as e:
        print(f"Error during cleanup: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# Centralized yt-dlp Options Configuration
# ─────────────────────────────────────────────────────────────────────────────

def build_ydl_opts(
    format_id: Optional[str] = None,
    outtmpl: Optional[str] = None,
    is_audio: bool = False,
    extra_postprocessors: Optional[list] = None
) -> dict:
    """
    Centralized, deterministic yt-dlp options factory.
    All format extraction, preparation, and downloading use this shared configuration.
    """
    js_runtime_cfg = {"node": {"path": NODE_PATH}} if NODE_PATH else {"node": {}}
    opts = {
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
        "socket_timeout": 30,
        "noplaylist": True,
        "js_runtimes": js_runtime_cfg,
        "extractor_args": {
            "youtube": {
                "player_client": ["web_embedded"]
            }
        },
    }

    cookie_file = get_cookie_file()
    if cookie_file:
        opts["cookiefile"] = cookie_file

    if FFMPEG_PATH:
        opts["ffmpeg_location"] = FFMPEG_PATH

    if format_id:
        opts["format"] = format_id

    if outtmpl:
        opts["outtmpl"] = outtmpl

    if is_audio:
        opts["format"] = "ba/b"
        opts["postprocessors"] = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "0",
        }]

    if extra_postprocessors:
        opts.setdefault("postprocessors", []).extend(extra_postprocessors)

    return opts


# ─────────────────────────────────────────────────────────────────────────────
# Root & Static File Endpoints
# ─────────────────────────────────────────────────────────────────────────────

@app.api_route("/", methods=["GET", "HEAD"])
async def root(request: Request, json: Optional[int] = Query(None)):
    accept = request.headers.get("accept", "")
    index_html = os.path.join(BASE_DIR, "index.html")

    if json != 1 and "text/html" in accept and os.path.exists(index_html):
        return FileResponse(index_html, media_type="text/html")

    return {
        "api": "Fast YouTube Downloader Backend (Python FastAPI)",
        "yt_dlp": yt_dlp.version.__version__,
        "yt_dlp_ejs": EJS_VERSION or "missing",
        "python": platform.python_version(),
        "ffmpeg": "installed" if FFMPEG_PATH else "missing",
        "node": NODE_VERSION or "missing",
        "cookies_configured": bool(get_cookie_file()),
        "status": "online",
    }


@app.api_route("/style.css", methods=["GET", "HEAD"])
async def get_style():
    path = os.path.join(BASE_DIR, "style.css")
    if os.path.exists(path):
        return FileResponse(path, media_type="text/css")
    raise HTTPException(status_code=404, detail="style.css not found")


@app.api_route("/app.js", methods=["GET", "HEAD"])
async def get_app_js():
    path = os.path.join(BASE_DIR, "app.js")
    if os.path.exists(path):
        return FileResponse(path, media_type="application/javascript")
    raise HTTPException(status_code=404, detail="app.js not found")


# ─────────────────────────────────────────────────────────────────────────────
# Server Status Diagnostics
# ─────────────────────────────────────────────────────────────────────────────

@app.api_route("/api/status", methods=["GET", "HEAD"])
async def api_status():
    return {
        "api": "Fast YouTube Downloader Backend (Python FastAPI)",
        "yt_dlp": yt_dlp.version.__version__,
        "python": platform.python_version(),
        "ffmpeg": "installed" if FFMPEG_PATH else "missing",
        "node": NODE_VERSION or "missing",
        "cookies_configured": bool(get_cookie_file()),
        "status": "online",
    }


# ─────────────────────────────────────────────────────────────────────────────
# Cookie Management (Safe Metadata & Protected Update)
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/api/cookies")
async def get_cookies_status():
    """Safe metadata only: never exposes cookie contents."""
    cookie_path = get_cookie_file()
    has_cookies = bool(cookie_path)
    size = os.path.getsize(cookie_path) if has_cookies else 0
    return {
        "success": True,
        "has_cookies": has_cookies,
        "size": size,
    }


@app.post("/api/cookies")
async def update_cookies(
    request: Request,
    authorization: Optional[str] = Header(None),
    x_admin_token: Optional[str] = Header(None, alias="X-Admin-Token"),
    cookies: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None)
):
    """
    Protected cookie update endpoint.
    If COOKIE_ADMIN_TOKEN is defined in the environment, callers must provide it.
    """
    admin_token = os.getenv("COOKIE_ADMIN_TOKEN")
    if admin_token:
        provided = x_admin_token or (authorization.replace("Bearer ", "").strip() if authorization else None)
        if not provided or provided != admin_token:
            raise HTTPException(status_code=403, detail="Unauthorized: invalid or missing admin token.")

    content = ""
    if cookies:
        content = cookies.strip()
    elif file:
        file_bytes = await file.read()
        content = file_bytes.decode("utf-8", errors="ignore").strip()
    else:
        try:
            body = await request.json()
            content = body.get("cookies", "").strip()
        except Exception:
            raw_body = await request.body()
            content = raw_body.decode("utf-8", errors="ignore").strip()

    if not content:
        raise HTTPException(status_code=400, detail="No cookie content provided.")

    with open(COOKIE_FILE, "w", encoding="utf-8") as f:
        f.write(content + "\n")

    return {
        "success": True,
        "message": "Cookies saved successfully!"
    }


# ─────────────────────────────────────────────────────────────────────────────
# Format Extraction
# ─────────────────────────────────────────────────────────────────────────────

@app.api_route("/api/formats", methods=["GET", "POST"])
async def api_formats(
    request: Request,
    url: Optional[str] = Query(None)
):
    if not url:
        try:
            data = await request.json()
            url = data.get("url")
        except Exception:
            form = await request.form()
            url = form.get("url")

    if not url:
        raise HTTPException(status_code=422, detail="URL is required.")

    if not re.search(r"youtube\.com|youtu\.be", url):
        raise HTTPException(status_code=422, detail="Only YouTube URLs are supported.")

    url = clean_youtube_url(url.strip())
    opts = build_ydl_opts()

    print(f"[formats] Processing URL: {url}")
    print(f"[formats] yt-dlp: {yt_dlp.version.__version__}, python: {platform.python_version()}, node: {NODE_VERSION}, ejs: {EJS_VERSION}")

    def extract():
        with yt_dlp.YoutubeDL(opts) as ydl:
            return ydl.extract_info(url, download=False)

    try:
        info = await asyncio.to_thread(extract)
        raw_count = len(info.get("formats", [])) if info else 0
        print(f"[formats] Extraction successful. Raw formats found: {raw_count}")
    except Exception as e:
        raw_err = str(e)
        print(f"[formats] Extraction failed: {raw_err}")
        # Classify errors safely without exposing credentials
        if "confirm you're not a bot" in raw_err.lower() or "sign in" in raw_err.lower():
            if not get_cookie_file():
                user_msg = "YouTube bot detection encountered. YouTube cookies are not configured on the server."
            else:
                user_msg = "YouTube authentication failed. Configured cookies may be expired or invalid."
        elif "javascript runtime" in raw_err.lower():
            user_msg = "JavaScript runtime error during YouTube challenge decryption."
        else:
            user_msg = "Could not parse video details."

        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": user_msg,
                "details": raw_err
            }
        )

    if not info or not info.get("formats"):
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": "No downloadable formats found for this video.",
                "details": "yt-dlp returned an empty formats list."
            }
        )

    video_title = sanitize_filename(info.get("title") or "YouTube_Video")
    duration = info.get("duration") or 0
    thumbnail = info.get("thumbnail") or ""

    base_url = str(request.base_url).rstrip("/")
    formats_map = {}
    best_audio = None
    allowed_heights = [144, 240, 360, 480, 720, 1080, 1440, 2160]

    for f in info.get("formats", []):
        vcodec = f.get("vcodec") or "none"
        acodec = f.get("acodec") or "none"
        height = f.get("height")
        abr = f.get("abr") or 0
        tbr = f.get("tbr") or 0
        vbr = f.get("vbr") or 0
        ext = f.get("ext") or "mp4"
        fid = str(f.get("format_id", ""))

        filesize = f.get("filesize") or f.get("filesize_approx")
        if not filesize and duration > 0:
            eff_bitrate = tbr or (vbr + (abr or 128))
            if eff_bitrate > 0:
                filesize = int((eff_bitrate * 1000 / 8) * duration)

        # Video streams
        if vcodec != "none" and height in allowed_heights:
            has_audio = (acodec != "none")
            display_ext = "mp4" if ext == "webm" else ext
            format_id_to_send = fid if has_audio else f"{fid}+bestaudio"

            # Prefer stream with audio or initialize
            if height not in formats_map or has_audio:
                formats_map[height] = {
                    "label": f"{height}p Video+Audio ({display_ext})",
                    "type": "video",
                    "height": height,
                    "ext": display_ext,
                    "filesize": filesize,
                    "download_url": f"{base_url}/api/download?url={quote(url)}&format_id={quote(format_id_to_send)}&title={quote(video_title)}"
                }

        # Audio streams
        elif vcodec == "none" and acodec != "none":
            if not best_audio or abr > (best_audio.get("abr") or 0):
                best_audio = {
                    "label": f"High Quality MP3 Audio ({round(abr)}kbps)",
                    "type": "audio",
                    "height": 0,
                    "abr": abr,
                    "ext": "mp3",
                    "filesize": filesize,
                    "download_url": f"{base_url}/api/download?url={quote(url)}&format_id={quote(fid)}&type=audio&ext=mp3&title={quote(video_title)}"
                }

    formats_list = list(formats_map.values())
    if best_audio:
        formats_list.append(best_audio)

    # Sort descending by resolution height
    formats_list.sort(key=lambda x: x["height"], reverse=True)

    if not formats_list:
        raise HTTPException(status_code=404, detail="No downloadable formats found.")

    return {
        "success": True,
        "title": info.get("title") or "YouTube_Video",
        "thumbnail": thumbnail,
        "duration": duration,
        "formats": formats_list,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Prepare / Pre-download
# ─────────────────────────────────────────────────────────────────────────────

@app.api_route("/api/prepare", methods=["GET", "POST"])
async def api_prepare(
    request: Request,
    url: Optional[str] = Query(None),
    format_id: Optional[str] = Query(None),
    title: Optional[str] = Query("YouTube_Media"),
    type: Optional[str] = Query(None),
    ext: Optional[str] = Query(None)
):
    if not url or not format_id:
        try:
            data = await request.json()
            url = data.get("url", url)
            format_id = data.get("format_id", format_id)
            title = data.get("title", title)
            type = data.get("type", type)
            ext = data.get("ext", ext)
        except Exception:
            pass

    if not url or not format_id:
        raise HTTPException(status_code=400, detail="Missing url or format_id.")

    clean_url = clean_youtube_url(url)
    clean_title = sanitize_filename(title or "YouTube_Media")

    is_audio = (
        type == "audio"
        or ext == "mp3"
        or format_id in ["140", "251", "139", "249", "ba", "bestaudio"]
    )
    target_ext = "mp3" if is_audio else "mp4"

    safe_hash = hashlib.md5(f"{clean_url}_{format_id}_{target_ext}".encode()).hexdigest()
    local_file_name = f"dl_{safe_hash}.{target_ext}"
    target_path = os.path.join(DOWNLOADS_DIR, local_file_name)

    cleanup_old_downloads()

    if not os.path.exists(target_path) or os.path.getsize(target_path) == 0:
        outtmpl = os.path.join(DOWNLOADS_DIR, f"dl_{safe_hash}.%(ext)s")
        ydl_opts = build_ydl_opts(
            format_id=format_id,
            outtmpl=outtmpl,
            is_audio=is_audio
        )
        if not is_audio:
            ydl_opts["merge_output_format"] = "mp4"

        def download():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([clean_url])

        try:
            await asyncio.to_thread(download)
        except Exception as e:
            return JSONResponse(
                status_code=500,
                content={
                    "success": False,
                    "error": f"Failed to process media file: {e}"
                }
            )

    if not os.path.exists(target_path) or os.path.getsize(target_path) == 0:
        raise HTTPException(status_code=500, detail="Failed to generate media file.")

    base_url = str(request.base_url).rstrip("/")
    download_url = f"{base_url}/api/download?file={quote(local_file_name)}&title={quote(clean_title)}&ext={target_ext}"

    return {
        "success": True,
        "ready": True,
        "file_name": f"{clean_title}.{target_ext}",
        "size_bytes": os.path.getsize(target_path),
        "download_url": download_url,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Download & Stream
# ─────────────────────────────────────────────────────────────────────────────

@app.api_route("/api/download", methods=["GET", "HEAD"])
async def api_download(
    request: Request,
    file: Optional[str] = Query(None),
    url: Optional[str] = Query(None),
    format_id: Optional[str] = Query(None),
    title: Optional[str] = Query("YouTube_Media"),
    type: Optional[str] = Query(None),
    ext: Optional[str] = Query(None),
    stream: Optional[str] = Query(None)
):
    # 1. Download prepared/cached file by filename
    if file:
        safe_name = os.path.basename(file)
        file_path = os.path.join(DOWNLOADS_DIR, safe_name)
        if os.path.exists(file_path) and os.path.getsize(file_path) > 0:
            clean_title = sanitize_filename(title or "YouTube_Media")
            file_ext = ext or os.path.splitext(safe_name)[1].lstrip(".") or "mp4"
            output_name = f"{clean_title}.{file_ext}"

            if stream == "1":
                mime_type = "audio/mpeg" if file_ext == "mp3" else "video/mp4"
                return FileResponse(file_path, media_type=mime_type)

            return FileResponse(
                file_path,
                filename=output_name,
                media_type="application/octet-stream"
            )

    # 2. Download via url + format_id on-the-fly
    if not url or not format_id:
        raise HTTPException(status_code=400, detail="Missing url or format_id parameter.")

    clean_url = clean_youtube_url(url)
    clean_title = sanitize_filename(title or "YouTube_Media")

    is_audio = (
        type == "audio"
        or ext == "mp3"
        or format_id in ["140", "251", "139", "249", "ba", "bestaudio"]
    )
    target_ext = "mp3" if is_audio else "mp4"
    safe_hash = hashlib.md5(f"{clean_url}_{format_id}_{target_ext}".encode()).hexdigest()
    local_file_name = f"dl_{safe_hash}.{target_ext}"
    target_path = os.path.join(DOWNLOADS_DIR, local_file_name)

    cleanup_old_downloads()

    if not os.path.exists(target_path) or os.path.getsize(target_path) == 0:
        outtmpl = os.path.join(DOWNLOADS_DIR, f"dl_{safe_hash}.%(ext)s")
        ydl_opts = build_ydl_opts(
            format_id=format_id,
            outtmpl=outtmpl,
            is_audio=is_audio
        )
        if not is_audio:
            ydl_opts["merge_output_format"] = "mp4"

        def download():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([clean_url])

        try:
            await asyncio.to_thread(download)
        except Exception as e:
            return JSONResponse(
                status_code=500,
                content={
                    "success": False,
                    "error": f"Failed to download media file: {e}"
                }
            )

    if not os.path.exists(target_path) or os.path.getsize(target_path) == 0:
        raise HTTPException(status_code=500, detail="Failed to save media file.")

    output_name = f"{clean_title}.{target_ext}"

    if stream == "1":
        mime_type = "audio/mpeg" if target_ext == "mp3" else "video/mp4"
        return FileResponse(target_path, media_type=mime_type)

    return FileResponse(
        target_path,
        filename=output_name,
        media_type="application/octet-stream"
    )


# ─────────────────────────────────────────────────────────────────────────────
# /api/merge - Direct GoogleVideo CDN URLs merge
# (Intentionally separate: direct CDN links require zero YouTube authentication)
# ─────────────────────────────────────────────────────────────────────────────

@app.api_route("/api/merge", methods=["GET", "POST", "HEAD"])
async def api_merge(
    request: Request,
    video_url: Optional[str] = Query(None),
    audio_url: Optional[str] = Query(None),
    title: Optional[str] = Query("YouTube_Video")
):
    if not video_url:
        try:
            data = await request.json()
            video_url = data.get("video_url", video_url)
            audio_url = data.get("audio_url", audio_url)
            title = data.get("title", title)
        except Exception:
            pass

    if not video_url:
        raise HTTPException(status_code=400, detail="video_url is required.")

    clean_title = sanitize_filename(title or "YouTube_Video")
    safe_hash = hashlib.md5(f"{video_url}_{audio_url}".encode()).hexdigest()
    merged_file = os.path.join(DOWNLOADS_DIR, f"merge_{safe_hash}.mp4")

    cleanup_old_downloads()

    if not os.path.exists(merged_file) or os.path.getsize(merged_file) == 0:
        tmp_video = os.path.join(DOWNLOADS_DIR, f"tmp_v_{safe_hash}.mp4")
        tmp_audio = os.path.join(DOWNLOADS_DIR, f"tmp_a_{safe_hash}.m4a")

        def run_merge():
            # 1. Download video CDN stream
            download_cdn_file(video_url, tmp_video)

            # 2. Download audio CDN stream if present
            if audio_url:
                download_cdn_file(audio_url, tmp_audio)

            # 3. Merge or copy
            ffmpeg = FFMPEG_PATH or "ffmpeg"
            if os.path.exists(tmp_video) and os.path.getsize(tmp_video) > 0:
                if audio_url and os.path.exists(tmp_audio) and os.path.getsize(tmp_audio) > 0:
                    cmd = [
                        ffmpeg, "-y",
                        "-i", tmp_video,
                        "-i", tmp_audio,
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-strict", "experimental",
                        merged_file
                    ]
                    subprocess.run(cmd, check=False)
                else:
                    shutil.copyfile(tmp_video, merged_file)

            # Cleanup temp files
            if os.path.exists(tmp_video):
                try: os.remove(tmp_video)
                except Exception: pass
            if os.path.exists(tmp_audio):
                try: os.remove(tmp_audio)
                except Exception: pass

        await asyncio.to_thread(run_merge)

    if not os.path.exists(merged_file) or os.path.getsize(merged_file) == 0:
        raise HTTPException(status_code=500, detail="Failed to merge video and audio streams.")

    return FileResponse(
        merged_file,
        filename=f"{clean_title}.mp4",
        media_type="video/mp4"
    )


# ─────────────────────────────────────────────────────────────────────────────
# /api/audio-cdn - Direct audio CDN URL conversion
# (Intentionally separate: direct CDN links require zero YouTube authentication)
# ─────────────────────────────────────────────────────────────────────────────

@app.api_route("/api/audio-cdn", methods=["GET", "POST", "HEAD"])
async def api_audio_cdn(
    request: Request,
    audio_url: Optional[str] = Query(None),
    title: Optional[str] = Query("YouTube_Audio")
):
    if not audio_url:
        try:
            data = await request.json()
            audio_url = data.get("audio_url", audio_url)
            title = data.get("title", title)
        except Exception:
            pass

    if not audio_url:
        raise HTTPException(status_code=400, detail="audio_url is required.")

    clean_title = sanitize_filename(title or "YouTube_Audio")
    safe_hash = hashlib.md5(audio_url.encode()).hexdigest()
    output_audio = os.path.join(DOWNLOADS_DIR, f"audio_{safe_hash}.mp3")

    cleanup_old_downloads()

    if not os.path.exists(output_audio) or os.path.getsize(output_audio) == 0:
        tmp_raw = os.path.join(DOWNLOADS_DIR, f"tmp_raw_{safe_hash}.m4a")

        def run_convert():
            # 1. Download raw audio CDN stream
            download_cdn_file(audio_url, tmp_raw)

            # 2. Convert to MP3
            ffmpeg = FFMPEG_PATH or "ffmpeg"
            if os.path.exists(tmp_raw) and os.path.getsize(tmp_raw) > 0:
                cmd = [
                    ffmpeg, "-y",
                    "-i", tmp_raw,
                    "-vn", "-ar", "44100", "-ac", "2", "-b:a", "192k",
                    output_audio
                ]
                subprocess.run(cmd, check=False)

            if os.path.exists(tmp_raw):
                try: os.remove(tmp_raw)
                except Exception: pass

        await asyncio.to_thread(run_convert)

    if not os.path.exists(output_audio) or os.path.getsize(output_audio) == 0:
        raise HTTPException(status_code=500, detail="Failed to convert audio stream to MP3.")

    return FileResponse(
        output_audio,
        filename=f"{clean_title}.mp3",
        media_type="audio/mpeg"
    )


# ─────────────────────────────────────────────────────────────────────────────
# Direct download from /downloads/{file_name}
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/downloads/{file_name}")
async def get_download_file(file_name: str):
    safe_name = os.path.basename(file_name)
    path = os.path.join(DOWNLOADS_DIR, safe_name)
    if os.path.exists(path) and os.path.isfile(path):
        return FileResponse(path, filename=safe_name, media_type="application/octet-stream")
    raise HTTPException(status_code=404, detail="File not found.")


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8080))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
