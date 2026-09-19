[CmdletBinding(SupportsShouldProcess)]
param([string]$InstallRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'VideoAI.Bootstrap.ps1')
$manager = Resolve-VideoAIPackageRoot $PSScriptRoot
Import-Module (Join-Path $manager 'VideoAI.Installation.psm1') -Force
Uninstall-VideoAIPackage -InstallRoot $InstallRoot -WhatIf:$WhatIfPreference
