# Machine acceptance uses installed dependencies and the existing uv cache.
# It stays offline, but is intentionally separate from deterministic CI tests.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$checker = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Test-VideoAIHealth.ps1'
$pwsh = Join-Path $PSHOME 'pwsh.exe'
function Assert-Report($Report, [string]$RuntimeStatus) {
    if ($Report.Checks.Count -ne 11 -or $Report.Summary.Total -ne 11 -or
        @($Report.Checks | Where-Object Required).Count -ne 9 -or
        ($Report.Checks | Where-Object Name -eq 'VideoAI CUDA Runtime').Status -ne $RuntimeStatus) {
        throw 'Unexpected check count or CUDA runtime status'
    }
}
& $pwsh -NoProfile -File $checker
if ($LASTEXITCODE -ne 0) { throw 'Normal human mode failed' }
$output = & $pwsh -NoProfile -File $checker -Json
if ($LASTEXITCODE -ne 0) { throw 'Normal JSON mode failed' }
$report = ($output -join [char]10) | ConvertFrom-Json
Assert-Report $report 'PASS'
if (($report.Checks | Where-Object Name -eq 'VideoAI CUDA Runtime').Detail -match '\{\d+\}') { throw 'Unformatted CUDA detail' }
Write-Host 'PASS: normal human/JSON exits 0; 11 checks, 9 required, CUDA PASS'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$cache = Join-Path $tempRoot ('VideoAI-empty-cache-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $cache
$oldCache = $env:UV_CACHE_DIR
try {
    $env:UV_CACHE_DIR = $cache
    $output = & $pwsh -NoProfile -File $checker -Json
    if ($LASTEXITCODE -ne 1) { throw 'Empty cache must exit 1' }
    $report = ($output -join [char]10) | ConvertFrom-Json
    Assert-Report $report 'MISSING'
    if (($report.Checks | Where-Object Name -eq 'VideoAI CUDA Runtime').Detail -notmatch 'Offline') { throw 'Offline diagnostic missing' }
    if ($report.Summary.MissingRequired -ne 1) { throw 'Only the uncached runtime should be missing' }
    Write-Host 'PASS: empty uv cache; CUDA MISSING; exit 1'
}
finally {
    $env:UV_CACHE_DIR = $oldCache
    $resolved = [IO.Path]::GetFullPath($cache)
    if (-not ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf) -like 'VideoAI-empty-cache-*')) { throw 'Unsafe cache cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$hash = (Get-FileHash -LiteralPath $checker -Algorithm SHA256).Hash
Write-Host "CheckerSHA256=$hash"
