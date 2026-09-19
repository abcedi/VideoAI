[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
foreach ($test in @('Test-TikTokIntegrity.ps1', 'Test-VideoAIHealth.ps1')) {
    & (Join-Path $PSHOME 'pwsh.exe') -NoLogo -NoProfile -File (Join-Path $PSScriptRoot $test)
    if ($LASTEXITCODE -ne 0) { throw "$test failed with exit $LASTEXITCODE" }
}
Write-Host 'PASS: all offline regression suites'
