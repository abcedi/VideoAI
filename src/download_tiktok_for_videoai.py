import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time

from datetime import datetime
from pathlib import Path
from urllib.parse import quote, urlparse

import requests
from playwright.sync_api import sync_playwright


TOOL_VERSION = "0.5.0"
PLATFORM = "tiktok"

VIDEO_ID_RE = re.compile(r"/video/(\d+)")
SAFE_NAME_RE = re.compile(r"[^A-Za-z0-9._-]+")


def extract_video_id(url: str) -> str:
    parsed = urlparse(url)

    if parsed.scheme not in {"http", "https"}:
        raise ValueError("TikTok URL must use http or https.")

    host = parsed.hostname.lower() if parsed.hostname else ""

    if host not in {
        "tiktok.com",
        "www.tiktok.com",
        "m.tiktok.com",
    }:
        raise ValueError(f"Unsupported TikTok host: {host}")

    match = VIDEO_ID_RE.search(parsed.path)

    if not match:
        raise ValueError(
            "Expected a full TikTok post URL containing /video/<id>."
        )

    return match.group(1)


def safe_name(value: str, fallback: str) -> str:
    value = value.strip()
    value = SAFE_NAME_RE.sub("-", value)
    value = value.strip("._-")
    return value[:100] or fallback


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()

    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)

    return h.hexdigest().upper()


def get_oembed(url: str) -> dict:
    endpoint = (
        "https://www.tiktok.com/oembed?url="
        + quote(url, safe="")
    )

    response = requests.get(
        endpoint,
        headers={"User-Agent": "Mozilla/5.0"},
        timeout=30,
    )

    response.raise_for_status()

    data = response.json()

    if data.get("type") != "video":
        raise RuntimeError(
            f"Unexpected TikTok oEmbed type: {data.get('type')!r}"
        )

    return data


def ffprobe_media(path: Path) -> dict:
    command = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        (
            "format=duration,size,format_name,bit_rate:"
            "stream=index,codec_type,codec_name,width,height"
        ),
        "-of",
        "json",
        str(path),
    ]

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        raise RuntimeError(
            "ffprobe failed: " + result.stderr.strip()
        )

    data = json.loads(result.stdout)

    streams = data.get("streams") or []

    if not any(s.get("codec_type") == "video" for s in streams):
        raise RuntimeError("Downloaded media has no video stream.")

    return data


def capture_tiktok_media(
    video_id: str,
    attempts: int = 3,
    wait_seconds: int = 15,
) -> dict:
    player_url = (
        f"https://www.tiktok.com/player/v1/{video_id}"
        "?autoplay=1&muted=1&controls=1"
    )

    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            headless=True,
        )

        try:
            for attempt in range(1, attempts + 1):
                context = browser.new_context()
                page = context.new_page()

                candidates = []
                play_url = None
                final_video_url = None

                def capture(response):
                    nonlocal play_url, final_video_url

                    url = response.url
                    content_type = (
                        response.headers.get("content-type", "")
                        .lower()
                    )
                    resource_type = response.request.resource_type

                    interesting = (
                        "/aweme/v1/play/" in url
                        or content_type.startswith("video/")
                        or resource_type == "media"
                    )

                    if not interesting:
                        return

                    candidates.append({
                        "status": response.status,
                        "resource_type": resource_type,
                        "content_type": content_type,
                        "host": urlparse(url).hostname,
                    })

                    if "/aweme/v1/play/" in url:
                        play_url = url

                    if content_type.startswith("video/"):
                        final_video_url = url

                page.on("response", capture)

                try:
                    page.goto(
                        player_url,
                        wait_until="domcontentloaded",
                        timeout=60000,
                    )

                    for _ in range(wait_seconds):
                        try:
                            videos = page.locator("video")

                            if videos.count():
                                videos.first.evaluate(
                                    """(v) => {
                                        v.muted = true;
                                        v.play().catch(() => {});
                                    }"""
                                )
                        except Exception:
                            pass

                        if final_video_url:
                            break

                        time.sleep(1)

                    if final_video_url or play_url:
                        result = {
                            "player_url": player_url,
                            "attempt": attempt,
                            "play_url": play_url,
                            "video_url": final_video_url,
                            "cookies": context.cookies(),
                            "user_agent": page.evaluate(
                                "navigator.userAgent"
                            ),
                            "candidates": candidates,
                        }

                        context.close()
                        return result

                finally:
                    if not context.pages:
                        pass
                    else:
                        context.close()

        finally:
            browser.close()

    raise RuntimeError(
        f"No TikTok media URL captured after {attempts} attempts."
    )


def download_media_to_part(
    capture: dict,
    part_path: Path,
) -> dict:
    download_url = (
        capture.get("video_url")
        or capture.get("play_url")
    )

    if not download_url:
        raise RuntimeError("Capture result contains no media URL.")

    if part_path.exists():
        raise RuntimeError(
            f"Partial target already exists: {part_path}"
        )

    part_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    session = requests.Session()

    for cookie in capture.get("cookies") or []:
        session.cookies.set(
            cookie["name"],
            cookie["value"],
            domain=cookie.get("domain"),
            path=cookie.get("path", "/"),
        )

    headers = {
        "User-Agent": (
            capture.get("user_agent")
            or "Mozilla/5.0"
        ),
        "Referer": capture["player_url"],
        "Accept": "*/*",
        "Range": "bytes=0-",
    }

    bytes_written = 0

    try:
        with session.get(
            download_url,
            headers=headers,
            stream=True,
            allow_redirects=True,
            timeout=120,
        ) as response:
            response.raise_for_status()

            status = response.status_code
            content_type = (
                response.headers.get(
                    "content-type",
                    "",
                )
                .split(";", 1)[0]
                .strip()
                .lower()
            )
            content_length = response.headers.get(
                "content-length"
            )
            content_range = response.headers.get(
                "content-range"
            )

            if status not in {200, 206}:
                raise RuntimeError(
                    f"Unexpected media HTTP status: {status}"
                )

            if not content_type.startswith("video/"):
                raise RuntimeError(
                    "Media response is not video: "
                    f"{content_type!r}"
                )

            expected_total = None

            if status == 206:
                match = re.fullmatch(
                    r"bytes\s+(\d+)-(\d+)/(\d+)",
                    content_range or "",
                    flags=re.IGNORECASE,
                )

                if not match:
                    raise RuntimeError(
                        "206 response lacks a valid "
                        "Content-Range."
                    )

                start = int(match.group(1))
                end = int(match.group(2))
                total = int(match.group(3))

                if start != 0:
                    raise RuntimeError(
                        f"Partial media begins at byte {start}, "
                        "not byte 0."
                    )

                if end + 1 != total:
                    raise RuntimeError(
                        "206 response does not span the "
                        "complete media object."
                    )

                expected_total = total

            elif content_length:
                expected_total = int(content_length)

            with part_path.open("xb") as f:
                for chunk in response.iter_content(
                    chunk_size=1024 * 1024
                ):
                    if not chunk:
                        continue

                    f.write(chunk)
                    bytes_written += len(chunk)

            if bytes_written < 100000:
                raise RuntimeError(
                    "Downloaded media is unexpectedly small."
                )

            if (
                expected_total is not None
                and bytes_written != expected_total
            ):
                raise RuntimeError(
                    "Downloaded byte count mismatch: "
                    f"wrote {bytes_written}, "
                    f"expected {expected_total}."
                )

            return {
                "http_status": status,
                "content_type": content_type,
                "content_length": (
                    int(content_length)
                    if content_length
                    else None
                ),
                "content_range": content_range,
                "expected_total": expected_total,
                "bytes_written": bytes_written,
                "final_host": urlparse(
                    response.url
                ).hostname,
            }

    except Exception:
        if part_path.exists():
            part_path.unlink()

        raise


import shutil


def acquire_tiktok(url: str, output_root: Path) -> dict:
    video_id = extract_video_id(url)
    metadata = get_oembed(url)

    creator = metadata.get("author_name") or "unknown"
    creator_url = metadata.get("author_url")
    title = metadata.get("title") or f"TikTok {video_id}"

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    creator_safe = safe_name(creator, "tiktok")

    job_dir = output_root / (
        f"{creator_safe}-{video_id}__{stamp}"
    )

    job_dir.mkdir(
        parents=True,
        exist_ok=False,
    )

    part_path = job_dir / f"{video_id}.mp4.part"
    video_path = job_dir / f"{video_id}.mp4"
    manifest_path = job_dir / "acquisition.json"

    try:
        capture = capture_tiktok_media(video_id)

        download = download_media_to_part(
            capture,
            part_path,
        )

        probe = ffprobe_media(part_path)
        media_sha256 = sha256_file(part_path)
        media_bytes = part_path.stat().st_size

        if video_path.exists():
            raise RuntimeError(
                f"Final media path already exists: {video_path}"
            )

        os.replace(part_path, video_path)

        manifest = {
            "schema": "videoai-acquisition/v1",
            "tool_version": TOOL_VERSION,
            "platform": PLATFORM,
            "source_url": url,
            "video_id": video_id,
            "title": title,
            "creator": {
                "name": creator,
                "url": creator_url,
            },
            "acquired_at": (
                datetime.now()
                .astimezone()
                .isoformat()
            ),
            "acquisition": {
                "method": (
                    "official-player-playwright-chrome"
                ),
                "capture_attempt": capture["attempt"],
                "player_url": capture["player_url"],
                "observed_responses": (
                    capture.get("candidates") or []
                ),
                "http": download,
            },
            "media": {
                "path": str(video_path),
                "filename": video_path.name,
                "bytes": media_bytes,
                "sha256": media_sha256,
                "ffprobe": probe,
            },
            "captions": {
                "kind": "none",
                "path": None,
                "fallback": "whisper",
            },
        }

        manifest_path.write_text(
            json.dumps(
                manifest,
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

        return {
            "ok": True,
            "platform": PLATFORM,
            "video_id": video_id,
            "title": title,
            "creator": creator,
            "source_url": url,
            "video_path": str(video_path),
            "manifest_path": str(manifest_path),
            "caption_kind": "none",
            "caption_path": None,
            "whisper_fallback": True,
            "sha256": media_sha256,
            "bytes": media_bytes,
        }

    except Exception:
        shutil.rmtree(
            job_dir,
            ignore_errors=True,
        )
        raise


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Acquire a public TikTok post for VideoAI."
        )
    )

    parser.add_argument(
        "url",
        help="Full public TikTok /video/<id> URL.",
    )

    parser.add_argument(
        "--output-root",
        default=str(
            Path.home()
            / "Videos"
            / "AI-Video-Analysis"
            / "Acquisitions"
            / "TikTok"
        ),
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        result = acquire_tiktok(
            args.url,
            Path(args.output_root)
            .expanduser()
            .resolve(),
        )

        print(
            json.dumps(
                result,
                ensure_ascii=False,
            )
        )

        return 0

    except Exception as exc:
        print(
            json.dumps({
                "ok": False,
                "platform": PLATFORM,
                "error": str(exc),
            }),
            file=sys.stderr,
        )

        return 1


if __name__ == "__main__":
    raise SystemExit(main())
