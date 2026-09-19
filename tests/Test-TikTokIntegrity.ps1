# Execute only the shipped hash guards: no GUI, browser, Python, or network.
[CmdletBinding()]
param([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Read-Ast([string]$Path) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "Parser errors in $Path"
    return $ast
}
function Get-Assignment($Ast, [string]$Name) {
    $nodes = @($Ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -eq $Name
    }, $true))
    Assert-True ($nodes.Count -eq 1) "Expected exactly one assignment to $Name"
    return $nodes[0]
}
function Get-IntegrityGuard($Ast, [string]$ExpectedName, [string]$ActualName) {
    $expected = Get-Assignment $Ast $ExpectedName
    $actual = Get-Assignment $Ast $ActualName
    $parent = $actual.Parent
    Assert-True ($parent -is [Management.Automation.Language.StatementBlockAst] -or
        $parent -is [Management.Automation.Language.NamedBlockAst]) 'Unexpected guard container'
    $statements = @($parent.Statements)
    $guard = $statements[[array]::IndexOf($statements, $actual) + 1]
    Assert-True ($guard -is [Management.Automation.Language.IfStatementAst]) 'Hash guard must follow actual hash calculation'
    Assert-True ($guard.Extent.Text.Contains('$' + $ActualName) -and
        $guard.Extent.Text.Contains('$' + $ExpectedName)) 'Hash guard comparison changed'
    return [scriptblock]::Create(($expected.Extent.Text, $actual.Extent.Text, $guard.Extent.Text) -join [char]10)
}
function Assert-Guard($Guard, [string]$Fixture, [bool]$Accepted, [string]$Message, [string]$ErrorPrefix) {
    $failure = $null
    try {
        & {
            $TikTokHelper = $Fixture
            $Helper = $Fixture
            & $Guard
        }
    }
    catch { $failure = $_.Exception.Message }
    if ($Accepted) {
        Assert-True ($null -eq $failure) "$Message rejected: $failure"
    }
    else {
        Assert-True ($null -ne $failure -and $failure.StartsWith($ErrorPrefix)) "$Message did not fail at the integrity guard: $failure"
    }
    Write-Host "PASS: $Message"
}
$gui = Join-Path $RepositoryRoot 'gui/VideoAI-GUI.ps1'
$wrapper = Join-Path $RepositoryRoot 'src/Download-TikTokForVideoAI.ps1'
$helper = Join-Path $RepositoryRoot 'src/download_tiktok_for_videoai.py'
$guiAst = Read-Ast $gui
$wrapperAst = Read-Ast $wrapper
$guiGuard = Get-IntegrityGuard $guiAst 'expectedTikTokHelperHashes' 'actualTikTokHelperHash'
$helperGuard = Get-IntegrityGuard $wrapperAst 'ExpectedHelperHash' 'ActualHelperHash'
$lf = [IO.File]::ReadAllBytes($wrapper)
$pythonBytes = [IO.File]::ReadAllBytes($helper)
foreach ($path in @($gui, $wrapper, $helper)) {
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-True (-not ($bytes -contains 13)) "Canonical source must use LF: $path"
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) "Unexpected UTF-8 BOM: $path"
}
$encoding = [Text.UTF8Encoding]::new($false, $true)
$crlf = $encoding.GetBytes($encoding.GetString($lf).Replace([string][char]10, ([string][char]13 + [char]10)))
$canonicalHash = '94BE272206BAA3C925C3BD2EF23F6DA5648124AFB698F1302AF81D6D1123BF62'
$transitionalHash = '4C72D945E59400ABE12F20CE26FAF160367A70CC731F9DA1D5AF1339FF41D73A'
$sha = [Security.Cryptography.SHA256]::Create()
try {
    Assert-True ([Convert]::ToHexString($sha.ComputeHash($lf)) -eq $canonicalHash) 'Canonical wrapper bytes changed'
    Assert-True ([Convert]::ToHexString($sha.ComputeHash($crlf)) -eq $transitionalHash) 'Transitional wrapper bytes changed'
}
finally { $sha.Dispose() }
$assignment = Get-Assignment $guiAst 'expectedTikTokHelperHashes'
$approved = @(& ([scriptblock]::Create($assignment.Extent.Text + '; $expectedTikTokHelperHashes')))
Assert-True ($approved.Count -eq 2 -and $canonicalHash -in $approved -and $transitionalHash -in $approved) 'GUI allowlist must contain exactly the two approved hashes'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtures = Join-Path $tempRoot ('VideoAI-integrity-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtures
try {
    $fixture = Join-Path $fixtures 'fixture.bin'
    [IO.File]::WriteAllBytes($fixture, $lf)
    Assert-Guard $guiGuard $fixture $true 'canonical LF wrapper accepted' 'TikTok acquisition helper hash mismatch.'
    [IO.File]::WriteAllBytes($fixture, $crlf)
    Assert-Guard $guiGuard $fixture $true 'approved transitional CRLF wrapper accepted' 'TikTok acquisition helper hash mismatch.'
    [IO.File]::WriteAllText($fixture, 'arbitrary untrusted wrapper', $encoding)
    Assert-Guard $guiGuard $fixture $false 'arbitrary wrapper hash rejected' 'TikTok acquisition helper hash mismatch.'
    $tampered = [byte[]]$lf.Clone()
    $tampered[0] = $tampered[0] -bxor 1
    [IO.File]::WriteAllBytes($fixture, $tampered)
    Assert-Guard $guiGuard $fixture $false 'one-byte wrapper tampering rejected' 'TikTok acquisition helper hash mismatch.'
    [IO.File]::WriteAllBytes($fixture, $pythonBytes)
    Assert-Guard $helperGuard $fixture $true 'canonical Python helper accepted' 'TikTok Python helper hash mismatch.'
    [IO.File]::WriteAllText($fixture, 'arbitrary untrusted helper', $encoding)
    Assert-Guard $helperGuard $fixture $false 'arbitrary Python helper rejected' 'TikTok Python helper hash mismatch.'
    [IO.File]::WriteAllText($fixture, $encoding.GetString($pythonBytes).Replace([string][char]10, ([string][char]13 + [char]10)), $encoding)
    Assert-Guard $helperGuard $fixture $false 'unapproved CRLF Python helper rejected' 'TikTok Python helper hash mismatch.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixtures)
    Assert-True ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf) -like 'VideoAI-integrity-*') 'Unsafe fixture cleanup path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'PASS: TikTok integrity chain (7 behavioral cases, exact allowlist, parser, LF and BOM checks)'
