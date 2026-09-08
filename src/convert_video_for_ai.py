#!/usr/bin/env python3
"""
VideoAI Workflow v0.4.2

Modes:
1) Convert a video end-to-end with analysis-video 0.1.1 + CUDA Turbo.
2) Repack an existing analysis-video archive into video-ai-evidence/v4
   without rerunning split/transcription/frame detection.

v4 evidence format:
- selected/              representative full, uncropped frames
- visual_sheets/         overview of representative frames
- timeline_sheets/       chronological FULL-FRAME visual evidence
- transcript.json/txt
- compact_context.md
- TIMELINE_EVIDENCE.md
- selection.json
- SOURCE.txt

No persistent Windows PATH changes are made.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlparse

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

TOOL_VERSION = "0.4.2"
FORMAT_VERSION = "video-ai-evidence/v4"
ANALYSIS_VIDEO_VERSION = "0.1.1"

# Representative-frame selection. The crop is used ONLY for similarity.
COMPARE_KEEP_TOP = 0.72
PHASH_DISTANCE = 18
MAX_GAP_SECONDS = 2.5

# Duration-aware evidence policy.
# Short-form preserves the exact v0.3.1 behavior.
SHORT_FORM_MAX_SECONDS = 180.0

# Long-form BALANCED-A policy, measured against the
# 16:31 YouTube acceptance archive.
LONG_SELECTED_PHASH_DISTANCE = 20
LONG_SELECTED_MAX_GAP_SECONDS = 6.0
LONG_TIMELINE_PHASH_DISTANCE = 24
LONG_TIMELINE_MAX_GAP_SECONDS = 6.0

# Representative visual sheets.
VIS_COLUMNS = 3
VIS_ROWS = 4
VIS_PER_SHEET = VIS_COLUMNS * VIS_ROWS
VIS_CELL_WIDTH = 260

# Location-agnostic timeline sheets: full frame, every archive read image.
TIME_COLUMNS = 4
TIME_ROWS = 4
TIME_PER_SHEET = TIME_COLUMNS * TIME_ROWS
TIME_CELL_WIDTH = 240

TS_RE = re.compile(r"_t(\d+(?:\.\d+)?)\.jpg$", re.IGNORECASE)


def fail(msg: str, code: int = 2) -> "None":
    print(json.dumps({"ok": False, "error": msg}, indent=2), file=sys.stderr)
    raise SystemExit(code)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


WINDOWS_RESERVED_NAMES = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}


def safe_component(value: str, *, max_length: int = 72, fallback: str = "video") -> str:
    """Create a human-readable Windows-safe path component."""
    value = str(value or "").strip()
    value = re.sub(r'[<>:"/\\\\|?*\x00-\x1f]', " ", value)
    value = re.sub(r"\s+", "-", value)
    value = re.sub(r"-{2,}", "-", value)
    value = value.strip(" .-_")

    if not value:
        value = fallback

    if value.upper().split(".", 1)[0] in WINDOWS_RESERVED_NAMES:
        value = f"_{value}"

    value = value[:max_length].rstrip(" .-_")
    return value or fallback


def safe_stem(name: str) -> str:
    return safe_component(name, max_length=80, fallback="video")


def source_handle(source_url: str | None) -> str | None:
    """Extract creator/handle from common short-form URLs without network access."""
    if not source_url:
        return None

    try:
        parsed = urlparse(source_url)
    except Exception:
        return None

    host = (parsed.hostname or "").lower()
    parts = [unquote(p) for p in parsed.path.split("/") if p]

    if "tiktok.com" in host:
        for part in parts:
            if part.startswith("@") and len(part) > 1:
                return safe_component(part[1:], max_length=40, fallback="creator")

    if "instagram.com" in host and len(parts) >= 2:
        if parts[0] not in {"reel", "reels", "p", "tv"}:
            return safe_component(parts[0].lstrip("@"), max_length=40, fallback="creator")

    if "youtube.com" in host and parts and parts[0].startswith("@"):
        return safe_component(parts[0][1:], max_length=40, fallback="creator")

    return None


def make_job_name(
    *,
    video: Path,
    source_url: str | None,
    job_label: str | None,
    stamp: str,
) -> tuple[str, str | None, str | None]:
    handle = source_handle(source_url)
    label = (
        safe_component(job_label, max_length=72, fallback="video")
        if job_label and job_label.strip()
        else None
    )

    pieces: list[str] = []

    if handle:
        pieces.append(f"@{handle}")

    if label:
        pieces.append(label)
    elif handle:
        pieces.append(safe_component(video.stem, max_length=32, fallback="video"))
    else:
        pieces.append(safe_component(video.stem, max_length=80, fallback="video"))

    pieces.append(stamp)
    return "__".join(pieces), handle, label


def timestamp(path: Path) -> float:
    m = TS_RE.search(path.name)
    if not m:
        raise RuntimeError(f"Cannot parse timestamp from {path.name}")
    return float(m.group(1))


def nvidia_bin_dirs() -> tuple[Path, Path]:
    import nvidia.cublas
    import nvidia.cudnn

    def one_bin(mod) -> Path:
        roots = list(mod.__path__)
        if len(roots) != 1:
            raise RuntimeError(
                f"Expected one package root for {mod.__name__}; found {roots}"
            )
        p = Path(roots[0]) / "bin"
        if not p.is_dir():
            raise RuntimeError(f"NVIDIA DLL directory missing: {p}")
        return p

    cublas = one_bin(nvidia.cublas)
    cudnn = one_bin(nvidia.cudnn)

    required = (
        cublas / "cublas64_12.dll",
        cublas / "cublasLt64_12.dll",
        cudnn / "cudnn64_9.dll",
    )
    for dll in required:
        if not dll.is_file():
            raise RuntimeError(f"Required NVIDIA DLL missing: {dll}")

    return cublas, cudnn


def child_env() -> dict[str, str]:
    cublas, cudnn = nvidia_bin_dirs()
    env = os.environ.copy()
    env["PATH"] = (
        str(cublas)
        + os.pathsep
        + str(cudnn)
        + os.pathsep
        + env.get("PATH", "")
    )
    env["CUDA_VISIBLE_DEVICES"] = "0"
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    return env


def run_av(exe: str, argv: list[str], env: dict[str, str]) -> dict:
    p = subprocess.run(
        [exe, *argv],
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if p.stderr:
        print(p.stderr, end="", file=sys.stderr)
    if p.stdout:
        print(p.stdout, end="")
    if p.returncode != 0:
        raise RuntimeError(
            f"analysis-video {' '.join(argv[:2])} failed with exit {p.returncode}"
        )
    try:
        data = json.loads(p.stdout)
    except Exception as exc:
        raise RuntimeError(f"Could not parse analysis-video JSON: {exc}") from exc
    if not data.get("ok"):
        raise RuntimeError(f"analysis-video returned ok=false: {data}")
    return data


def phash(path: Path) -> np.ndarray:
    img = cv2.imdecode(
        np.frombuffer(path.read_bytes(), dtype=np.uint8),
        cv2.IMREAD_GRAYSCALE,
    )
    if img is None:
        raise RuntimeError(f"Cannot read image: {path}")
    h, _w = img.shape[:2]
    # Similarity-only crop. Output images and timeline thumbnails are full frame.
    img = img[: max(1, int(h * COMPARE_KEEP_TOP)), :]
    img = cv2.resize(img, (32, 32), interpolation=cv2.INTER_AREA)
    low = cv2.dct(np.float32(img))[:8, :8].flatten()
    med = np.median(low[1:])
    return low > med


def hamming(a: np.ndarray, b: np.ndarray) -> int:
    return int(np.count_nonzero(a != b))


def choose_frames(
    files: list[Path],
    *,
    phash_distance: int = PHASH_DISTANCE,
    max_gap_seconds: float = MAX_GAP_SECONDS,
) -> list[Path]:
    if not files:
        raise RuntimeError("No analysis-video reading frames found")

    selected = [files[0]]
    last_hash = phash(files[0])
    last_t = timestamp(files[0])

    for path in files[1:]:
        cur_hash = phash(path)
        cur_t = timestamp(path)

        if (
            hamming(last_hash, cur_hash) >= phash_distance
            or (cur_t - last_t) >= max_gap_seconds
        ):
            selected.append(path)
            last_hash = cur_hash
            last_t = cur_t

    if selected[-1] != files[-1]:
        selected.append(files[-1])

    return selected


def transcript_speech(segments: list[dict], t: float) -> str:
    for seg in segments:
        if float(seg["start"]) <= t <= float(seg["end"]):
            return str(seg["text"]).strip()

    if not segments:
        return "(no transcript segment)"

    nearest = min(
        segments,
        key=lambda s: abs(
            ((float(s["start"]) + float(s["end"])) / 2.0) - t
        ),
    )

    mid = (float(nearest["start"]) + float(nearest["end"])) / 2.0
    if abs(mid - t) <= 3.0:
        return str(nearest["text"]).strip()

    return "(no nearby speech)"


def _sheet(
    paths: list[Path],
    out_path: Path,
    columns: int,
    rows: int,
    cell_width: int,
) -> None:
    font = ImageFont.load_default()
    cells = []

    for path in paths:
        img = Image.open(path).convert("RGB")
        ratio = cell_width / img.width
        nh = max(1, int(img.height * ratio))
        img = img.resize((cell_width, nh), Image.Resampling.LANCZOS)

        label_h = 30
        cell = Image.new("RGB", (cell_width, nh + label_h), "white")
        cell.paste(img, (0, 0))

        draw = ImageDraw.Draw(cell)
        draw.text(
            (4, nh + 6),
            f"{timestamp(path):06.2f}s  {path.stem}",
            fill="black",
            font=font,
        )
        cells.append(cell)

    ch = max(c.height for c in cells)
    sheet = Image.new(
        "RGB",
        (columns * cell_width, rows * ch),
        "white",
    )

    for i, cell in enumerate(cells):
        x = (i % columns) * cell_width
        y = (i // columns) * ch
        sheet.paste(cell, (x, y))

    sheet.save(out_path, quality=88, optimize=True)


def make_sheets(
    frames: list[Path],
    out_dir: Path,
    columns: int,
    rows: int,
    cell_width: int,
    prefix: str,
) -> list[str]:
    out_dir.mkdir()
    per_sheet = columns * rows
    names = []

    for start in range(0, len(frames), per_sheet):
        batch = frames[start : start + per_sheet]
        num = start // per_sheet + 1
        name = f"{prefix}_{num:02d}.jpg"
        _sheet(batch, out_dir / name, columns, rows, cell_width)
        names.append(name)

    return names


def state_source_path(analysis_dir: Path) -> Path | None:
    state_path = analysis_dir / "state.json"
    if not state_path.is_file():
        return None

    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        return None

    raw = state.get("source", {}).get("path")
    if not raw:
        return None

    try:
        return Path(raw)
    except Exception:
        return None


def build_pack(
    *,
    analysis_dir: Path,
    transcript_path: Path,
    pack_dir: Path,
    zip_path: Path,
    source_video: Path | None,
    source_url: str | None,
    source_handle_value: str | None = None,
    job_label: str | None = None,
) -> dict:
    read_dir = analysis_dir / "runs" / "full" / "read"
    metadata_path = analysis_dir / "runs" / "full" / "metadata.json"

    if not read_dir.is_dir():
        raise RuntimeError(f"Missing analysis read directory: {read_dir}")

    if not transcript_path.is_file():
        raise RuntimeError(f"Missing transcript: {transcript_path}")

    if pack_dir.exists():
        raise RuntimeError(f"Pack directory already exists: {pack_dir}")

    if zip_path.exists():
        raise RuntimeError(f"Pack ZIP already exists: {zip_path}")

    frames = sorted(read_dir.glob("*.jpg"), key=timestamp)
    if not frames:
        raise RuntimeError("No read/*.jpg frames found")

    frame_span_seconds = max(
        0.0,
        timestamp(frames[-1]) - timestamp(frames[0]),
    )
    long_form = frame_span_seconds > SHORT_FORM_MAX_SECONDS

    if long_form:
        evidence_policy = "long-form-balanced-a"

        selected_phash_distance = LONG_SELECTED_PHASH_DISTANCE
        selected_max_gap_seconds = LONG_SELECTED_MAX_GAP_SECONDS
        timeline_phash_distance = LONG_TIMELINE_PHASH_DISTANCE
        timeline_max_gap_seconds = LONG_TIMELINE_MAX_GAP_SECONDS

        selected = choose_frames(
            frames,
            phash_distance=selected_phash_distance,
            max_gap_seconds=selected_max_gap_seconds,
        )
        timeline_frames = choose_frames(
            frames,
            phash_distance=timeline_phash_distance,
            max_gap_seconds=timeline_max_gap_seconds,
        )
    else:
        evidence_policy = "short-form-high-recall-v0.3.1"

        selected_phash_distance = PHASH_DISTANCE
        selected_max_gap_seconds = MAX_GAP_SECONDS
        timeline_phash_distance = None
        timeline_max_gap_seconds = None

        # Exact pre-v0.4 behavior.
        selected = choose_frames(frames)
        timeline_frames = frames

    transcript = json.loads(transcript_path.read_text(encoding="utf-8"))
    segments = transcript.get("segments", [])

    # Validation is complete; output mutation begins now.
    pack_dir.mkdir()

    selected_dir = pack_dir / "selected"
    selected_dir.mkdir()

    for path in selected:
        shutil.copy2(path, selected_dir / path.name)

    visual_names = make_sheets(
        selected,
        pack_dir / "visual_sheets",
        VIS_COLUMNS,
        VIS_ROWS,
        VIS_CELL_WIDTH,
        "visual_sheet",
    )

    # Chronological, FULL-FRAME, location-agnostic evidence.
    # Short-form keeps every archive frame. Long-form uses the
    # independently measured BALANCED-A timeline subset.
    timeline_names = make_sheets(
        timeline_frames,
        pack_dir / "timeline_sheets",
        TIME_COLUMNS,
        TIME_ROWS,
        TIME_CELL_WIDTH,
        "timeline_sheet",
    )

    shutil.copy2(transcript_path, pack_dir / "transcript.json")
    (pack_dir / "transcript.txt").write_text(
        str(transcript.get("text", "")),
        encoding="utf-8",
    )

    source_hash = None
    source_lines = [
        f"Generated: {datetime.now().astimezone().isoformat()}",
        f"Analysis directory: {analysis_dir}",
        f"Transcript file: {transcript_path}",
    ]

    if source_video is not None:
        source_lines.insert(0, f"Original file: {source_video}")
        if source_video.is_file():
            source_hash = sha256(source_video)
            source_lines.append(f"SHA256: {source_hash}")
        else:
            source_lines.append("SHA256: unavailable (source file not present)")

    if source_url:
        source_lines.append(f"Source URL: {source_url}")
    if source_handle_value:
        source_lines.append(f"Source handle: @{source_handle_value}")
    if job_label:
        source_lines.append(f"Context label: {job_label}")

    (pack_dir / "SOURCE.txt").write_text(
        "\n".join(source_lines) + "\n",
        encoding="utf-8",
    )

    context = [
        "# Video AI evidence",
        "",
        f"Evidence format: {FORMAT_VERSION}",
        f"Evidence policy: {evidence_policy}",
        f"Frame span seconds: {frame_span_seconds:.2f}",
        f"Archive visual frames: {len(frames)}",
        f"Selected full-resolution visual frames: {len(selected)}",
        f"Timeline evidence frames: {len(timeline_frames)}",
        f"Transcript source: {transcript.get('source', {}).get('kind')}",
        f"Transcript backend: {transcript.get('backend')}",
        f"Transcript model: {transcript.get('model')}",
        f"Transcript device: {transcript.get('device')}",
        "",
        "## Evidence rules",
        "",
        "The speech transcript is useful but is not ground truth. "
        "Use visible evidence to resolve proper nouns, negations, technical terms, "
        "commands, URLs, product names, UI labels, and disagreements with Whisper.",
        "",
        "selected/ contains representative FULL, UNCROPPED reading frames.",
        "",
        "timeline_sheets/ is location-agnostic chronological evidence. Short-form "
        "packages include every archive read frame; long-form packages use a "
        "conservative visual subset with max-gap retention. Use it when selected/ "
        "may have removed a brief caption, UI label, diagram, or other state.",
        "",
        "## AI reading strategy",
        "",
        "Do not open every individual image by default.",
        "",
        "1. Read this file and transcript first.",
        "2. Inspect visual_sheets/ for the fastest visual overview.",
        "3. Inspect timeline_sheets/ to resolve missing, brief, or conflicting visual evidence.",
        "4. Open individual selected/ images only when finer text, UI, diagram, hardware, "
        "command, URL, or other detail requires close inspection.",
        "5. Treat visible evidence as authoritative when it conflicts with automatic speech recognition.",
        "",
        "This progressive order is intended to minimize image/token usage while retaining "
        "complete visual coverage through the timeline sheets.",
        "",
        "## Representative visual overview",
        "",
    ]

    context += [f"![](visual_sheets/{n})" for n in visual_names]

    context += [
        "",
        "## Complete chronological visual timeline",
        "",
    ]

    context += [f"![](timeline_sheets/{n})" for n in timeline_names]

    context += [
        "",
        "## Selected timestamped visual evidence",
        "",
    ]

    for path in selected:
        t = timestamp(path)
        context += [
            f"### {t:.2f}s",
            f"![](selected/{path.name})",
            "",
            f"Speech: {transcript_speech(segments, t)}",
            "",
        ]

    (pack_dir / "compact_context.md").write_text(
        "\n".join(context),
        encoding="utf-8",
    )

    timeline_guide = f"""# Timeline evidence

`timeline_sheets/` contains FULL-FRAME thumbnails from
{len(timeline_frames)} of {len(frames)} `analysis-video` reading frames,
chronologically ordered.

Evidence policy: {evidence_policy}
Frame span: {frame_span_seconds:.2f} seconds.

This deliberately makes no assumption about where captions or important UI text
appear. Text may be top, center, bottom, or
anywhere else in the frame.

Use the timeline sheets when:
- a Whisper word or negation matters;
- a brief caption may have been removed by representative-frame selection;
- a project/product name appears visually;
- a command, URL, parameter, diagram, or UI label matters;
- the selected images do not fully explain a transition.

The selected/ images remain the preferred high-detail evidence. Timeline
sheets are the policy-aware low-cost visual safety net.
"""
    (pack_dir / "TIMELINE_EVIDENCE.md").write_text(
        timeline_guide,
        encoding="utf-8",
    )

    reduction = round((1 - len(selected) / len(frames)) * 100, 1)

    readme = f"""# AI analysis instructions

This is a multimodal evidence package for one informational video.

## ConvertedVideo mode

When the user says `ConvertedVideo` (or legacy `ConvertedTikTok`), analyze the entire evidence package.
Use transcript + selected high-detail frames + visual sheets + chronological
timeline sheets. Treat visible evidence as authoritative when it conflicts
with automatic speech recognition. Explain what is being taught or
demonstrated; identify products, software, settings, commands, URLs,
hardware, UI labels, and diagrams shown visually; and verify substantive
claims with current external sources when appropriate.

Use progressive inspection to reduce AI/image usage rather than opening
every individual image immediately.

Recommended reading order:
1. compact_context.md and transcript first
2. visual_sheets/ for the fastest visual overview
3. timeline_sheets/ when any brief state, wording, or conflict matters
4. selected/ only when close inspection is needed

Do not treat Whisper as authoritative when visible evidence contradicts it.

The full high-recall analysis-video archive remains outside this ZIP:
{analysis_dir}

Evidence format: {FORMAT_VERSION}
Tool version: {TOOL_VERSION}
"""
    (pack_dir / "README_AI.md").write_text(readme, encoding="utf-8")

    manifest = {
        "format": FORMAT_VERSION,
        "tool_version": TOOL_VERSION,
        "analysis_video_version": ANALYSIS_VIDEO_VERSION,
        "source": {
            "path": str(source_video) if source_video else None,
            "sha256": source_hash,
            "url": source_url,
            "handle": source_handle_value,
        },
        "job_label": job_label,
        "analysis_dir": str(analysis_dir),
        "transcript_file": str(transcript_path),
        "evidence_policy": evidence_policy,
        "frame_span_seconds": round(frame_span_seconds, 3),
        "short_form_max_seconds": SHORT_FORM_MAX_SECONDS,
        "source_frames": len(frames),
        "selected_full_frames": len(selected),
        "reduction_percent": reduction,
        "selection": {
            "algorithm": "DCT perceptual hash + max-gap retention",
            "hamming_threshold": selected_phash_distance,
            "max_gap_seconds": selected_max_gap_seconds,
            "comparison_crop_keep_top_fraction": COMPARE_KEEP_TOP,
            "output_images_cropped": False,
        },
        "timeline_evidence": {
            "source_frames": len(frames),
            "evidence_frames": len(timeline_frames),
            "algorithm": (
                "DCT perceptual hash + max-gap retention"
                if long_form
                else "every archive read frame"
            ),
            "hamming_threshold": timeline_phash_distance,
            "max_gap_seconds": timeline_max_gap_seconds,
            "full_frame_thumbnails": True,
            "sheets": timeline_names,
            "frames_per_sheet": TIME_PER_SHEET,
            "location_assumption": None,
        },
        "visual_sheets": visual_names,
        "transcript": {
            "backend": transcript.get("backend"),
            "device": transcript.get("device"),
            "model": transcript.get("model"),
            "language": transcript.get("source", {}).get("language"),
            "source_kind": transcript.get("source", {}).get("kind"),
        },
        "frames": [
            {
                "file": p.name,
                "timestamp": timestamp(p),
                "speech": transcript_speech(segments, timestamp(p)),
            }
            for p in selected
        ],
    }

    if metadata_path.is_file():
        try:
            meta = json.loads(metadata_path.read_text(encoding="utf-8"))
            manifest["analysis_video_images"] = meta.get("images")
        except Exception:
            pass

    (pack_dir / "selection.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    with zipfile.ZipFile(
        zip_path,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as zf:
        for path in pack_dir.rglob("*"):
            if path.is_file():
                zf.write(path, path.relative_to(pack_dir))

    return {
        "source_frames": len(frames),
        "selected_frames": len(selected),
        "timeline_frames": len(timeline_frames),
        "reduction_percent": reduction,
        "visual_sheets": len(visual_names),
        "timeline_sheets": len(timeline_names),
        "zip": str(zip_path),
        "source_sha256": source_hash,
    }


def convert_mode(args) -> int:
    video = Path(args.video).expanduser().resolve()
    output_root = Path(args.output_root).expanduser().resolve()

    transcript_input = (
        Path(args.transcript).expanduser().resolve()
        if args.transcript
        else None
    )

    if not video.is_file():
        fail(f"Video not found: {video}")

    if video.suffix.lower() not in {".mp4", ".mov", ".mkv", ".webm"}:
        fail(f"Unsupported video extension: {video.suffix}")

    if transcript_input is not None:
        if not transcript_input.is_file():
            fail(f"Transcript not found: {transcript_input}")
        if transcript_input.suffix.lower() != ".srt":
            fail(f"Explicit transcript must currently be SRT: {transcript_input}")

    exe = shutil.which("analysis-video")
    if exe is None:
        fail("analysis-video executable is not available in the uv environment")

    source_before = sha256(video)

    output_root.mkdir(parents=True, exist_ok=True)

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    job_name, creator_handle, normalized_job_label = make_job_name(
        video=video,
        source_url=args.source_url,
        job_label=args.job_label,
        stamp=stamp,
    )
    job_dir = output_root / job_name
    analysis_dir = job_dir / "archive-analysis"
    pack_dir = job_dir / "ai-pack"
    zip_path = job_dir / f"{job_name}-ai.zip"

    if job_dir.exists():
        fail(f"Job directory already exists: {job_dir}")

    job_dir.mkdir()

    try:
        env = child_env()

        print("===== CUDA DOCTOR =====", file=sys.stderr)
        doctor = run_av(exe, ["doctor"], env)
        speech = doctor["capabilities"]["speech-recognition"]

        if not speech["available"]:
            raise RuntimeError("Speech recognition is unavailable")

        print("===== SPLIT =====", file=sys.stderr)
        run_av(
            exe,
            [
                "analyze",
                str(video),
                "--out",
                str(analysis_dir),
                "--until",
                "split",
            ],
            env,
        )

        transcribe_args = [
            "transcribe",
            str(video),
            "--out",
            str(analysis_dir),
            "--model",
            "turbo",
            "--stt-backend",
            "faster-whisper",
        ]

        if args.language:
            transcribe_args += ["--language", args.language]

        if transcript_input is not None:
            transcribe_args += ["--transcript", str(transcript_input)]

        print("===== TRANSCRIBE =====", file=sys.stderr)
        tr = run_av(exe, transcribe_args, env)

        if tr.get("source_kind") == "whisper" and tr.get("device") != "cuda":
            raise RuntimeError(
                f"Whisper transcription did not use CUDA: {tr.get('device')}"
            )

        print("===== FRAMES =====", file=sys.stderr)
        run_av(
            exe,
            [
                "frames",
                str(video),
                "--out",
                str(analysis_dir),
            ],
            env,
        )

        print("===== BUILD V4 PACK =====", file=sys.stderr)
        pack = build_pack(
            analysis_dir=analysis_dir,
            transcript_path=analysis_dir / "transcript.json",
            pack_dir=pack_dir,
            zip_path=zip_path,
            source_video=video,
            source_url=args.source_url,
            source_handle_value=creator_handle,
            job_label=normalized_job_label,
        )

        source_after = sha256(video)

        if source_after != source_before:
            raise RuntimeError(
                "Source video hash changed during processing. Stop using this job."
            )

        result = {
            "ok": True,
            "mode": "convert",
            "job_dir": str(job_dir),
            "archive_analysis": str(analysis_dir),
            "ai_pack_dir": str(pack_dir),
            "ai_zip": str(zip_path),
            "source_sha256": source_before,
            "job_name": job_name,
            "source_handle": creator_handle,
            "job_label": normalized_job_label,
            "transcript": {
                "source_kind": tr.get("source_kind"),
                "backend": tr.get("backend"),
                "device": tr.get("device"),
                "model": tr.get("model"),
                "language": tr.get("language"),
                "segments": tr.get("n_segments"),
                "words": tr.get("n_words"),
            },
            **pack,
        }

        print("\n===== COMPLETE =====")
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0

    except Exception as exc:
        print(
            json.dumps(
                {
                    "ok": False,
                    "mode": "convert",
                    "error": f"{type(exc).__name__}: {exc}",
                    "partial_job_dir": str(job_dir),
                    "source_sha256_before": source_before,
                    "source_sha256_now": sha256(video),
                    "note": "Partial job kept for inspection.",
                },
                indent=2,
                ensure_ascii=False,
            ),
            file=sys.stderr,
        )
        return 1


def repack_mode(args) -> int:
    analysis_dir = Path(args.repack_analysis).expanduser().resolve()

    if not analysis_dir.is_dir():
        fail(f"Analysis directory not found: {analysis_dir}")

    read_dir = analysis_dir / "runs" / "full" / "read"
    if not read_dir.is_dir():
        fail(f"Expected analysis read directory not found: {read_dir}")

    transcript_path = (
        Path(args.transcript).expanduser().resolve()
        if args.transcript
        else analysis_dir / "transcript.json"
    )

    if not transcript_path.is_file():
        fail(f"Transcript not found: {transcript_path}")

    output_root = Path(args.output_root).expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    source_video = (
        Path(args.source_video).expanduser().resolve()
        if args.source_video
        else state_source_path(analysis_dir)
    )

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    base_name = safe_stem(
        source_video.stem if source_video else analysis_dir.name
    )
    name = f"{base_name}-evidence-v4-{stamp}"

    pack_dir = output_root / name
    zip_path = output_root / f"{name}.zip"

    print("===== REPACK EXISTING ANALYSIS =====", file=sys.stderr)
    result = build_pack(
        analysis_dir=analysis_dir,
        transcript_path=transcript_path,
        pack_dir=pack_dir,
        zip_path=zip_path,
        source_video=source_video,
        source_url=args.source_url,
    )

    print("\n===== REPACK COMPLETE =====")
    print(
        json.dumps(
            {
                "ok": True,
                "mode": "repack",
                "analysis_dir": str(analysis_dir),
                "transcript": str(transcript_path),
                "ai_pack_dir": str(pack_dir),
                **result,
            },
            indent=2,
            ensure_ascii=False,
        )
    )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()

    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--video")
    mode.add_argument("--repack-analysis")

    ap.add_argument("--output-root", required=True)
    ap.add_argument("--language", default=None)
    ap.add_argument("--source-url", default=None)
    ap.add_argument("--job-label", default=None)

    # --transcript is shared by convert/repack; --source-video is repack-only.
    ap.add_argument("--transcript", default=None)
    ap.add_argument("--source-video", default=None)

    args = ap.parse_args()

    if args.video:
        return convert_mode(args)

    return repack_mode(args)


if __name__ == "__main__":
    raise SystemExit(main())
