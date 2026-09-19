# Installation

VideoAI is a Windows-first developer-oriented release. A v0.6 installation preview now provides per-user install, launch, update and uninstall scripts plus portable ZIP and Setup.exe builds. See [DISTRIBUTION.md](DISTRIBUTION.md) for the preview workflow and outstanding release gates. The source/manual layout below remains supported.

## Tested environment

The release was validated with:

- Windows 10;
- PowerShell 7;
- Python 3.13;
- uv;
- FFmpeg / ffprobe;
- Google Chrome;
- Deno;
- NVIDIA GPU/CUDA environment.

These are tested conditions, not necessarily hard minimum versions.

## Required tools

Verify the main external tools:

```powershell
pwsh --version
python --version
uv --version
ffmpeg -version
ffprobe -version
deno --version
```

For NVIDIA systems:

```powershell
nvidia-smi
```

## Run directly from a clone

```powershell
git clone https://github.com/abcedi/VideoAI.git
Set-Location .\VideoAI

pwsh -NoProfile -Sta -File .\gui\VideoAI-GUI.ps1 `
    -BackendPath "$PWD\src\Convert-VideoForAI.ps1"
```

Keep the `src` files together. The GUI resolves acquisition helpers beside the selected backend wrapper.

## Optional development-style local install

The GUI's default production-style paths are:

```text
~/Tools/VideoAI
~/Tools/VideoAI-GUI
```

You can copy the six `src` files into `~/Tools/VideoAI` and `gui/VideoAI-GUI.ps1` into `~/Tools/VideoAI-GUI`.

Then launch:

```powershell
pwsh -NoProfile -Sta -File "$HOME\Tools\VideoAI-GUI\VideoAI-GUI.ps1"
```

## Execution policy

Do not globally weaken PowerShell security controls just to run VideoAI.

If Windows marks downloaded scripts as blocked, inspect the source and use normal Windows/PowerShell mechanisms to unblock only trusted files as needed.

## First-run downloads

The current wrappers use isolated runtime dependency resolution. First run may take longer while `uv` resolves/downloads dependencies or Whisper model data.

Network access is also required for YouTube/TikTok URL acquisition.

## Next

See [USAGE.md](USAGE.md). For failures, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Offline dependency preflight

Run `pwsh -NoProfile -File ./src/Test-VideoAIHealth.ps1` before conversion.
Add `-Json` for a structured report. System Python and WinGet are optional;
the current conversion path requires the cached CUDA runtime.
See [HEALTH_CHECKER.md](HEALTH_CHECKER.md) for exit codes and setup boundaries.
