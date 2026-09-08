# Usage

VideoAI v0.5.0 has three primary workflows:

1. local video;
2. public YouTube URL;
3. full public TikTok post URL.

All successful workflows converge on the same evidence backend.

## Launch

From the repository root:

```powershell
pwsh -NoProfile -Sta -File .\gui\VideoAI-GUI.ps1 `
    -BackendPath "$PWD\src\Convert-VideoForAI.ps1"
```

## Local video

Select a local video and start conversion.

A URL may still be supplied as provenance.

**Local precedence:** when both a valid local file and a URL exist, VideoAI processes the local file instead of redownloading it.

## YouTube URL

Leave the local-video field empty and provide a supported public YouTube URL.

High-level flow:

```text
YouTube URL
    ↓
yt-dlp acquisition
    ↓
media + metadata + captions when available
    ↓
common evidence backend
    ↓
AI package
```

Transcript preference:

```text
explicit/manual subtitle
    ↓
automatic caption
    ↓
Whisper fallback
```

## TikTok URL

Leave the local-video field empty and provide a full public TikTok post URL.

High-level flow:

```text
TikTok post URL
    ↓
public oEmbed metadata
    ↓
official TikTok player
    ↓
Playwright + installed Chrome
    ↓
validated MP4
    ↓
common evidence backend
    ↓
Whisper when no explicit transcript exists
    ↓
AI package
```

The current validated v0.5.0 input contract expects a full canonical TikTok post URL. Short redirect URLs are not yet part of the tested contract.

The workflow does not import the user's normal logged-in browser profile/cookies.

## Output

Successful conversion produces an `*-ai.zip` package containing transcript, selected frames, overview sheets, timeline sheets, and provenance/evidence metadata.

See [EVIDENCE_FORMAT.md](EVIDENCE_FORMAT.md).

## Privacy reminder

Generated packages can preserve visible/spoken private information. Inspect transcript, screenshots, filenames, URLs, and `SOURCE.txt` before sharing.
