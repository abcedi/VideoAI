# Contributing to VideoAI

Contributions, criticism, bug reports, experiments, documentation fixes, and design suggestions are welcome.

VideoAI began as a personal tool and is still an early project. One reason it is public is to expose the implementation to people who may see better ways to solve the same problems.

## Before contributing

Please read:

- [README.md](README.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/EVIDENCE_FORMAT.md](docs/EVIDENCE_FORMAT.md)
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- [SECURITY.md](SECURITY.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

## Useful contributions

Examples include:

- bug/security fixes;
- better error messages;
- portability improvements;
- installation improvements;
- automated tests;
- performance improvements;
- better frame-selection logic;
- better long-form handling;
- GUI/accessibility improvements;
- packaging/installer work;
- refactoring that reduces complexity;
- additional public URL sources;
- documentation improvements.

## Discuss substantial changes first

Please open an issue before large architectural changes such as:

- replacing the analysis backend;
- changing evidence thresholds;
- changing the `video-ai-evidence/v4` contract;
- adding browser login/cookie import;
- changing provenance semantics;
- introducing a new installer/executable packaging system.

## Development principles

### Local input stays first-class

A local file should not depend on an online acquisition service.

### Local file wins over URL

When both valid local media and a URL exist, the local media is processed. The URL may remain as provenance.

### Acquisition stays separate from evidence analysis

YouTube/TikTok acquisition should produce validated local media before the common evidence backend runs.

### Fail closed on incomplete acquisition

Do not silently hand an incomplete media download to the evidence engine.

### Preserve provenance without preserving secrets

Stable source URLs and useful metadata are valuable. Unnecessary cookies, signed URLs, or account state are not.

### Do not import private browser state by default

The current TikTok workflow does not import a user's normal logged-in browser cookies.

### Evidence-format changes require explicit versioning

Do not silently change the meaning of `video-ai-evidence/v4`.

## Testing

The current release was validated across:

1. local video;
2. public YouTube URL;
3. public TikTok URL.

When practical, include source type, duration, transcript source, frame counts, package results, and relevant hashes.

Do not commit arbitrary third-party test videos. Prefer synthetic or clearly redistributable fixtures.

## Security-sensitive changes

Be especially careful with:

- cookies/auth headers;
- signed media URLs;
- browser profiles;
- URL validation/redirects;
- subprocess execution;
- shell quoting;
- temporary files;
- archive creation;
- output provenance.

See [SECURITY.md](SECURITY.md).

## Dependencies and licensing

If adding a dependency:

1. explain why;
2. link upstream;
3. identify its license;
4. update `THIRD_PARTY_NOTICES.md`;
5. avoid vendoring upstream source without a clear reason.

## AI-assisted contributions

AI-assisted contributions are allowed.

If AI materially generated or modified code, contributors are encouraged to describe how it was used and what human review/testing was performed.

AI-generated code should be reviewed and tested like any other code.

## Pull requests

A good PR explains:

- the problem;
- the solution;
- what changed;
- how it was tested;
- compatibility impact;
- security/privacy impact;
- dependency/license changes.

Keep unrelated changes separate when possible.
