[CmdletBinding()]
param([switch]$Describe, [switch]$Health, [switch]$Json)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'VideoAI.Bootstrap.ps1')
$source = Resolve-VideoAIPackageRoot $PSScriptRoot
Import-Module (Join-Path $source 'VideoAI.Installation.psm1') -Force
Invoke-VideoAILaunch -PackageRoot $source -Describe:$Describe -Health:$Health -Json:$Json
if ($Health) { exit $LASTEXITCODE }
