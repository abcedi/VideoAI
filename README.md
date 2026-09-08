# VideoAI

**Turn local videos, TikTok URLs, and YouTube URLs into AI-ready transcripts and visual evidence.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **Status:** Early-stage initial public release<br>
> **Public release:** VideoAI v0.5.0<br>
> **Primary platform:** Windows<br>
> **License:** MIT for VideoAI's own source code

VideoAI is a personal project that grew into a reusable workflow for converting video into compact multimodal context for AI chats.

The project started because I wanted to use informational TikTok videos as context in AI conversations. A transcript alone was not enough: important information was often visible on screen but never spoken. VideoAI therefore tries to preserve both:

1. **what was said**, and
2. **what was shown**.

It produces a transcript plus representative visual evidence, including selected frames and chronological contact sheets. The goal is not to archive every frame; the goal is to preserve enough evidence for an AI or human reviewer to reconstruct what the video was teaching, demonstrating, or showing.

The project later expanded into a Windows GUI, generalized local-video support, YouTube processing, direct YouTube URL acquisition, and finally direct TikTok URL acquisition.

## What it supports

VideoAI v0.5.0 can accept:

- an existing local video;
- a supported public YouTube URL; or
- a full public TikTok post URL.

All successful source modes converge on the same evidence backend and produce a `video-ai-evidence/v4` package.

```text
Local video ───────────────────────┐
                                  │
YouTube URL ── acquisition ───────┤
                                  ├─> common evidence backend
TikTok URL ─── acquisition ───────┘
                                      │
                                      ├─ transcript/subtitles
                                      ├─ selected evidence frames
                                      ├─ overview visual sheets
                                      ├─ chronological timeline sheets
                                      └─ video-ai-evidence/v4 ZIP
```

## Why transcript + visual evidence?

Useful videos often contain information that is shown rather than spoken:

- commands;
- URLs;
- product names;
- diagrams;
- UI labels;
- settings;
- code;
- screenshots;
- before/after states;
- step-by-step visual changes.

A speech transcript can be correct and still miss those details. VideoAI is intended to preserve enough of both modalities that downstream analysis has a better chance of understanding the actual video.

## Input modes

### Local video

Local files are first-class inputs.

If both a valid local file and a URL are supplied, VideoAI uses the local file. The URL can still be retained as provenance.

### YouTube URL

The YouTube path uses `yt-dlp` for public media acquisition and can reuse available subtitles/captions before falling back to Whisper transcription.

Current transcript preference is:

```text
explicit/manual subtitle
    ↓
automatic YouTube caption
    ↓
Whisper fallback
```

### TikTok URL

The TikTok path is currently validated for full canonical public TikTok post URLs.

It uses public oEmbed metadata plus the official TikTok player through Playwright and an installed Chrome browser. It does not import the user's normal browser profile or logged-in cookie store.

The temporary isolated browser context may create runtime cookies needed for the public media request. Those values are not hard-coded into the repository.

If acquisition fails, VideoAI does not intentionally pass an incomplete media file into the evidence backend.

## Output package

A normal package looks like:

```text
*-ai.zip
├── README_AI.md
├── compact_context.md
├── TIMELINE_EVIDENCE.md
├── transcript.txt
├── transcript.json
├── selection.json
├── SOURCE.txt
├── selected/
├── visual_sheets/
└── timeline_sheets/
```

Recommended review order:

1. `compact_context.md`
2. transcript
3. `visual_sheets/`
4. `timeline_sheets/` when chronology matters
5. individual files in `selected/` for closer inspection

The primary package cue is `ConvertedVideo`. Packages also retain `ConvertedTikTok` as a legacy-compatible cue from the project's earlier TikTok-specific phase.

See [docs/EVIDENCE_FORMAT.md](docs/EVIDENCE_FORMAT.md).

## Current versions

| Component | Version |
|---|---:|
| VideoAI GUI | `0.5.0` |
| TikTok acquisition | `0.5.0` |
| Evidence engine | `0.4.2` |
| YouTube acquisition | `0.2.1` |
| Evidence package | `video-ai-evidence/v4` |
| Core analysis dependency | `analysis-video 0.1.1` |

The public Git repository begins at v0.5.0. Earlier TikTokAI/VideoAI snapshots existed privately; they are documented as history rather than recreated as fake historical Git commits.

## Evidence policies

### Short form

For videos up to and including 180 seconds:

```text
policy: short-form-high-recall-v0.3.1
selected pHash threshold: 18
selected maximum gap: 2.5 seconds
timeline: every archive read frame
```

### Long form

For videos longer than 180 seconds:

```text
policy: long-form-balanced-a
selected pHash threshold: 20
selected maximum gap: 6 seconds
timeline pHash threshold: 24
timeline maximum gap: 6 seconds
```

These are implementation choices, not universal claims about the best sampling strategy. Feedback and experiments with better policies are welcome.

## Quick start

The current release is Windows-first and was validated with PowerShell 7, Python, `uv`, FFmpeg/ffprobe, Chrome, Deno, and an NVIDIA CUDA-capable environment for the accelerated transcription path.

Clone:

```powershell
git clone https://github.com/abcedi/VideoAI.git
Set-Location .\VideoAI
```

Launch the GUI from the clone:

```powershell
pwsh -NoProfile -Sta -File .\gui\VideoAI-GUI.ps1 `
    -BackendPath "$PWD\src\Convert-VideoForAI.ps1"
```

See [docs/INSTALLATION.md](docs/INSTALLATION.md) and [docs/USAGE.md](docs/USAGE.md).

## AI-assisted development

VideoAI was developed **heavily with AI assistance**.

AI was used during:

- research;
- architecture discussions;
- code generation;
- refactoring;
- debugging;
- troubleshooting;
- documentation;
- test planning;
- review of implementation ideas.

The requirements, workflow decisions, acceptance criteria, real-video validation, release gates, rollback decisions, and final implementation choices were made interactively while building and using the project.

Parts of the process could reasonably be described as **"vibe-coding adjacent"**, but this was not a one-shot generation exercise. The current release went through repeated manual testing, real-video regression tests, exact SHA-256 gates, release-candidate comparisons, Unicode-path testing, visual byte-identity checks, rollback verification, and controlled promotion.

That does not make the software bug-free. AI-assisted code can still contain poor assumptions, security issues, unnecessary complexity, or simply better ways of solving the same problem. Please review the implementation critically.

## Early-stage project

This works for my current workflow, but I do **not** consider the project finished.

Known areas for improvement include:

- installation and dependency setup;
- GUI polish;
- a cleaner packaged Windows application/executable;
- automated tests and CI;
- error reporting;
- configuration;
- portability;
- additional public source types;
- evidence-selection strategies;
- overall code structure.

See [ROADMAP.md](ROADMAP.md).

## Feedback wanted

One of the main reasons this repository is public is to get feedback.

If you find a bug, security issue, questionable design, unnecessary complexity, better architecture, UX improvement, packaging idea, performance improvement, evidence-selection improvement, or simply a cleaner way to do something, please open an issue.

Constructive criticism is welcome.

- [Issues](https://github.com/abcedi/VideoAI/issues)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)

## Upstream work and acknowledgements

### analysis-video

The most important upstream dependency is [`hwanyong/analysis-video`](https://github.com/hwanyong/analysis-video) by **@hwanyong** and its contributors.

VideoAI uses `analysis-video 0.1.1` as the underlying video-analysis workflow. VideoAI adds its own Windows orchestration, duration-aware evidence policies, package construction, local-file routing, YouTube/TikTok acquisition, provenance handling, GUI, validation gates, and release/deployment workflow around it.

Thank you to @hwanyong and the project contributors for making that work available as open source.

### Other upstream projects

VideoAI also relies directly or indirectly on projects including:

- yt-dlp;
- Playwright Python;
- Requests;
- OpenCV;
- NumPy;
- Pillow;
- faster-whisper;
- CTranslate2;
- PySceneDetect;
- PyAV;
- scikit-image;
- uv;
- Deno;
- FFmpeg / ffprobe;
- NVIDIA CUDA/cuBLAS/cuDNN runtime components.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

If you believe your code, repository, research, documentation, or public example materially influenced VideoAI and should be credited but is missing, please open an issue. I would rather add a missing credit than leave one out.

## Privacy and security

VideoAI is not a cloud service, but URL acquisition is not offline.

- YouTube acquisition contacts YouTube and related endpoints through yt-dlp.
- TikTok acquisition contacts TikTok and media/CDN infrastructure.
- `uv` may contact package indexes while resolving isolated runtime dependencies.
- model/runtime tools may make network requests.

Generated evidence can contain transcript text, screenshots, URLs, titles, creator metadata, filenames, and other provenance.

Review a package before uploading it to an AI provider or sharing it publicly.

See [SECURITY.md](SECURITY.md).

## Responsibility and non-affiliation

VideoAI is not affiliated with, sponsored by, or endorsed by TikTok/ByteDance, YouTube/Google, Microsoft, NVIDIA, FFmpeg, `analysis-video`, or other upstream dependencies unless explicitly stated by those projects.

Users are responsible for complying with applicable law, copyright, privacy requirements, platform terms, content licenses, and organizational policies.

Use the software only for media you are authorized to access and process.

## Repository layout

```text
VideoAI/
├── src/                     backend and acquisition scripts
├── gui/                     Windows Forms GUI
├── docs/                    detailed documentation
├── .github/                 issue/PR templates
├── README.md
├── LICENSE
├── THIRD_PARTY_NOTICES.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
├── SUPPORT.md
├── CHANGELOG.md
└── ROADMAP.md
```

## Documentation

- [Installation](docs/INSTALLATION.md)
- [Usage](docs/USAGE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Evidence format](docs/EVIDENCE_FORMAT.md)
- [Project history](docs/PROJECT_HISTORY.md)
- [Development](docs/DEVELOPMENT.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Roadmap](ROADMAP.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## License

VideoAI's own source code is licensed under the [MIT License](LICENSE).

Third-party projects retain their own copyrights and license terms. VideoAI's MIT license does not replace or relicense third-party software.
