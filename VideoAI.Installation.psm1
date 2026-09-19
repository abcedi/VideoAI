Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VideoAISafePath {
    param([string]$Root, [string]$Relative)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($Relative -notmatch '^[A-Za-z0-9._/-]+$' -or $Relative -match '(^|/)\.\.?(/|$)' -or
        [IO.Path]::IsPathRooted($Relative)) { throw "Unsafe package path: $Relative" }
    $full = [IO.Path]::GetFullPath((Join-Path $rootFull $Relative))
    if (-not $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes application directory: $Relative"
    }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not supported: $cursor"
            }
        }
        $cursor = Split-Path $cursor -Parent
    }
    return $full
}

function Get-VideoAIPackage {
    param([Parameter(Mandatory)][string]$PackageRoot)
    $manifestPath = Get-VideoAISafePath $PackageRoot 'package-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.Schema -ne 'videoai-package/v1' -or $manifest.Version -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$') {
        throw 'Unsupported package manifest.'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $manifest.Files) {
        if (-not $seen.Add($file.Path) -or $file.SHA256 -notmatch '^[A-F0-9]{64}$') { throw 'Duplicate path or invalid package hash.' }
        $path = Get-VideoAISafePath $PackageRoot $file.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) {
            throw "Package integrity check failed: $($file.Path)"
        }
    }
    foreach ($required in @('Start-VideoAI.ps1','Install-VideoAI.ps1','Update-VideoAI.ps1','Uninstall-VideoAI.ps1',
        'VideoAI.Bootstrap.ps1','VideoAI.Installation.psm1','src/Test-VideoAIHealth.ps1',
        'src/Convert-VideoForAI.ps1','src/convert_video_for_ai.py','gui/VideoAI-GUI.ps1',
        'src/Download-TikTokForVideoAI.ps1','src/download_tiktok_for_videoai.py',
        'src/Download-YouTubeForVideoAI.ps1','src/Repack-VideoEvidenceV4.ps1','LICENSE','THIRD_PARTY_NOTICES.md')) {
        if (-not $seen.Contains($required)) { throw "Package missing required entry: $required" }
    }
    return [PSCustomObject]@{
        Root = [IO.Path]::GetFullPath($PackageRoot)
        Manifest = $manifest
        Hash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    }
}

function Read-VideoAIReceipt {
    param([string]$InstallRoot)
    $path = Get-VideoAISafePath $InstallRoot 'installation.json'
    $receipt = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($receipt.Schema -ne 'videoai-install/v1' -or $receipt.ActiveRelease -notmatch '^releases/[a-zA-Z0-9.-]+$' -or
        $receipt.ManifestSHA256 -notmatch '^[A-F0-9]{64}$') { throw 'Not a managed VideoAI installation.' }
    $active = @($receipt.Releases | Where-Object Path -eq $receipt.ActiveRelease)
    if ($active.Count -ne 1 -or $active[0].SHA256 -ne $receipt.ManifestSHA256) { throw 'Invalid active release record.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($release in $receipt.Releases) {
        if ($release.Path -notmatch '^releases/[a-zA-Z0-9.-]+$' -or -not $seen.Add($release.Path) -or $release.SHA256 -notmatch '^[A-F0-9]{64}$') {
            throw 'Invalid release record.'
        }
        $null = Get-VideoAISafePath $InstallRoot $release.Path
    }
    $controlNames = @('Start-VideoAI.ps1','Update-VideoAI.ps1','Uninstall-VideoAI.ps1','VideoAI.Bootstrap.ps1')
    if (@($receipt.Controls).Count -ne $controlNames.Count) { throw 'Invalid entry point records.' }
    $seen.Clear()
    foreach ($control in $receipt.Controls) {
        if ($control.Path -notin $controlNames -or -not $seen.Add($control.Path) -or $control.SHA256 -notmatch '^[A-F0-9]{64}$') {
            throw 'Invalid entry point record.'
        }
    }
    return $receipt
}

function Invoke-VideoAIHealth {
    param([string]$PackageRoot, [switch]$AllowMissingRuntime)
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    $output = & $pwsh -NoLogo -NoProfile -File (Join-Path $PackageRoot 'src/Test-VideoAIHealth.ps1') -Json
    $code = $LASTEXITCODE
    try {
        $report = ($output -join [char]10) | ConvertFrom-Json
        if ($report.Schema -ne 'videoai-health/v1' -or $report.Checks.Count -ne 11 -or
            @($report.Checks | Where-Object Required).Count -ne 9) { throw 'Unexpected health contract.' }
        $missing = @($report.Checks | Where-Object { $_.Required -and $_.Status -eq 'MISSING' })
        if ($code -eq 0 -and $missing.Count -gt 0) { throw 'Inconsistent health success.' }
    }
    catch { throw "Health checker returned an invalid report: $($_.Exception.Message)" }
    if ($code -ne 0) {
        if ($code -eq 1) {
            if ($AllowMissingRuntime -and $missing.Count -eq 1 -and $missing[0].Name -eq 'VideoAI CUDA Runtime') { return $report }
            $details = @($missing | ForEach-Object { "$($_.Name): $($_.Detail)" })
            throw ("VideoAI is not ready. The current release requires NVIDIA/CUDA. Missing requirements:" + [char]10 + ($details -join [char]10))
        }
        throw "Health checker failed with exit $code."
    }
    return $report
}

function Install-VideoAIPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$InstallRoot,
        [switch]$Update,
        [switch]$PrepareRuntime
    )
    $package = Get-VideoAIPackage $PackageRoot
    $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/')
    if ([string]::IsNullOrWhiteSpace($root) -or $root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\','/') -or
        $root -eq [IO.Path]::GetFullPath($HOME).TrimEnd('\','/') -or
        $package.Root.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $package.Root -eq $root) { throw 'Choose a dedicated installation directory outside the package.' }
    $receiptPath = Get-VideoAISafePath $root 'installation.json'
    $receipt = $null
    if (Test-Path -LiteralPath $receiptPath) { $receipt = Read-VideoAIReceipt $root }
    elseif (Test-Path -LiteralPath $root) {
        if (@(Get-ChildItem -LiteralPath $root -Force).Count -gt 0) { throw 'Refusing to use a nonempty unmanaged directory.' }
    }
    if ($Update -and -not $receipt) { throw 'Update requires an existing managed installation.' }
    if (-not $PSCmdlet.ShouldProcess($root, "Install verified VideoAI $($package.Manifest.Version)")) { return }
    if ($PrepareRuntime) {
        $null = Invoke-VideoAIHealth $package.Root -AllowMissingRuntime
        $uv = Get-Command uv -CommandType Application -ErrorAction Stop | Select-Object -First 1
        # Explicit opt-in is the only online installation operation. No model download.
        & $uv.Source run --no-project --with 'analysis-video[cuda]==0.1.1' python -c 'import faster_whisper, ctranslate2'
        if ($LASTEXITCODE -ne 0) { throw 'Runtime preparation failed; application activation was not changed.' }
    }
    $null = Invoke-VideoAIHealth $package.Root
    $finalRoot = $root
    $fresh = -not $receipt
    $lock = $null
    if ($fresh) {
        # Construct first installs in a sibling directory; never expose half an install.
        $root = Get-VideoAISafePath (Split-Path $finalRoot -Parent) ('.VideoAI-install-' + [guid]::NewGuid().ToString('N'))
        $receiptPath = Join-Path $root 'installation.json'
        $null = New-Item -ItemType Directory -Force -Path $root
    }
    else {
        $lockPath = Get-VideoAISafePath $root '.install.lock'
        $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    $stage = $null
    try {
        # Re-read after obtaining the lock; another process may have updated meanwhile.
        if (Test-Path -LiteralPath $receiptPath) { $receipt = Read-VideoAIReceipt $root }
        $releaseName = $package.Manifest.Version + '-' + $package.Hash.Substring(0,16)
        $releaseRelative = 'releases/' + $releaseName
        $releasePath = Get-VideoAISafePath $root $releaseRelative
        if ($receipt) {
            foreach ($control in $receipt.Controls) {
                $path = Get-VideoAISafePath $root $control.Path
                if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $control.SHA256) {
                    throw "Entry point was modified: $($control.Path)"
                }
            }
        }
        if (Test-Path -LiteralPath $releasePath) {
            $existing = Get-VideoAIPackage $releasePath
            if ($existing.Hash -ne $package.Hash) { throw 'Release directory collision.' }
        }
        else {
            $stage = Get-VideoAISafePath $root ('releases/.stage-' + [guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Force -Path $stage
            foreach ($file in $package.Manifest.Files) {
                $destination = Get-VideoAISafePath $stage $file.Path
                $null = New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent)
                [IO.File]::Copy((Join-Path $package.Root $file.Path), $destination, $false)
            }
            [IO.File]::Copy((Join-Path $package.Root 'package-manifest.json'), (Join-Path $stage 'package-manifest.json'), $false)
            $staged = Get-VideoAIPackage $stage
            if ($staged.Hash -ne $package.Hash) { throw 'Staged package changed.' }
            [IO.Directory]::Move($stage, $releasePath)
            $stage = $null
        }
        $controls = @()
        if ($receipt) { $controls = @($receipt.Controls) }
        else {
            foreach ($name in @('Start-VideoAI.ps1','Update-VideoAI.ps1','Uninstall-VideoAI.ps1','VideoAI.Bootstrap.ps1')) {
                $target = Get-VideoAISafePath $root $name
                if (Test-Path -LiteralPath $target) { throw "Entry point already exists: $name" }
                [IO.File]::Copy((Join-Path $releasePath $name), $target, $false)
                $controls += [PSCustomObject]@{ Path=$name; SHA256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash }
            }
        }
        $releases = @()
        if ($receipt) { $releases = @($receipt.Releases | Where-Object Path -ne $releaseRelative) }
        $releases += [PSCustomObject]@{ Path=$releaseRelative; SHA256=$package.Hash }
        $state = [ordered]@{
            Schema='videoai-install/v1'; Version=$package.Manifest.Version
            ActiveRelease=$releaseRelative; ManifestSHA256=$package.Hash
            Releases=$releases; Controls=$controls
        }
        $pending = Get-VideoAISafePath $root ('receipt-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($pending, ($state | ConvertTo-Json -Depth 8) + [char]10, [Text.UTF8Encoding]::new($false))
        try {
            # Same-volume atomic replacement leaves the previous active receipt intact on failure.
            if (Test-Path -LiteralPath $receiptPath) {
                $backup = Get-VideoAISafePath $root ('receipt-backup-' + [guid]::NewGuid().ToString('N') + '.tmp')
                try { [IO.File]::Replace($pending, $receiptPath, $backup) }
                finally { if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force } }
            }
            else { [IO.File]::Move($pending, $receiptPath) }
        }
        finally { if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force } }
        if ($fresh) {
            if (Test-Path -LiteralPath $finalRoot) {
                # Delete only an empty destination; a concurrent change makes this fail safely.
                [IO.Directory]::Delete($finalRoot, $false)
            }
            [IO.Directory]::Move($root, $finalRoot)
        }
        [PSCustomObject]@{ Status='Installed'; Version=$state.Version; InstallRoot=$finalRoot; ActiveRelease=$releaseRelative }
    }
    finally {
        if ($stage -and (Test-Path -LiteralPath $stage)) {
            $safeStage = Get-VideoAISafePath $root ('releases/' + (Split-Path $stage -Leaf))
            if ((Split-Path $safeStage -Leaf) -notlike '.stage-*') { throw 'Unsafe stage cleanup.' }
            Remove-Item -LiteralPath $safeStage -Recurse -Force
        }
        if ($lock) { $lock.Dispose() }
        if ($fresh -and (Test-Path -LiteralPath $root)) {
            $safeRoot = Get-VideoAISafePath (Split-Path $finalRoot -Parent) (Split-Path $root -Leaf)
            if ((Split-Path $safeRoot -Leaf) -notlike '.VideoAI-install-*') { throw 'Unsafe install cleanup.' }
            Remove-Item -LiteralPath $safeRoot -Recurse -Force
        }
        # Updates retain the lock file. Initial construction uses a private sibling.
    }
}

function Uninstall-VideoAIPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$InstallRoot)
    $root = [IO.Path]::GetFullPath($InstallRoot)
    $receipt = Read-VideoAIReceipt $root
    if (-not $PSCmdlet.ShouldProcess($root, 'Remove recorded VideoAI application files; preserve modified and unrecorded files')) { return }
    $lockPath = Get-VideoAISafePath $root '.install.lock'
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $preserved = [Collections.Generic.List[string]]::new()
    try {
        $receipt = Read-VideoAIReceipt $root
        $delete = [Collections.Generic.List[string]]::new()
        $directories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        # Validate every manifest/path before deleting anything. Never recursively delete an install root.
        foreach ($release in $receipt.Releases) {
            $releaseRoot = Get-VideoAISafePath $root $release.Path
            $manifestPath = Get-VideoAISafePath $releaseRoot 'package-manifest.json'
            if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $release.SHA256) {
                throw 'Release manifest changed; refusing uninstall.'
            }
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            foreach ($file in $manifest.Files) {
                $path = Get-VideoAISafePath $releaseRoot $file.Path
                if (Test-Path -LiteralPath $path) {
                    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $file.SHA256) { $delete.Add($path) }
                    else { $preserved.Add($path) }
                }
                $parent = Split-Path $path -Parent
                while ($parent.StartsWith($releaseRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    $null = $directories.Add($parent)
                    $parent = Split-Path $parent -Parent
                }
            }
            $delete.Add($manifestPath)
            $null = $directories.Add($releaseRoot)
        }
        foreach ($control in $receipt.Controls) {
            $path = Get-VideoAISafePath $root $control.Path
            if (Test-Path -LiteralPath $path) {
                if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $control.SHA256) { $delete.Add($path) }
                else { $preserved.Add($path) }
            }
        }
        foreach ($path in $delete) { Remove-Item -LiteralPath $path -Force }
        Remove-Item -LiteralPath (Get-VideoAISafePath $root 'installation.json') -Force
        $null = $directories.Add((Get-VideoAISafePath $root 'releases'))
        foreach ($directory in @($directories | Sort-Object Length -Descending)) {
            if ((Test-Path -LiteralPath $directory) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
                Remove-Item -LiteralPath $directory -Force
            }
        }
    }
    finally { $lock.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force
    if (@(Get-ChildItem -LiteralPath $root -Force).Count -eq 0) { [IO.Directory]::Delete($root, $false) }
    [PSCustomObject]@{ Status='Uninstalled'; InstallRoot=$root; PreservedModifiedFiles=@($preserved) }
}

function Invoke-VideoAILaunch {
    param([string]$PackageRoot, [switch]$Describe, [switch]$Health, [switch]$Json)
    $package = Get-VideoAIPackage $PackageRoot
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    $gui = Join-Path $package.Root 'gui/VideoAI-GUI.ps1'
    $backend = Join-Path $package.Root 'src/Convert-VideoForAI.ps1'
    if ($Describe) {
        [PSCustomObject]@{ Version=$package.Manifest.Version; PackageRoot=$package.Root; PowerShell=$pwsh; GUI=$gui; Backend=$backend } | ConvertTo-Json
        return
    }
    if ($Health) {
        $arguments = @('-NoLogo','-NoProfile','-File',(Join-Path $package.Root 'src/Test-VideoAIHealth.ps1'))
        if ($Json) { $arguments += '-Json' }
        & $pwsh @arguments
        $global:LASTEXITCODE = $LASTEXITCODE
        return
    }
    $null = Invoke-VideoAIHealth $package.Root
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $pwsh
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    foreach ($argument in @('-NoLogo','-NoProfile','-STA','-File',$gui,'-BackendPath',$backend)) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $process.Dispose()
}

Export-ModuleMember -Function Get-VideoAIPackage,Install-VideoAIPackage,Uninstall-VideoAIPackage,Invoke-VideoAILaunch
