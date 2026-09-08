# Project History

VideoAI grew incrementally from a specific personal problem.

This document describes that progression without pretending private pre-GitHub versions were historical public commits.

## 1. Informational TikTok videos

The original use case was informational TikTok content that I wanted an AI chat to understand.

The first obvious workflow was:

```text
video -> speech-to-text -> transcript -> AI
```

## 2. Transcript-only context was incomplete

Many useful details were shown rather than spoken: commands, menus, code, URLs, settings, diagrams, product names, screenshots, and step-by-step UI changes.

The problem became:

> How can I convert a video into something an AI can read while preserving both what was said and what was shown?

## 3. TikTokAI

The first workflow became TikTokAI and combined transcript + important screenshots + chronological visual context.

That established the core idea that survives today: **video should be treated as multimodal evidence, not only audio with subtitles.**

## 4. Evidence selection

Capturing every frame is wasteful, so the workflow evolved toward archive/read frames, perceptual similarity, selected evidence frames, overview sheets, and timeline sheets.

Short-form content intentionally prioritized high recall.

## 5. Windows GUI

A Windows Forms GUI was added to make repeated use easier.

Private early GUI versions went through fixes around background jobs, output/progress, Unicode, friendly job names, and backend integration.

Historical archives are preserved privately for future archaeology. They are not committed here as fake historical revisions.

## 6. TikTokAI became VideoAI

Once the workflow could process generic local video, the project became source-neutral VideoAI:

```text
video source -> validated local media -> common evidence backend
```

## 7. YouTube

YouTube processing was added, initially for already-downloaded media.

## 8. Integrated YouTube acquisition

Direct YouTube acquisition using yt-dlp removed the separate download step and allowed source subtitles/captions to be preferred before Whisper.

## 9. Integrated TikTok acquisition

The project returned to its original source platform by adding direct public TikTok post acquisition.

The v0.5.0 flow supports:

```text
local video
YouTube URL
TikTok URL
    ↓
common VideoAI evidence package
```

## 10. `video-ai-evidence/v4`

The package evolved into a source-neutral contract. `ConvertedVideo` became the primary cue while `ConvertedTikTok` remained as a compatibility alias.

## 11. First public release

VideoAI v0.5.0 is the first version in this public Git history.

```text
GUI                     0.5.0
TikTok acquisition      0.5.0
Evidence engine         0.4.2
YouTube acquisition     0.2.1
Evidence format         video-ai-evidence/v4
analysis-video          0.1.1
```

## AI-assisted development

AI was used extensively for research, architecture, code generation, debugging, refactoring, testing plans, and documentation.

The project also used manual real-video validation, hash gates, regression comparisons, and controlled release promotion.

## History is still being documented

If later archaeology of the private snapshots reveals missing attribution or a useful milestone, this document should be corrected and expanded.
