# video-ai-evidence/v4

VideoAI v0.5.0 produces packages using the `video-ai-evidence/v4` contract.

The purpose is to preserve enough speech and visual context that another AI or reviewer can inspect the material without repeatedly processing the original video.

## Layout

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

## Recommended inspection order

1. `compact_context.md`
2. transcript
3. `visual_sheets/`
4. `timeline_sheets/` when chronology/detail matters
5. `selected/` for individual evidence

## Key files

### `README_AI.md`

AI-facing explanation of package purpose, inspection guidance, evidence hierarchy, provenance, and limitations.

### `compact_context.md`

Compact package/source context.

### `TIMELINE_EVIDENCE.md`

Chronological visual-evidence index.

### `transcript.txt` / `transcript.json`

Human-readable and structured transcript data. Content can come from source captions/subtitles or Whisper/faster-whisper.

ASR is not guaranteed to be correct.

### `selection.json`

Machine-readable selection/policy metadata.

### `SOURCE.txt`

Source/provenance information. Review it before sharing a package publicly.

### `selected/`

Individual selected evidence images.

### `visual_sheets/`

Overview contact sheets.

### `timeline_sheets/`

Chronological visual sheets intended to retain transient UI/visual changes.

## Short-form policy

Duration: `<= 180 seconds`

Identifier:

```text
short-form-high-recall-v0.3.1
```

Parameters:

```text
selected pHash threshold: 18
selected maximum gap: 2.5 seconds
timeline: every archive read frame
```

Design intent: high visual recall.

## Long-form policy

Duration: `> 180 seconds`

Identifier:

```text
long-form-balanced-a
```

Parameters:

```text
selected pHash threshold: 20
selected maximum gap: 6 seconds
timeline pHash threshold: 24
timeline maximum gap: 6 seconds
```

Design intent: balance visual recall against package size.

## Visible evidence versus transcript

Speech recognition can be wrong. When exact on-screen labels, commands, numbers, URLs, product names, or diagrams matter, the image evidence is authoritative for what was visibly shown.

## Package cues

Primary cue:

```text
ConvertedVideo
```

Legacy-compatible cue:

```text
ConvertedTikTok
```

The second remains because the project began as a TikTok-specific workflow.

## Compatibility

`video-ai-evidence/v4` is a package contract. Incompatible semantic changes should use a new format version rather than silently changing v4.
