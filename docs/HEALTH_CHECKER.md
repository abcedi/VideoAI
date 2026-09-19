# Dependency health checker

Run from the repository root with PowerShell 7 on Windows x64:

```powershell
pwsh -NoProfile -File ./src/Test-VideoAIHealth.ps1
pwsh -NoProfile -File ./src/Test-VideoAIHealth.ps1 -Json
```

The checker reports eleven results: nine required checks (Windows/x64,
PowerShell 7, uv, FFmpeg, ffprobe, Deno, Chrome, NVIDIA GPU/driver, and the VideoAI
CUDA runtime) and two optional checks (system Python and WinGet). It checks the
current NVIDIA conversion contract; it does not promise CPU-only support.
Windows Store Python aliases are treated as optional/unavailable to avoid
launching an installation prompt.

JSON uses schema `videoai-health/v1`, with architecture, per-check
Name/Status/Required/RequiredFor/Version/Path/Detail, and summary counts.
`GeneratedUtc` and detected machine values vary by run.
Missing optional tools use status OPTIONAL and do not block readiness.

| Exit | Meaning |
| --- | --- |
| 0 | All required checks pass |
| 1 | At least one required dependency is missing or unusable |
| 2 | The checker itself failed; JSON contains Error |

`-ChromePath` and `-NvidiaSmiPath` override discovery without fallback, so
missing explicit paths produce MISSING. Native probes capture their output,
preserve failures, and time out after 60 seconds. The embedded doctor has a
30-second timeout.

The runtime check uses the same `analysis-video[cuda]==0.1.1` requirement as
conversion. It calls uv with --offline, --no-python-downloads, and --no-project;
checks cuBLAS/cuDNN DLLs and CTranslate2 CUDA capability; then runs
analysis-video doctor in that environment. It reports installed dependency
versions rather than claiming that transitive versions are locked.

No software is installed from the network, system configuration is not changed,
and no browser or video acquisition is launched. uv may create/reuse local
cache environments from already cached packages. A fresh cache therefore
reports the runtime as MISSING even when the NVIDIA driver works. Preparing
that cache belongs to the future installer or an explicit runtime setup step.

## Regression

```powershell
pwsh -NoProfile -File ./tests/Run-Regression.ps1
```

This deterministic offline suite needs PowerShell only. It extracts the actual
GUI/wrapper integrity guard AST statements, hashes temporary fixtures, and proves:

- canonical LF wrapper acceptance;
- approved transitional CRLF wrapper acceptance;
- arbitrary and single-byte-tampered wrapper rejection;
- canonical Python helper acceptance;
- arbitrary and unapproved CRLF Python helper rejection.

The exact two wrapper pins, parser validity, LF source bytes, and UTF-8 BOM
absence are checked. The test does not run the full GUI or download wrapper.
Intentional pin changes require reviewing and updating these regression
expectations; new wrapper content is not automatically approved.

Health tests use deterministic local probe fixtures and the production report
block to verify nine required registrations, two optional results, CUDA
classification, offline arguments, malformed JSON, native failures/timeouts,
and human/JSON exits 0, 1, and 2. CI runs this suite on Windows. CI checkout
requires GitHub access; the test suite itself does not require network access.

## Machine acceptance and seal

On a machine with all required dependencies already prepared:

```powershell
pwsh -NoProfile -File ./tests/Test-HealthMachine.ps1
```

This separate offline acceptance test verifies real human/JSON success and
11 actual checks, then uses a new temporary empty uv cache to assert CUDA
MISSING with exit 1. It restores UV_CACHE_DIR and removes only its test cache.
The machine acceptance test is deliberately excluded from deterministic CI.

Verified on Windows 10 x64 / PowerShell 7.6.6 / RTX 3070 Ti / driver 610.62.
The initial CUDA-registration gate passed nine actual checks and both exits 0.
The completed checker passed eleven checks (nine required), both normal exits
0, and empty-cache MISSING/exit 1.

Sealed SHA-256 of src/Test-VideoAIHealth.ps1:

```text
21163BFD275D33499DAB2352834DECE9FE4D934D5342594B88B3E41981EA4810
```

This is the health-checker deliverable for the v0.6 installation work. See
[DISTRIBUTION.md](DISTRIBUTION.md) for the lifecycle and packaging preview,
machine acceptance commands, and remaining clean-VM release gate.
