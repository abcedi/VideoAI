[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Video,

    [string]$OutputRoot = "$HOME\Videos\AI-Video-Analysis\Jobs",

    # Use "auto" to let Whisper detect spoken language.
    [string]$Language = "en",

    [string]$SourceUrl,

    [string]$JobLabel,

    [string]$Transcript
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "`n===== Convert-VideoForAI v0.4.2 ====="

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "uv is not installed or not in PATH."
}

$Driver = Join-Path $PSScriptRoot "convert_video_for_ai.py"

if (-not (Test-Path -LiteralPath $Driver -PathType Leaf)) {
    throw "Python driver missing: $Driver"
}

$ResolvedVideo = (Resolve-Path -LiteralPath $Video -ErrorAction Stop).Path

$ResolvedTranscript = $null

if ($Transcript) {
    $ResolvedTranscript = (
        Resolve-Path -LiteralPath $Transcript -ErrorAction Stop
    ).Path

    if ([IO.Path]::GetExtension($ResolvedTranscript).ToLowerInvariant() -ne ".srt") {
        throw "Explicit transcript must currently be an SRT file: $ResolvedTranscript"
    }
}

$ArgsList = @(
    "run",
    "--no-project",
    "--with",
    "analysis-video[cuda]==0.1.1",
    $Driver,
    "--video",
    $ResolvedVideo,
    "--output-root",
    $OutputRoot
)

if ($Language -and $Language.ToLowerInvariant() -ne "auto") {
    $ArgsList += @("--language", $Language)
}

if ($SourceUrl) {
    $ArgsList += @("--source-url", $SourceUrl)
}

if ($JobLabel) {
    $ArgsList += @("--job-label", $JobLabel)
}

if ($ResolvedTranscript) {
    $ArgsList += @("--transcript", $ResolvedTranscript)
}

Write-Host "Video:      $ResolvedVideo"
Write-Host "OutputRoot: $OutputRoot"
Write-Host "Language:   $Language"
Write-Host "Evidence:   video-ai-evidence/v4"
Write-Host "CUDA PATH:  process-local only"
Write-Host "JobLabel:   $JobLabel"
Write-Host "Transcript: $ResolvedTranscript"
Write-Host "Source:     never intentionally modified"

# Match GUI execution for Unicode diagnostics even when invoked directly.
$PreviousPythonUtf8 = $env:PYTHONUTF8
$PreviousPythonEncoding = $env:PYTHONIOENCODING
try {
    $env:PYTHONUTF8 = "1"
    $env:PYTHONIOENCODING = "utf-8"
    & uv @ArgsList
}
finally {
    $env:PYTHONUTF8 = $PreviousPythonUtf8
    $env:PYTHONIOENCODING = $PreviousPythonEncoding
}

$Code = $LASTEXITCODE

if ($Code -ne 0) {
    throw "Convert-VideoForAI failed with exit code $Code."
}
