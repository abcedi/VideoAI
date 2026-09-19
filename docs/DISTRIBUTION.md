# Installation lifecycle preview

This is a v0.6 preview, not a completed distribution release. Windows x64 and
PowerShell 7 are required. CPU-only conversion is not supported: preflight must
report the NVIDIA/CUDA requirement and stop before activating an application.

## Build

Run `pwsh -NoProfile -File ./packaging/Build-VideoAIRelease.ps1`.
Build outputs go to .artifacts: an unpacked package, a portable ZIP, a
self-extracting Setup.exe, and SHA256SUMS.txt. Use a fresh -OutputDirectory for
each build. Setup compilation uses the Windows .NET Framework C# compiler;
-SkipSetup builds only the package and ZIP. ZIP entry order/timestamps and the
manifest are deterministic for identical inputs. Application files are copied
as exact bytes; build inputs are explicitly listed, excluding local transcripts.

The portable ZIP contains VideoAI and notices, not third-party binaries, CUDA
packages, browsers or Whisper models. It can move between directories but still
requires the documented tools and runtime cache. Checksums detect corruption;
they are not a publisher signature. The preview Setup.exe is unsigned.

## Install and launch

Extract a trusted ZIP and run Install-VideoAI.ps1 from that package. The default
destination is %LOCALAPPDATA%/Programs/VideoAI, separate from legacy ~/Tools
installations. -InstallRoot selects another dedicated directory. Existing
nonempty unmanaged directories and reparse-point paths are refused.

Installation validates the manifest and runs offline preflight. Missing
requirements produce a detailed error without activation. -PrepareRuntime
explicitly allows uv to download the pinned analysis-video[cuda]==0.1.1 runtime
and its dependencies before preflight; it does not install system tools,
NVIDIA drivers, browsers or Whisper models. uv may download Python when needed.
Use -WhatIf to validate package/target structure without health probes,
downloads or filesystem changes.

Use Start-VideoAI.ps1 in the installation directory as the stable entry point.
It resolves the active release, verifies the payload and launches the GUI in an
STA PowerShell process with an explicit backend path. -Describe returns launch
paths without opening the GUI; -Health and -Health -Json run preflight.
The same launcher works directly inside an extracted portable package.

Setup.exe contains the exact portable ZIP. Double-click for a per-user setup
confirmation, or pass --quiet, --install-root PATH, --prepare-runtime, --what-if.
--extract NEW_DIRECTORY extracts the verified payload without installing.
Setup requires an existing PowerShell 7 installation and writes diagnostics to
a uniquely named VideoAI-Setup log in the temporary directory. It does not
weaken execution policy or request administrator privileges.

## Update and uninstall

Run the installed Update-VideoAI.ps1 -PackageRoot PATH_TO_NEW_EXTRACTED_PACKAGE.
The old active release remains selected until the new package passes integrity
and health validation. New releases are staged separately and a same-volume
atomic receipt replacement switches the launcher. Previous release directories
are retained until uninstall. Identical package installation is idempotent.
Concurrent writers fail on the installation lock rather than sharing a stage.
The v1 root entry points stay stable across updates; version-specific management
code is loaded from the active release.

Run the installed Uninstall-VideoAI.ps1, optionally with -WhatIf first.
Uninstall validates its recorded release manifests before deleting any files.
It removes only recorded files whose hashes still match, preserves modified
and unrecorded files, and removes directories only when empty. User media,
job output, uv caches, system dependencies and legacy installations are outside
its ownership. A changed manifest or reparse point causes a safe refusal.

## Acceptance

The deterministic lifecycle tests use temporary packages and simulated health
reports. They cover first install, repeat install, relocation, update,
preflight failure, integrity failure, WhatIf, unmanaged directories, traversal,
and uninstall preservation. These are not a clean Windows VM or physical
CPU-only machine proof. Run the separate machine acceptance script on prepared
NVIDIA hardware before release, then repeat installation/update/uninstall on
a clean Windows VM. Do not mark v0.6 complete from unit tests alone.

## Recorded validation and remaining release gates

The prepared Windows 10 x64 / RTX 3070 Ti / driver 610.62 host passed a temporary
install, installed health check (11 PASS), same-package update and uninstall.
Synthetic six-second video conversion passed offline with an explicit SRT and
with the already cached faster-whisper Turbo model on CUDA. Source SHA-256
was unchanged; output contained 10 selected and 11 timeline frames. The
synthetic tone checks execution, not speech-recognition accuracy.

Repeat the machine tests from a source checkout, supplying a built package:

```powershell
./tests/Test-DistributionMachine.ps1 -PackageRoot PATH_TO_PACKAGE
./tests/Test-ConversionMachine.ps1 -PackageRoot PATH_TO_PACKAGE
./tests/Test-DistributionMachine.ps1 -PackageRoot PATH_TO_PACKAGE -ExpectMissingNvidia
```

Use the last command only on a machine without NVIDIA. The CI workflow runs it
on an ephemeral Windows runner, separately from simulated unit fixtures.
That preconfigured CI image is not a clean Windows desktop installation proof.

A clean Windows desktop VM is not available in the current environment. That
milestone remains pending. On that VM, first verify clear missing-prerequisite
errors, then install the documented system tools, and rerun the applicable
acceptance script. A machine without NVIDIA must refuse activation; CPU
conversion is intentionally out of scope. Review the setup dialog manually
before a public release. These preview artifacts are not a signed final v0.6
release, and no GitHub release is published by the build script.
