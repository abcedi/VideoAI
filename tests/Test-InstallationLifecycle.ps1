[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest
$repository = Split-Path $PSScriptRoot -Parent
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $tempRoot ('VideoAI-lifecycle-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$utf8 = [Text.UTF8Encoding]::new($false)
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Run-Script([string]$Path, [string[]]$Arguments = @()) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $pwsh
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['UV_OFFLINE'] = '1'
    foreach ($argument in (@('-NoProfile','-File',$Path) + $Arguments)) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill($true); throw "Test timed out: $Path" }
        [PSCustomObject]@{ Code=$process.ExitCode; Output=$stdout.GetAwaiter().GetResult(); Error=$stderr.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}
function Write-FixtureHealth([string]$Path, [switch]$MissingNvidia) {
    $checks = @()
    foreach ($name in @('Windows','PowerShell','uv','FFmpeg','ffprobe','Deno','Google Chrome','NVIDIA GPU/Driver','VideoAI CUDA Runtime','System Python','WinGet')) {
        $checks += [ordered]@{ Name=$name; Required=($name -notin @('System Python','WinGet')); Status=$(if ($MissingNvidia -and $name -eq 'NVIDIA GPU/Driver') { 'MISSING' } else { 'PASS' }); Detail='Local fixture' }
    }
    $report = @{ Schema='videoai-health/v1'; Checks=$checks } | ConvertTo-Json -Depth 5 -Compress
    $code = if ($MissingNvidia) { 1 } else { 0 }
    [IO.File]::WriteAllText($Path, 'param([switch]$Json); ' + "'" + $report + "'; exit $code" + [char]10, $utf8)
}
function Seal-Fixture([string]$Package, [string]$Version) {
    $path = Join-Path $Package 'package-manifest.json'
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $manifest.Version = $Version
    foreach ($file in $manifest.Files) { $file.SHA256 = (Get-FileHash -LiteralPath (Join-Path $Package $file.Path) -Algorithm SHA256).Hash }
    [IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 6) + [char]10, $utf8)
}
function Require-Success($Result, [string]$Message) {
    Assert-True ($Result.Code -eq 0) "$Message : $($Result.Output) $($Result.Error)"
    Write-Host "PASS: $Message"
}
try {
    $buildOutput = Join-Path $work 'build'
    $result = Run-Script (Join-Path $repository 'packaging/Build-VideoAIRelease.ps1') @('-OutputDirectory',$buildOutput,'-SkipSetup')
    Require-Success $result 'explicit package build'
    $package = Join-Path $buildOutput 'VideoAI-0.6.0-preview.1'
    $health = Join-Path $package 'src/Test-VideoAIHealth.ps1'
    # Only fixtures use simulated health. Public entry points have no skip-health switch.
    Write-FixtureHealth $health
    Seal-Fixture $package '0.6.0-test.1'
    $root = Join-Path $work "installed ü user's app"
    $install = Join-Path $package 'Install-VideoAI.ps1'
    $result = Run-Script $install @('-InstallRoot',$root,'-WhatIf')
    Require-Success $result 'install WhatIf'
    Assert-True (-not (Test-Path -LiteralPath $root)) 'WhatIf created target'
    $unmanaged = Join-Path $work 'unmanaged'
    $null = New-Item -ItemType Directory -Path $unmanaged
    [IO.File]::WriteAllText((Join-Path $unmanaged 'personal.txt'),'keep',$utf8)
    $result = Run-Script $install @('-InstallRoot',$unmanaged)
    Assert-True ($result.Code -ne 0 -and (Get-Content -LiteralPath (Join-Path $unmanaged 'personal.txt') -Raw) -eq 'keep') 'Unmanaged target protection'
    $outside = Join-Path $work 'junction-target'
    $link = Join-Path $work 'junction'
    $null = New-Item -ItemType Directory -Path $outside
    $null = New-Item -ItemType Junction -Path $link -Target $outside
    try {
        $result = Run-Script $install @('-InstallRoot',(Join-Path $link 'application'))
        Assert-True ($result.Code -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $outside 'application'))) 'Reparse-point install target accepted'
    }
    finally {
        $safeLink = [IO.Path]::GetFullPath($link)
        Assert-True ($safeLink.StartsWith($work + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'Unsafe junction cleanup'
        [IO.Directory]::Delete($safeLink,$false)
    }
    Write-Host 'PASS: reparse-point installation target refused'
    $result = Run-Script $install @('-InstallRoot',$root)
    Require-Success $result 'first per-user install with Unicode, spaces and apostrophe'
    $receiptPath = Join-Path $root 'installation.json'
    $before = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    $result = Run-Script $install @('-InstallRoot',$root)
    Require-Success $result 'idempotent repeated install'
    Assert-True ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -eq $before) 'Repeated install changed receipt'
    $launcher = Join-Path $root 'Start-VideoAI.ps1'
    $result = Run-Script $launcher @('-Describe')
    Require-Success $result 'stable launcher path resolution'
    $description = $result.Output | ConvertFrom-Json
    Assert-True ($description.Version -eq '0.6.0-test.1' -and $description.Backend.StartsWith($root)) "Launcher backend not installed release: expected $root ; actual $($description | ConvertTo-Json -Compress)"
    $result = Run-Script $launcher @('-Health','-Json')
    Require-Success $result 'launcher health forwarding'
    $package2 = Join-Path $work 'update package'
    Copy-Item -LiteralPath $package -Destination $package2 -Recurse
    Seal-Fixture $package2 '0.6.0-test.2'
    $update = Join-Path $root 'Update-VideoAI.ps1'
    $result = Run-Script $update @('-PackageRoot',$package2,'-WhatIf')
    Require-Success $result 'update WhatIf'
    Assert-True ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -eq $before) 'Update WhatIf activated release'
    $lock = [IO.File]::Open((Join-Path $root '.install.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $result = Run-Script $update @('-PackageRoot',$package2)
        Assert-True ($result.Code -ne 0) 'Concurrent installation did not fail'
    }
    finally { $lock.Dispose() }
    Assert-True ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -eq $before) 'Lock failure changed active release'
    $result = Run-Script $update @('-PackageRoot',$package2)
    Require-Success $result 'verified update activation'
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    Assert-True ($receipt.Releases.Count -eq 2 -and $receipt.Version -eq '0.6.0-test.2') 'Previous release not retained'
    $previousManifest = Join-Path (Join-Path $root $receipt.Releases[0].Path) 'package-manifest.json'
    $savedManifest = [IO.File]::ReadAllBytes($previousManifest)
    try {
        [IO.File]::AppendAllText($previousManifest, ' ', $utf8)
        $result = Run-Script (Join-Path $root 'Uninstall-VideoAI.ps1')
        Assert-True ($result.Code -ne 0 -and (Test-Path -LiteralPath (Join-Path (Join-Path $root $receipt.ActiveRelease) 'src/Convert-VideoForAI.ps1'))) 'Uninstall mutated application before validating every manifest'
    }
    finally { [IO.File]::WriteAllBytes($previousManifest,$savedManifest) }
    Write-Host 'PASS: changed retained manifest refuses uninstall before deletion'

    $before = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    [IO.File]::AppendAllText((Join-Path $package2 'README.md'), 'tamper', $utf8)
    $result = Run-Script $update @('-PackageRoot',$package2)
    Assert-True ($result.Code -ne 0 -and $result.Error -match 'integrity') 'Tampered update accepted'
    Assert-True ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -eq $before) 'Bad update replaced active receipt'
    Write-FixtureHealth (Join-Path $package2 'src/Test-VideoAIHealth.ps1') -MissingNvidia
    Seal-Fixture $package2 '0.6.0-test.3'
    $result = Run-Script $update @('-PackageRoot',$package2)
    Assert-True ($result.Code -ne 0 -and $result.Error -match 'requires NVIDIA/CUDA') 'CPU-only preflight did not explain requirement'
    Assert-True ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -eq $before) 'Failed preflight changed active release'
    $missingRoot = Join-Path $work 'must not exist'
    $result = Run-Script (Join-Path $package2 'Install-VideoAI.ps1') @('-InstallRoot',$missingRoot)
    Assert-True ($result.Code -ne 0 -and -not (Test-Path -LiteralPath $missingRoot)) 'Failed first preflight wrote install root'
    $result = Run-Script (Join-Path $package2 'Install-VideoAI.ps1') @('-InstallRoot',$missingRoot,'-PrepareRuntime')
    Assert-True ($result.Code -ne 0 -and $result.Error -match 'requires NVIDIA/CUDA') 'Runtime preparation bypassed NVIDIA preflight'
    Write-Host 'PASS: integrity, concurrency and CPU-only failure preserve active installation'
    $manifestPath = Join-Path $package2 'package-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.Files[0].Path = '../outside.ps1'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), $utf8)
    $result = Run-Script $update @('-PackageRoot',$package2)
    Assert-True ($result.Code -ne 0 -and $result.Error -match 'Unsafe package path') 'Manifest traversal accepted'
    $relocated = Join-Path $work 'relocated install'
    [IO.Directory]::Move($root,$relocated)
    $root = $relocated
    $result = Run-Script (Join-Path $root 'Start-VideoAI.ps1') @('-Describe')
    Require-Success $result 'relocated installation launcher'
    Assert-True (($result.Output | ConvertFrom-Json).Backend.StartsWith($root)) 'Relocated backend points to old path'
    $receiptPath = Join-Path $root 'installation.json'
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $active = Join-Path $root $receipt.ActiveRelease
    $modified = Join-Path $active 'README.md'
    [IO.File]::WriteAllText($modified,'local edits',$utf8)
    $personal = Join-Path $root 'personal-video.txt'
    [IO.File]::WriteAllText($personal,'personal data',$utf8)
    $uninstall = Join-Path $root 'Uninstall-VideoAI.ps1'
    $result = Run-Script $uninstall @('-WhatIf')
    Require-Success $result 'uninstall WhatIf'
    Assert-True (Test-Path -LiteralPath $receiptPath) 'Uninstall WhatIf removed receipt'
    $result = Run-Script $uninstall
    Require-Success $result 'managed uninstall'
    Assert-True (-not (Test-Path -LiteralPath $receiptPath)) 'Receipt survived uninstall'
    Assert-True ((Get-Content -LiteralPath $modified -Raw) -eq 'local edits') 'Modified payload deleted'
    Assert-True ((Get-Content -LiteralPath $personal -Raw) -eq 'personal data') 'Unrecorded user data deleted'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $active 'src/Convert-VideoForAI.ps1'))) 'Owned payload not removed'
    Write-Host 'PASS: uninstall preserves modified and unrecorded files'
}
finally {
    $safe = [IO.Path]::GetFullPath($work)
    if (-not ($safe.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $safe -Leaf) -like 'VideoAI-lifecycle-*')) { throw 'Unsafe test cleanup' }
    Remove-Item -LiteralPath $safe -Recurse -Force
}
Write-Host 'PASS: offline installation lifecycle regression'
