# VideoAI Roadmap

This is a direction document, not a promise or release schedule.

## Near-term priorities

### Easier installation

- dependency preflight;
- bootstrap/install helper;
- clearer first-run setup;
- automatic checks for FFmpeg, Chrome, Deno, uv, Python, and CUDA capability.

### GUI improvements

- more polished design;
- clearer mode selection;
- better progress reporting/cancellation;
- actionable errors;
- output-folder shortcuts;
- package preview;
- accessibility review.

### Packaged Windows application

A future goal is a cleaner executable/application distribution.

Packaging must be evaluated carefully because redistributing FFmpeg, browsers, yt-dlp artifacts, or GPU runtimes can change licensing/update responsibilities.

### Automated testing

- Python unit tests;
- PowerShell tests where practical;
- acquisition parser tests;
- package-contract tests;
- Unicode/path tests;
- synthetic media fixtures;
- deterministic evidence tests;
- CI.

## Evidence improvements

Ideas include:

- configurable evidence budgets;
- motion-aware selection;
- OCR/text-aware importance scoring;
- UI-change scoring;
- semantic duplicate suppression;
- better long-form chapter segmentation;
- context-limit-aware output sizing.

Changes should be measured against practical analysis quality, not only frame-count reduction.

## Acquisition improvements

- better redirect handling;
- clearer supported-URL validation;
- additional public video sources;
- stronger provenance schema;
- improved network error classification.

Authentication/cookie-import workflows are intentionally not a casual roadmap item because they add privacy/security complexity.

## Platform support

Current priority: **Windows**.

Future investigation: Linux and macOS.

## Developer experience

- formal `pyproject.toml`;
- dependency manifests/lock strategy;
- reproducible dev environment;
- linting/formatting;
- CI;
- automated releases;
- cleaner version management.
