[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$')]
    [string]$Version = '0.6.0-preview.1',
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.artifacts'),
    [switch]$SkipSetup
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repository = Split-Path $PSScriptRoot -Parent
$output = [IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Force -Path $output
$name = 'VideoAI-' + $Version
$package = Join-Path $output $name
$zipPath = Join-Path $output ($name + '.zip')
$exePath = Join-Path $output ($name + '-Setup.exe')
foreach ($destination in @($package, $zipPath, $exePath)) {
    if (Test-Path -LiteralPath $destination) { throw "Build output already exists; choose a new output directory: $destination" }
}
$files = @(
    'Install-VideoAI.ps1','Update-VideoAI.ps1','Uninstall-VideoAI.ps1','Start-VideoAI.ps1',
    'VideoAI.Bootstrap.ps1','VideoAI.Installation.psm1',
    'LICENSE','THIRD_PARTY_NOTICES.md','README.md',
    'docs/INSTALLATION.md','docs/HEALTH_CHECKER.md','docs/DISTRIBUTION.md','docs/USAGE.md',
    'src/Convert-VideoForAI.ps1','src/convert_video_for_ai.py','src/Repack-VideoEvidenceV4.ps1',
    'src/Download-YouTubeForVideoAI.ps1','src/Download-TikTokForVideoAI.ps1',
    'src/download_tiktok_for_videoai.py','src/Test-VideoAIHealth.ps1','gui/VideoAI-GUI.ps1'
)
$null = New-Item -ItemType Directory -Path $package
$records = @()
foreach ($relative in ($files | Sort-Object -CaseSensitive)) {
    $source = Join-Path $repository $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing build input: $relative" }
    $destination = Join-Path $package $relative
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent)
    [IO.File]::Copy($source, $destination, $false)
    if ($relative -match '\.(ps1|psm1|py|md)$') {
        if ([IO.File]::ReadAllBytes($destination) -contains 13) { throw "Noncanonical line endings: $relative" }
    }
    $records += [ordered]@{ Path=$relative; SHA256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash }
}
$manifest = [ordered]@{ Schema='videoai-package/v1'; Version=$Version; Files=$records }
[IO.File]::WriteAllText((Join-Path $package 'package-manifest.json'), ($manifest | ConvertTo-Json -Depth 6).Replace(([string][char]13 + [char]10), [string][char]10) + [char]10, [Text.UTF8Encoding]::new($false))
Import-Module (Join-Path $repository 'VideoAI.Installation.psm1') -Force
$null = Get-VideoAIPackage $package
# Fixed entry order and timestamps; package manifest has no clock or local paths.
$archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relative in (@($files) + 'package-manifest.json' | Sort-Object -CaseSensitive)) {
        $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
        $stream = $entry.Open()
        try {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $package $relative))
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally { $stream.Dispose() }
    }
}
finally { $archive.Dispose() }
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$sums = @("$zipHash  $name.zip")
if (-not $SkipSetup) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { throw 'Setup build requires the Windows .NET Framework 4 C# compiler.' }
    $generated = Join-Path $output ($name + '-Setup.cs')
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Setup.cs'))
    [IO.File]::WriteAllText($generated, $template.Replace('__PAYLOAD_SHA256__', $zipHash), [Text.UTF8Encoding]::new($false))
    & $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$exePath" /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:System.Windows.Forms.dll "/resource:$zipPath,VideoAI.Package.zip" $generated
    if ($LASTEXITCODE -ne 0) { throw 'Setup compilation failed.' }
    Remove-Item -LiteralPath $generated
    $sums += ((Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash + "  $name-Setup.exe")
}
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'), ($sums -join [char]10) + [char]10, [Text.UTF8Encoding]::new($false))
[PSCustomObject]@{ Version=$Version; Package=$package; ZIP=$zipPath; Setup=$(if ($SkipSetup) { $null } else { $exePath }); SHA256=$zipHash }
