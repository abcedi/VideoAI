# Shared by the fixed entry points and by relocatable packages.
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
function Resolve-VideoAIPackageRoot {
    param([Parameter(Mandatory)][string]$Root)
    $Root = [IO.Path]::GetFullPath($Root)
    $cursor = $Root
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not supported in application paths: $cursor"
            }
        }
        $cursor = Split-Path $cursor -Parent
    }
    $manifestPath = Join-Path $Root 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $receipt = Get-Content -LiteralPath (Join-Path $Root 'installation.json') -Raw | ConvertFrom-Json
        if ($receipt.Schema -ne 'videoai-install/v1' -or $receipt.ActiveRelease -notmatch '^releases/[a-zA-Z0-9.-]+$') {
            throw 'Invalid VideoAI installation receipt.'
        }
        $Root = Join-Path $Root $receipt.ActiveRelease
        $manifestPath = Join-Path $Root 'package-manifest.json'
        if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $receipt.ManifestSHA256) {
            throw 'Installed package manifest has changed.'
        }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $moduleEntry = @($manifest.Files | Where-Object Path -eq 'VideoAI.Installation.psm1')
    if ($moduleEntry.Count -ne 1 -or
        (Get-FileHash -LiteralPath (Join-Path $Root 'VideoAI.Installation.psm1') -Algorithm SHA256).Hash -ne $moduleEntry[0].SHA256) {
        throw 'Installation module integrity check failed.'
    }
    # Check the selected release and module too before loading executable code.
    foreach ($candidate in @($Root, (Join-Path $Root 'VideoAI.Installation.psm1'))) {
        $cursor = $candidate
        while ($cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point in selected release: $cursor"
            }
            $cursor = Split-Path $cursor -Parent
        }
    }
    return $Root
}
