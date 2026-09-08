[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$Url,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = (
        Join-Path $HOME `
            "Videos\AI-Video-Analysis\Acquisitions\TikTok"
    )
)

$ErrorActionPreference = "Stop"

# Make this wrapper's own stdout/stderr deterministic UTF-8.
$Utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8

$Helper = Join-Path `
    $PSScriptRoot `
    "download_tiktok_for_videoai.py"

$ExpectedHelperHash =
    "9CD1F3DA519B44314DF07810590A2962DAF9CBB7D61A6F05943A459B21293793"

if(-not (Test-Path -LiteralPath $Helper -PathType Leaf)){
    throw "TikTok Python helper not found: $Helper"
}

$ActualHelperHash = (
    Get-FileHash `
        -LiteralPath $Helper `
        -Algorithm SHA256
).Hash

if($ActualHelperHash -ne $ExpectedHelperHash){
    throw (
        "TikTok Python helper hash mismatch. " +
        "Expected $ExpectedHelperHash; " +
        "found $ActualHelperHash."
    )
}

$Uv = (
    Get-Command `
        uv `
        -CommandType Application `
        -ErrorAction Stop
).Source

$Utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8

# Force Python UTF-8 exactly as dev5 did, but use native PowerShell
# invocation because ProcessStartInfo -> uv hangs inside Start-Job.
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"

# Preserve native nonzero exit codes for the wrapper to forward itself.
$PSNativeCommandUseErrorActionPreference = $false

$ErrFile = Join-Path (
    [IO.Path]::GetTempPath()
) (
    "VideoAI-TikTok-" +
    [Guid]::NewGuid().ToString("N") +
    ".stderr.txt"
)

try {
    $StdoutLines = @(
        & $Uv `
            run `
            --no-project `
            --with playwright `
            --with requests `
            python `
            $Helper `
            $Url `
            --output-root $OutputRoot `
            2> $ErrFile
    )

    $ExitCode = $LASTEXITCODE

    $Stdout = (
        $StdoutLines |
        ForEach-Object { [string]$_ }
    ) -join [Environment]::NewLine

    if($StdoutLines.Count -gt 0){
        $Stdout += [Environment]::NewLine
    }

    if(Test-Path -LiteralPath $ErrFile -PathType Leaf){
        $Stderr = [IO.File]::ReadAllText(
            $ErrFile,
            [Text.Encoding]::UTF8
        )
    }
    else {
        $Stderr = ""
    }
}
finally {
    Remove-Item `
        -LiteralPath $ErrFile `
        -Force `
        -ErrorAction SilentlyContinue
}

if(-not [string]::IsNullOrEmpty($Stdout)){
    $StdoutBytes = [Text.Encoding]::UTF8.GetBytes($Stdout)
        $StdoutStream = [Console]::OpenStandardOutput()

        $StdoutStream.Write(
            $StdoutBytes,
            0,
            $StdoutBytes.Length
        )

        $StdoutStream.Flush()
}

if(-not [string]::IsNullOrEmpty($Stderr)){
    $StderrBytes = [Text.Encoding]::UTF8.GetBytes($Stderr)
        $StderrStream = [Console]::OpenStandardError()

        $StderrStream.Write(
            $StderrBytes,
            0,
            $StderrBytes.Length
        )

        $StderrStream.Flush()
}

exit $ExitCode
