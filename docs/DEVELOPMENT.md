# Development

VideoAI v0.5.0 is the first public development baseline.

## Run from source

```powershell
pwsh -NoProfile -Sta -File .\gui\VideoAI-GUI.ps1 `
    -BackendPath "$PWD\src\Convert-VideoForAI.ps1"
```

## Current identities

```text
GUI                     0.5.0
TikTok acquisition      0.5.0
Evidence engine         0.4.2
YouTube acquisition     0.2.1
Evidence format         video-ai-evidence/v4
analysis-video          0.1.1
```

## Current testing philosophy

The pre-public release process used:

- read-only preflight audits;
- exact SHA-256 gates;
- isolated dev copies;
- release candidates;
- syntax checks;
- real-video integration/regression tests;
- evidence count comparison;
- evidence-image byte-identity comparison;
- rollback backups;
- post-promotion audits.

## Representative modes

### Local

Confirms local routing, common backend, transcription path, and short-form evidence behavior.

### YouTube

Confirms URL routing, yt-dlp acquisition, caption handling, and long-form evidence behavior.

### TikTok

Confirms canonical URL parsing, oEmbed, official-player acquisition, media validation, transcription, and short-form evidence behavior.

## Test media

Do not commit arbitrary downloaded TikTok/YouTube media.

Use synthetic media or explicitly redistributable fixtures with documented licenses.

## Evidence-policy changes

Treat changes to pHash thresholds, max-gap timing, duration boundary, timeline selection, sheet layout, image encoding, or selection ordering as behavior changes.

Compare selected filenames/counts, timeline counts, image hashes, package metadata, and practical analysis quality.

## Unicode paths

Windows Unicode paths are a regression area. Engine 0.4.2 uses byte-based OpenCV image decoding. Include non-ASCII paths in relevant tests.

## Network acquisition

Test invalid URLs, unsupported hosts, redirects, partial responses, unavailable browser/runtime, cleanup after failure, filename sanitization, and ffprobe failures.

## Secrets

Never add real credentials to fixtures. The project should remain usable without private browser profiles, saved account cookies, or API keys.

## Dependency changes

Verify license, update `THIRD_PARTY_NOTICES.md`, document behavior impact, and consider binary redistribution implications.

## Known infrastructure gaps

- no mature automated test suite;
- no CI;
- no installer;
- no formal VideoAI package manifest;
- no automated release build;
- no cross-platform support contract.
