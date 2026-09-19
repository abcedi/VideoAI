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

## Installation and distribution v0.6 preview

| Milestone | Current state |
| --- | --- |
| Dependency / health checker | Merged; offline regression and NVIDIA validation passed |
| Install-VideoAI.ps1 | Implemented; transactional per-user installation tested |
| Stable launcher | Implemented; installed/portable path resolution tested |
| Update-VideoAI.ps1 | Implemented; validation before activation and retained releases tested |
| Uninstall-VideoAI.ps1 | Implemented; recorded-file removal and user-file preservation tested |
| Clean Windows VM proof | Pending; no clean desktop VM available |
| CPU-only machine | NVIDIA-required refusal covered by fixtures and a dedicated Windows CI acceptance step |
| NVIDIA/CUDA machine | Prepared-host lifecycle and offline cached Turbo conversion passed |
| Portable ZIP | Built; reproducible bytes and manifest integrity tested |
| Setup.exe | Unsigned preview built; embedded payload and unattended paths tested; manual dialog review pending |

The package version is 0.6.0-preview.1; existing GUI/backend component identities
remain unchanged. This is not the declaration of a completed v0.6 release.
See [distribution instructions](docs/DISTRIBUTION.md).
