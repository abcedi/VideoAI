# Troubleshooting

VideoAI is early-stage, so diagnostics are still developer-oriented.

## Collect versions

```powershell
$PSVersionTable.PSVersion
python --version
uv --version
ffmpeg -version
ffprobe -version
deno --version
nvidia-smi
```

Include relevant versions in bug reports.

## GUI does not start

Try:

```powershell
pwsh -NoProfile -Sta -File .\gui\VideoAI-GUI.ps1 `
    -BackendPath "$PWD\src\Convert-VideoForAI.ps1"
```

Check PowerShell 7, Windows script blocking, and backend path.

## `uv` not found

```powershell
Get-Command uv
uv --version
```

Project: https://github.com/astral-sh/uv

## FFmpeg / ffprobe not found

```powershell
Get-Command ffmpeg
Get-Command ffprobe
```

Both should resolve.

## YouTube acquisition fails

Check public URL availability, network connectivity, current yt-dlp behavior, and Deno availability where required. YouTube frequently changes upstream behavior.

Do not paste account cookies into a public issue.

## TikTok acquisition fails

Check:

- full public TikTok post URL;
- public post availability;
- installed Chrome;
- Playwright browser launch;
- ffprobe availability.

Short redirect URLs are not part of the current validated v0.5.0 contract.

## TikTok browser works but media download fails

Possible causes include CDN/range behavior changes, player changes, region/account restrictions, or session behavior changes.

Redact cookie values and signed media URLs from logs.

## Whisper/CUDA errors

Check `nvidia-smi`, drivers, runtime DLLs, dependency changes, VRAM, and model-download failures.

## Garbled Unicode output

Include PowerShell version, console host, exact visible corruption, and where it appears.

## Unicode path image error

Engine 0.4.2 includes a Windows OpenCV path compatibility fix. If non-ASCII paths still fail, provide a sanitized path structure and characters involved.

## Package incomplete

Do not treat a partially populated job directory as a successful result. Check the logs for the normal completion indication and expected v4 structure.

## Too many images

Short videos intentionally prioritize high recall.

## Too few images

Include duration, archive/read count, selected count, timeline count, and policy identifier in a bug report.

## AI misses something visible

Inspect `timeline_sheets/` and `selected/`. If the package truly omitted an important visual state, use a synthetic/redistributable reproduction where possible.
