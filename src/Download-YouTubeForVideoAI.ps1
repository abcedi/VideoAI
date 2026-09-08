[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url,

    [string]$OutputRoot = "$HOME\Videos\AI-Video-Analysis\Acquisitions",

    [ValidateSet("720","1080")]
    [string]$MaxHeight = "1080"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "`n===== VideoAI YouTube Acquisition v0.2.1 ====="

# ------------------------------------------------------------
# URL validation
# ------------------------------------------------------------

try {
    $Uri = [Uri]$Url
}
catch {
    throw "Invalid URL: $Url"
}

$HostName = $Uri.Host.ToLowerInvariant()

$Allowed = @(
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "youtu.be",
    "music.youtube.com"
)

if ($HostName -notin $Allowed) {
    throw "YouTube URLs only. Host received: $HostName"
}

# ------------------------------------------------------------
# Dependency gate
# ------------------------------------------------------------

foreach ($Command in @("uv","deno","ffmpeg","ffprobe")) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Command"
    }
}

Write-Host "PASS: required commands available."

# ------------------------------------------------------------
# Metadata probe
# ------------------------------------------------------------

Write-Host "`n===== METADATA PROBE ====="

$MetadataJson = & uvx --isolated `
    --from "yt-dlp[default]" `
    yt-dlp `
    --simulate `
    --no-playlist `
    --dump-single-json `
    "$Url"

if ($LASTEXITCODE -ne 0) {
    throw "yt-dlp metadata probe failed."
}

try {
    $Metadata = $MetadataJson | ConvertFrom-Json
}
catch {
    throw "Could not parse yt-dlp metadata."
}

if (-not $Metadata.id) {
    throw "Metadata did not contain a YouTube video ID."
}

$VideoId   = [string]$Metadata.id
$Title     = [string]$Metadata.title
$Channel   = [string]$Metadata.channel
$UploaderId = [string]$Metadata.uploader_id

Write-Host "ID:          $VideoId"
Write-Host "Title:       $Title"
Write-Host "Channel:     $Channel"
Write-Host "Uploader ID: $UploaderId"

# ------------------------------------------------------------
# Choose caption source
#
# Priority:
#   1. manually supplied English captions
#   2. original English automatic captions
#   3. other English automatic captions
#   4. none -> VideoAI will use Whisper
# ------------------------------------------------------------

$CaptionKind = "none"
$CaptionLang = $null

$ManualLanguages = @()

if ($Metadata.subtitles) {
    $ManualLanguages = @(
        $Metadata.subtitles.PSObject.Properties |
            ForEach-Object { $_.Name }
    )
}

$AutoLanguages = @()

if ($Metadata.automatic_captions) {
    $AutoLanguages = @(
        $Metadata.automatic_captions.PSObject.Properties |
            ForEach-Object { $_.Name }
    )
}

foreach ($Candidate in @("en","en-US","en-GB")) {
    if ($Candidate -in $ManualLanguages) {
        $CaptionKind = "manual"
        $CaptionLang = $Candidate
        break
    }
}

if (
    $CaptionKind -eq "none" -and
    $ManualLanguages.Count -gt 0
) {
    $EnglishManual = @(
        $ManualLanguages |
        Where-Object { $_ -match '^en(?:-|$)' } |
        Select-Object -First 1
    )

    if ($EnglishManual.Count -gt 0) {
        $CaptionKind = "manual"
        $CaptionLang = $EnglishManual[0]
    }
}

if ($CaptionKind -eq "none") {
    foreach ($Candidate in @("en-orig","en","en-US","en-GB")) {
        if ($Candidate -in $AutoLanguages) {
            $CaptionKind = "automatic"
            $CaptionLang = $Candidate
            break
        }
    }
}

if (
    $CaptionKind -eq "none" -and
    $AutoLanguages.Count -gt 0
) {
    $EnglishAuto = @(
        $AutoLanguages |
        Where-Object { $_ -match '^en(?:-|$)' } |
        Select-Object -First 1
    )

    if ($EnglishAuto.Count -gt 0) {
        $CaptionKind = "automatic"
        $CaptionLang = $EnglishAuto[0]
    }
}

Write-Host "`n===== CAPTION POLICY ====="
Write-Host "Caption kind:     $CaptionKind"
Write-Host "Caption language: $CaptionLang"

# ------------------------------------------------------------
# Fresh acquisition directory
# ------------------------------------------------------------

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$AcquisitionDir = Join-Path $OutputRoot "${VideoId}__${Stamp}"

if (Test-Path -LiteralPath $AcquisitionDir) {
    throw "Acquisition directory already exists: $AcquisitionDir"
}

New-Item -ItemType Directory -Path $AcquisitionDir -Force |
    Out-Null

Write-Host "`nAcquisition directory:"
Write-Host $AcquisitionDir

# ------------------------------------------------------------
# Download media
#
# Preference:
#   H.264 + AAC/M4A <= requested height
#   H.264 + best audio
#   best video <= height + best audio
#   combined fallback
# ------------------------------------------------------------

Write-Host "`n===== DOWNLOAD VIDEO ====="

$Format = (
    "bv*[height<=$MaxHeight][vcodec^=avc1]+ba[ext=m4a]" +
    "/bv*[height<=$MaxHeight][vcodec^=avc1]+ba" +
    "/bv*[height<=$MaxHeight]+ba" +
    "/b[height<=$MaxHeight]"
)

& uvx --isolated `
    --from "yt-dlp[default]" `
    yt-dlp `
    --no-playlist `
    --windows-filenames `
    --trim-filenames 180 `
    --write-info-json `
    --merge-output-format mp4 `
    -f $Format `
    -P "$AcquisitionDir" `
    -o "%(channel)s - %(title)s [%(id)s].%(ext)s" `
    "$Url"

if ($LASTEXITCODE -ne 0) {
    throw "YouTube media download failed."
}

$Videos = @(
    Get-ChildItem -LiteralPath $AcquisitionDir -File |
    Where-Object {
        $_.Extension -in @(".mp4",".mkv",".webm")
    }
)

if ($Videos.Count -ne 1) {
    throw "Expected exactly one final video; found $($Videos.Count)."
}

$Video = $Videos[0]

# ------------------------------------------------------------
# Caption download
# ------------------------------------------------------------

$CaptionPath = $null

if ($CaptionKind -ne "none") {

    Write-Host "`n===== DOWNLOAD CAPTIONS ====="

    $CaptionArgs = @(
        "--skip-download",
        "--no-playlist",
        "--sub-langs", $CaptionLang,
        "--sub-format", "srt",
        "--windows-filenames",
        "-P", $AcquisitionDir,
        "-o", "%(channel)s - %(title)s [%(id)s].%(ext)s"
    )

    if ($CaptionKind -eq "manual") {
        $CaptionArgs += "--write-subs"
    }
    else {
        $CaptionArgs += "--write-auto-subs"
    }

    $CaptionArgs += $Url

    & uvx --isolated `
        --from "yt-dlp[default]" `
        yt-dlp @CaptionArgs

    if ($LASTEXITCODE -eq 0) {
        $CaptionFiles = @(
            Get-ChildItem `
                -LiteralPath $AcquisitionDir `
                -File `
                -Filter "*.srt"
        )

        if ($CaptionFiles.Count -eq 1) {
            $CaptionPath = $CaptionFiles[0].FullName
            Write-Host "PASS: caption acquired."
        }
        elseif ($CaptionFiles.Count -gt 1) {
            $Chosen = @(
                $CaptionFiles |
                Where-Object {
                    $_.Name -like "*.$CaptionLang.srt"
                } |
                Select-Object -First 1
            )

            if ($Chosen.Count -gt 0) {
                $CaptionPath = $Chosen[0].FullName
                Write-Host "PASS: selected requested caption."
            }
            else {
                Write-Warning "Multiple caption files found; none selected automatically."
                $CaptionKind = "none"
            }
        }
        else {
            Write-Warning "Caption download reported success but no SRT was found."
            $CaptionKind = "none"
        }
    }
    else {
        Write-Warning "Caption acquisition failed; Whisper fallback remains available."
        $CaptionKind = "none"
    }
}

# ------------------------------------------------------------
# Validate media
# ------------------------------------------------------------

Write-Host "`n===== FFPROBE VALIDATION ====="

$ProbeJson = & ffprobe `
    -v error `
    -show_entries `
    "format=duration,size,format_name:stream=index,codec_type,codec_name,width,height,sample_rate,channels" `
    -of json `
    "$($Video.FullName)"

if ($LASTEXITCODE -ne 0) {
    throw "ffprobe validation failed."
}

$Probe = $ProbeJson | ConvertFrom-Json

$VideoStreams = @(
    $Probe.streams |
    Where-Object { $_.codec_type -eq "video" }
)

$AudioStreams = @(
    $Probe.streams |
    Where-Object { $_.codec_type -eq "audio" }
)

if ($VideoStreams.Count -lt 1) {
    throw "Downloaded file has no video stream."
}

if ($AudioStreams.Count -lt 1) {
    throw "Downloaded file has no audio stream."
}

$V = $VideoStreams[0]
$A = $AudioStreams[0]

Write-Host "PASS: video stream present."
Write-Host "PASS: audio stream present."
Write-Host "Video codec: $($V.codec_name)"
Write-Host "Audio codec: $($A.codec_name)"
Write-Host "Resolution:  $($V.width)x$($V.height)"
Write-Host "Duration:    $($Probe.format.duration) seconds"

# ------------------------------------------------------------
# Hash source
# ------------------------------------------------------------

$Hash = (
    Get-FileHash `
        -LiteralPath $Video.FullName `
        -Algorithm SHA256
).Hash

# ------------------------------------------------------------
# Structured acquisition manifest
# ------------------------------------------------------------

$ManifestPath = Join-Path $AcquisitionDir "acquisition.json"

$Manifest = [ordered]@{
    version          = "0.2.1"
    ok               = $true
    platform         = "youtube"

    source = [ordered]@{
        url           = $Url
        video_id      = $VideoId
        title         = $Title
        channel       = $Channel
        uploader_id   = $UploaderId
    }

    media = [ordered]@{
        path          = $Video.FullName
        sha256        = $Hash
        width         = [int]$V.width
        height        = [int]$V.height
        video_codec   = [string]$V.codec_name
        audio_codec   = [string]$A.codec_name
        duration      = [double]$Probe.format.duration
    }

    captions = [ordered]@{
        kind          = $CaptionKind
        language      = $CaptionLang
        path          = $CaptionPath
    }
}

$Manifest |
    ConvertTo-Json -Depth 8 |
    Set-Content `
        -LiteralPath $ManifestPath `
        -Encoding utf8NoBOM

Write-Host "`n===== ACQUISITION COMPLETE ====="
Write-Host "Video:      $($Video.FullName)"
Write-Host "SHA256:     $Hash"
Write-Host "Captions:   $CaptionPath"
Write-Host "Manifest:   $ManifestPath"

[PSCustomObject]@{
    ok               = $true
    platform         = "youtube"
    url              = $Url
    video_id         = $VideoId
    title            = $Title
    channel          = $Channel
    uploader_id      = $UploaderId
    acquisition_dir  = $AcquisitionDir
    video_path       = $Video.FullName
    sha256           = $Hash
    caption_kind     = $CaptionKind
    caption_language = $CaptionLang
    caption_path     = $CaptionPath
    manifest_path    = $ManifestPath
    width            = $V.width
    height           = $V.height
    video_codec      = $V.codec_name
    audio_codec      = $A.codec_name
    duration         = [double]$Probe.format.duration
}