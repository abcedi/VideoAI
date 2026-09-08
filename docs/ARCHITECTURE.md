# Architecture

VideoAI separates **media acquisition** from **evidence generation**.

```text
VideoAI GUI 0.5.0
│
├─ local file ────────────────────────────────┐
├─ YouTube URL -> YouTube acquisition ───────┤
└─ TikTok URL -> TikTok acquisition ─────────┤
                                              ↓
                                    validated local media
                                              ↓
                                   Convert-VideoForAI.ps1
                                              ↓
                                   convert_video_for_ai.py
                                              ↓
                                      analysis-video 0.1.1
                                              ↓
                             transcript + archive/read frames
                                              ↓
                                  evidence selection/package
                                              ↓
                                  video-ai-evidence/v4
```

## GUI

`gui/VideoAI-GUI.ps1`

Responsibilities:

- Windows Forms interface;
- local/YouTube/TikTok routing;
- local-file precedence;
- acquisition helper invocation;
- background execution/log display;
- common backend handoff.

## Backend wrapper

`src/Convert-VideoForAI.ps1`

Responsibilities include isolated runtime setup and Python backend invocation.

## Evidence engine

`src/convert_video_for_ai.py`

Current identity: `0.4.2`.

Responsibilities:

- source probing;
- analysis-video orchestration;
- transcript handling;
- duration policy selection;
- perceptual frame deduplication;
- timeline selection;
- contact-sheet generation;
- package/provenance metadata;
- ZIP creation.

## Core dependency

VideoAI uses `analysis-video 0.1.1` from:

https://github.com/hwanyong/analysis-video

VideoAI adds its own evidence policy/package and acquisition/orchestration layer.

## YouTube acquisition

`src/Download-YouTubeForVideoAI.ps1`

Current identity: `0.2.1`.

Uses yt-dlp through isolated uv/uvx execution.

## TikTok acquisition

- `src/Download-TikTokForVideoAI.ps1`
- `src/download_tiktok_for_videoai.py`

Current identity: `0.5.0`.

High-level sequence:

```text
canonical TikTok post URL
    ↓
post/video ID validation
    ↓
public oEmbed metadata
    ↓
official player opened with Playwright/Chrome
    ↓
observe public media response
    ↓
temporary browser-context cookie handoff
    ↓
validated HTTP media acquisition
    ↓
content completeness checks
    ↓
ffprobe + SHA-256
    ↓
atomic final placement + acquisition.json
```

## Why acquisition is separate

- local files do not depend on source platforms;
- every mode uses the same evidence logic;
- acquisition can fail before evidence analysis;
- source providers can be added without duplicating the evidence engine.

## Local-file precedence

```text
valid local file?
    yes -> use local file
    no  -> evaluate URL mode
```

## Policy split

```text
duration <= 180 s -> short-form-high-recall-v0.3.1
duration >  180 s -> long-form-balanced-a
```

## Unicode-path compatibility

Evidence engine 0.4.2 uses byte-based OpenCV decoding on Windows:

```python
cv2.imdecode(
    np.frombuffer(path.read_bytes(), dtype=np.uint8),
    cv2.IMREAD_GRAYSCALE,
)
```

This avoids direct OpenCV path-opening failures with some Unicode Windows paths. The change was regression-tested against accepted historical evidence imagery.

## Future architecture questions

- formal Python packaging;
- installer/executable packaging;
- dependency locks;
- stable CLI/API;
- provider interface;
- CI/tests;
- cross-platform support.
