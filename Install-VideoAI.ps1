[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PackageRoot = $PSScriptRoot,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs/VideoAI'),
    [switch]$PrepareRuntime
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'VideoAI.Bootstrap.ps1')
$source = Resolve-VideoAIPackageRoot $PackageRoot
Import-Module (Join-Path $source 'VideoAI.Installation.psm1') -Force
Install-VideoAIPackage -PackageRoot $source -InstallRoot $InstallRoot -PrepareRuntime:$PrepareRuntime -WhatIf:$WhatIfPreference
