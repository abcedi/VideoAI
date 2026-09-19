[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repo = Split-Path $PSScriptRoot -Parent
$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $temp ('VideoAI-packaging-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
function Run-Setup([string[]]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $work 'one/VideoAI-0.6.0-preview.1-Setup.exe'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    foreach ($arg in $Arguments) { $start.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(30000)) { $process.Kill($true); throw 'Setup test timeout' }
        return $process.ExitCode
    }
    finally { $process.Dispose() }
}
try {
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $repo 'packaging/Build-VideoAIRelease.ps1') -OutputDirectory (Join-Path $work 'one') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Setup build failed' }
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $repo 'packaging/Build-VideoAIRelease.ps1') -OutputDirectory (Join-Path $work 'two') -SkipSetup | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Second ZIP build failed' }
    $one = (Get-FileHash -LiteralPath (Join-Path $work 'one/VideoAI-0.6.0-preview.1.zip') -Algorithm SHA256).Hash
    $two = (Get-FileHash -LiteralPath (Join-Path $work 'two/VideoAI-0.6.0-preview.1.zip') -Algorithm SHA256).Hash
    if ($one -ne $two) { throw 'ZIP is not reproducible for identical source bytes' }
    $extract = Join-Path $work "extracted ü user's package"
    if ((Run-Setup @('--quiet','--extract',$extract)) -ne 0) { throw 'Setup payload extraction failed' }
    Import-Module (Join-Path $repo 'VideoAI.Installation.psm1') -Force
    $package = Get-VideoAIPackage $extract
    $original = Get-VideoAIPackage (Join-Path $work 'one/VideoAI-0.6.0-preview.1')
    if ($package.Hash -ne $original.Hash) { throw 'Embedded package differs from portable package' }
    if ((Run-Setup @('--quiet','--extract',$extract)) -eq 0) { throw 'Setup overwrote extraction directory' }
    $target = Join-Path $work "install ü user's app"
    if ((Run-Setup @('--quiet','--what-if','--install-root',$target)) -ne 0) { throw 'Setup WhatIf failed' }
    if (Test-Path -LiteralPath $target) { throw 'Setup WhatIf installed the app' }
    if ((Run-Setup @('--unknown','--quiet')) -eq 0) { throw 'Unknown Setup option accepted' }
    Write-Host 'PASS: reproducible ZIP, embedded setup payload, Unicode extraction, no overwrite and setup WhatIf'
}
finally {
    $safe = [IO.Path]::GetFullPath($work)
    if (-not ($safe.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $safe -Leaf) -like 'VideoAI-packaging-*')) { throw 'Unsafe packaging cleanup' }
    Remove-Item -LiteralPath $safe -Recurse -Force
}
