[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PackageRoot,
    [string]$InstallRoot = $PSScriptRoot,
    [switch]$PrepareRuntime
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'VideoAI.Bootstrap.ps1')
$manager = Resolve-VideoAIPackageRoot $PSScriptRoot
Import-Module (Join-Path $manager 'VideoAI.Installation.psm1') -Force
Install-VideoAIPackage -PackageRoot $PackageRoot -InstallRoot $InstallRoot -Update -PrepareRuntime:$PrepareRuntime -WhatIf:$WhatIfPreference
