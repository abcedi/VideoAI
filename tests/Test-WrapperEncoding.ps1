[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $temp ('VideoAI-encoding-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$video = Join-Path $work 'fixture.mp4'
[IO.File]::WriteAllBytes($video, [byte[]]@(0))
$previousUtf8 = $env:PYTHONUTF8
$previousEncoding = $env:PYTHONIOENCODING
$global:VideoAIEncodingInvoked = 0
$global:VideoAIEncodingFail = $false
function uv {
    if ($env:PYTHONUTF8 -ne '1' -or $env:PYTHONIOENCODING -ne 'utf-8') { throw 'Wrapper did not select UTF-8' }
    $global:VideoAIEncodingInvoked++
    if ($global:VideoAIEncodingFail) { throw 'fixture uv failure' }
    $global:LASTEXITCODE = 0
}
try {
    $env:PYTHONUTF8 = '0'
    $env:PYTHONIOENCODING = 'cp1252'
    foreach ($name in @('Convert-VideoForAI.ps1','Repack-VideoEvidenceV4.ps1')) {
        $parameters = if ($name.StartsWith('Convert')) { @{Video=$video} } else { @{AnalysisDir=$work} }
        $global:VideoAIEncodingFail = $false
        & (Join-Path $repo "src/$name") @parameters | Out-Null
        if ($env:PYTHONUTF8 -ne '0' -or $env:PYTHONIOENCODING -ne 'cp1252') { throw 'Wrapper changed caller environment' }
        $global:VideoAIEncodingFail = $true
        $caught = $false
        try { & (Join-Path $repo "src/$name") @parameters | Out-Null }
        catch { $caught = $_.Exception.Message -eq 'fixture uv failure' }
        if (-not $caught -or $env:PYTHONUTF8 -ne '0' -or $env:PYTHONIOENCODING -ne 'cp1252') { throw 'Failure did not restore caller environment' }
    }
    if ($global:VideoAIEncodingInvoked -ne 4) { throw 'Did not exercise both native invocation paths' }
    Write-Host 'PASS: conversion/repack UTF-8 and caller-environment restoration on success/failure'
}
finally {
    $env:PYTHONUTF8 = $previousUtf8
    $env:PYTHONIOENCODING = $previousEncoding
    $safe = [IO.Path]::GetFullPath($work)
    if (-not ($safe.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $safe -Leaf) -like 'VideoAI-encoding-*')) { throw 'Unsafe encoding cleanup' }
    Remove-Item -LiteralPath $safe -Recurse -Force
}
