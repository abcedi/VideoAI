# Hardware/model acceptance: requires the existing CUDA runtime and cached Turbo model.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageRoot)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $temp ('VideoAI-conversion-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$oldOffline = $env:UV_OFFLINE
$oldHubOffline = $env:HF_HUB_OFFLINE
try {
    $env:UV_OFFLINE = '1'
    $env:HF_HUB_OFFLINE = '1'
    $video = Join-Path $work 'synthetic.mp4'
    & ffmpeg -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=640x360:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=16000' -t 6 -c:v libx264 -pix_fmt yuv420p -c:a aac $video
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic video creation failed' }
    $before = (Get-FileHash -LiteralPath $video -Algorithm SHA256).Hash
    $jobs = Join-Path $work 'jobs'
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $PackageRoot 'src/Convert-VideoForAI.ps1') -Video $video -OutputRoot $jobs *> (Join-Path $work 'conversion.log')
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath (Join-Path $work 'conversion.log') -Tail 30
        throw 'Offline CUDA conversion failed'
    }
    $transcripts = @(Get-ChildItem -LiteralPath $jobs -Recurse -Filter transcript.json | Where-Object FullName -Match 'archive-analysis')
    if ($transcripts.Count -ne 1) { throw 'Expected one analysis transcript' }
    $transcript = Get-Content -LiteralPath $transcripts[0].FullName -Raw | ConvertFrom-Json
    if ($transcript.device -ne 'cuda' -or $transcript.backend -ne 'faster-whisper' -or $transcript.model -ne 'turbo') {
        throw 'Did not exercise CUDA Turbo transcription'
    }
    $zips = @(Get-ChildItem -LiteralPath $jobs -Recurse -Filter '*-ai.zip')
    if ($zips.Count -ne 1 -or (Get-FileHash -LiteralPath $video -Algorithm SHA256).Hash -ne $before) { throw 'Evidence ZIP/source integrity failure' }
    $archive = [IO.Compression.ZipFile]::OpenRead($zips[0].FullName)
    try {
        foreach ($name in @('README_AI.md','transcript.json','selection.json','SOURCE.txt')) {
            if (-not ($archive.Entries | Where-Object FullName -eq $name)) { throw "Evidence ZIP missing $name" }
        }
        if (@($archive.Entries | Where-Object FullName -like 'selected/*.jpg').Count -eq 0) { throw 'No selected evidence frames' }
    }
    finally { $archive.Dispose() }
    Write-Host 'PASS: offline cached CUDA Turbo transcription, evidence ZIP and unchanged synthetic source'
    Write-Host 'Synthetic tone is an execution test, not a transcription-accuracy evaluation.'
}
finally {
    $env:UV_OFFLINE = $oldOffline
    $env:HF_HUB_OFFLINE = $oldHubOffline
    $safe = [IO.Path]::GetFullPath($work)
    if (-not ($safe.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $safe -Leaf) -like 'VideoAI-conversion-*')) { throw 'Unsafe conversion cleanup' }
    Remove-Item -LiteralPath $safe -Recurse -Force
}
exit 0
