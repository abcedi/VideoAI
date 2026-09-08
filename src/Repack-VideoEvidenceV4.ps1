[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$AnalysisDir,

    [string]$Transcript,
    [string]$SourceVideo,
    [string]$SourceUrl,
    [string]$JobLabel,

    [string]$OutputRoot = "$HOME\Videos\AI-Video-Analysis\Repacked-VideoEvidence-v4"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "`n===== Repack-VideoEvidenceV4 v0.4.2 ====="

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "uv is not installed or not in PATH."
}

$Driver = Join-Path $PSScriptRoot "convert_video_for_ai.py"

if (-not (Test-Path -LiteralPath $Driver -PathType Leaf)) {
    throw "VideoAI Python driver missing: $Driver"
}

$ResolvedAnalysis = (
    Resolve-Path -LiteralPath $AnalysisDir -ErrorAction Stop
).Path

$ArgsList = @(
    "run",
    "--no-project",
    "--with",
    "analysis-video==0.1.1",
    $Driver,
    "--repack-analysis",
    $ResolvedAnalysis,
    "--output-root",
    $OutputRoot
)

$ResolvedTranscript = $null
$ResolvedSourceVideo = $null

if ($Transcript) {
    $ResolvedTranscript = (
        Resolve-Path -LiteralPath $Transcript -ErrorAction Stop
    ).Path
    $ArgsList += @("--transcript", $ResolvedTranscript)
}

if ($SourceVideo) {
    $ResolvedSourceVideo = (
        Resolve-Path -LiteralPath $SourceVideo -ErrorAction Stop
    ).Path
    $ArgsList += @("--source-video", $ResolvedSourceVideo)
}

if ($SourceUrl) {
    $ArgsList += @("--source-url", $SourceUrl)
}

if ($JobLabel) {
    $ArgsList += @("--job-label", $JobLabel)
}

Write-Host "Analysis:   $ResolvedAnalysis"
Write-Host "OutputRoot: $OutputRoot"
Write-Host "Evidence:   video-ai-evidence/v4"
Write-Host "Tool:       VideoAI v0.4.2"
Write-Host "Mode:       REPACK ONLY - no split/transcribe/frames rerun"
Write-Host "Transcript: $ResolvedTranscript"
Write-Host "Source:     $ResolvedSourceVideo"
Write-Host "Source URL: $SourceUrl"
Write-Host "Job label:  $JobLabel"

& uv @ArgsList

if ($LASTEXITCODE -ne 0) {
    throw "Repack-VideoEvidenceV4 failed with exit code $LASTEXITCODE."
}
