# Real-machine acceptance; never included in deterministic CI.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageRoot,
    [switch]$ExpectMissingNvidia,
    [string]$SetupPath
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $temp ('VideoAI-machine-' + [guid]::NewGuid().ToString('N'))
$root = Join-Path $work 'application'
$null = New-Item -ItemType Directory -Path $work
try {
    if ($ExpectMissingNvidia) {
        $output = & $pwsh -NoProfile -File (Join-Path $PackageRoot 'src/Test-VideoAIHealth.ps1') -Json
        $code = $LASTEXITCODE
        $report = ($output -join [char]10) | ConvertFrom-Json
        if ($code -ne 1 -or ($report.Checks | Where-Object Name -eq 'NVIDIA GPU/Driver').Status -ne 'MISSING') {
            throw 'This machine does not demonstrate missing NVIDIA hardware/driver.'
        }
        & $pwsh -NoProfile -File (Join-Path $PackageRoot 'Install-VideoAI.ps1') -InstallRoot $root
        if ($LASTEXITCODE -eq 0 -or (Test-Path -LiteralPath $root)) { throw 'NVIDIA-required install refusal failed' }
        Write-Host 'PASS: real machine without NVIDIA refuses installation before activation'
    }
    else {
        if ($SetupPath) {
            $start = [Diagnostics.ProcessStartInfo]::new()
            $start.FileName = (Resolve-Path -LiteralPath $SetupPath).Path
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            foreach ($arg in @('--quiet','--install-root',$root)) { $start.ArgumentList.Add($arg) }
            $process = [Diagnostics.Process]::Start($start)
            try {
                if (-not $process.WaitForExit(120000)) { $process.Kill($true); throw 'Setup acceptance timed out' }
                if ($process.ExitCode -ne 0) { throw 'Setup.exe installation failed; see VideoAI-Setup log in TEMP' }
            }
            finally { $process.Dispose() }
        }
        else {
            & $pwsh -NoProfile -File (Join-Path $PackageRoot 'Install-VideoAI.ps1') -InstallRoot $root
            if ($LASTEXITCODE -ne 0) { throw 'Install failed' }
        }
        & $pwsh -NoProfile -File (Join-Path $root 'Start-VideoAI.ps1') -Health -Json
        if ($LASTEXITCODE -ne 0) { throw 'Installed health check failed' }
        & $pwsh -NoProfile -File (Join-Path $root 'Update-VideoAI.ps1') -PackageRoot $PackageRoot
        if ($LASTEXITCODE -ne 0) { throw 'Update failed' }
        & $pwsh -NoProfile -File (Join-Path $root 'Uninstall-VideoAI.ps1')
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $root)) { throw 'Uninstall did not remove unchanged application' }
        Write-Host 'PASS: real NVIDIA install/health/update/uninstall'
    }
}
finally {
    $safe = [IO.Path]::GetFullPath($work)
    if (-not ($safe.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $safe -Leaf) -like 'VideoAI-machine-*')) { throw 'Unsafe acceptance cleanup' }
    Remove-Item -LiteralPath $safe -Recurse -Force
}
exit 0
