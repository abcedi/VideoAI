# Changelog

This changelog tracks the public VideoAI repository.

The project existed privately in earlier TikTokAI/VideoAI forms before this public Git repository. Those versions are not represented by fabricated historical Git commits.

## [0.5.0] - 2026-09

Initial public release.

### Added

- Windows GUI for local video, YouTube URL, and TikTok URL workflows.
- Common evidence backend shared by all source modes.
- `video-ai-evidence/v4` package contract.
- Short-form and long-form evidence policies.
- AI-ready transcript + selected visual evidence packaging.
- YouTube acquisition with caption/subtitle preference.
- TikTok public-post acquisition using oEmbed + official player + Playwright/Chrome.
- Source/provenance metadata.
- Windows Unicode-path-safe OpenCV image decoding in evidence engine 0.4.2.

### Current policies

Short form:

```text
short-form-high-recall-v0.3.1
selected pHash: 18
max selected gap: 2.5 s
timeline: every archive read frame
```

Long form:

```text
long-form-balanced-a
selected pHash: 20
max selected gap: 6 s
timeline pHash: 24
max timeline gap: 6 s
```

### Validation

The release was regression-tested with local video, long-form YouTube, and short-form TikTok URL acquisition.

Release promotion used exact SHA-256 gates and retained verified rollback copies during deployment.

## Before 0.5.0

The project evolved privately through multiple TikTokAI and VideoAI development versions.

See [docs/PROJECT_HISTORY.md](docs/PROJECT_HISTORY.md).
