# Production functions with deterministic local discovery/probe fixtures.
[CmdletBinding()]
param([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
$path = Join-Path $RepositoryRoot 'src/Test-VideoAIHealth.ps1'
$text = [IO.File]::ReadAllText($path)
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) 'Health parser errors'
Assert-True (-not $text.Contains([string][char]13)) 'Health script must be LF'
Assert-True (-not [regex]::IsMatch($text, '(?m)[ \t]+$')) 'Health trailing whitespace'
$functions = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false))
Assert-True (@($functions | Group-Object Name | Where-Object Count -ne 1).Count -eq 0) 'Duplicate health functions'
Assert-True (@($functions | Where-Object Name -eq 'Test-VideoAICudaRuntime').Count -eq 1) 'CUDA function count'
$calls = @($ast.FindAll({ param($n)
    $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Test-VideoAICudaRuntime'
}, $true))
Assert-True ($calls.Count -eq 1) 'CUDA registration count'
foreach ($function in $functions) { . ([scriptblock]::Create($function.Extent.Text)) }
$realProbe = (Get-Item Function:Invoke-HealthProbe).ScriptBlock
$script:commandPresent = $true
$script:probeOutput = @()
$script:probeExit = 0
$script:observedArguments = @()
function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    if ($script:commandPresent) { [PSCustomObject]@{ Source = 'fixture-tool.exe' } }
}
function Invoke-HealthProbe {
    param($FilePath, $ArgumentList)
    $script:observedArguments = $ArgumentList
    [PSCustomObject]@{ ExitCode = $script:probeExit; Output = $script:probeOutput }
}
$script:probeOutput = @('{"ok":true,"cuda_device_count":1,"cuda_compute_types":["float16"],"versions":{"analysis-video":"0.1.1","faster-whisper":"1.2.1","ctranslate2":"4.8.2","nvidia-cublas-cu12":"12.9.2.10","nvidia-cudnn-cu12":"9.26.0.51"}}')
$result = Test-VideoAICudaRuntime
Assert-True ($result.Status -eq 'PASS' -and $result.Required) 'CUDA ready fixture'
Assert-True ($result.Detail -match 'CUDA devices: 1;' -and $result.Detail -match 'cuBLAS 12.9.2.10; cuDNN 9.26.0.51;' -and $result.Detail -notmatch '\{\d+\}') 'CUDA detail formatting'
foreach ($flag in @('--offline', '--no-python-downloads', '--no-project', 'analysis-video[cuda]==0.1.1')) {
    Assert-True ($flag -in $script:observedArguments) "Missing runtime contract argument: $flag"
}
$script:probeExit = 1
$script:probeOutput = @('No cached package; network is disabled')
Assert-True ((Test-VideoAICudaRuntime).Status -eq 'MISSING') 'Empty cache must be MISSING'
$script:probeExit = 0
foreach ($bad in @('not JSON', '{}', '{"ok":false}', '{"ok":true}', '{"ok":"yes"}')) {
    $script:probeOutput = @($bad)
    Assert-True ((Test-VideoAICudaRuntime).Status -eq 'MISSING') "Malformed CUDA output: $bad"
}
$script:commandPresent = $false
Assert-True ((Test-VideoAICudaRuntime).Status -eq 'MISSING') 'Missing uv must be MISSING'
$params = @{
    Name = 'fixture'; CommandName = 'fixture'; RequiredFor = @('Development')
    VersionArguments = @('--version'); MissingDetail = 'missing'; AvailableDetail = 'ready'
}
$result = Test-RequiredCommand @params -Required $false
Assert-True ($result.Status -eq 'OPTIONAL' -and -not $result.Required) 'Optional absence must not block'
Assert-True ((Test-RequiredCommand @params).Status -eq 'MISSING') 'Required absence must block'
$script:commandPresent = $true
foreach ($failure in @(@{Code=9; Output=@('broken')}, @{Code=0; Output=@()})) {
    $script:probeExit = $failure.Code; $script:probeOutput = $failure.Output
    Assert-True ((Test-RequiredCommand @params).Status -eq 'MISSING') 'Broken/empty required version probe'
    Assert-True ((Test-RequiredCommand @params -Required $false).Status -eq 'OPTIONAL') 'Broken/empty optional version probe'
}
$script:probeExit = 0; $script:probeOutput = @('fixture 1.0')
Assert-True ((Test-RequiredCommand @params -Required $false).Status -eq 'PASS') 'Present optional command'
$pwsh = (Get-Process -Id $PID).Path
$result = & $realProbe -FilePath $pwsh -ArgumentList @('-NoProfile', '-Command', '[Console]::Out.WriteLine("out"); [Console]::Error.WriteLine("err"); exit 9')
Assert-True ($result.ExitCode -eq 9 -and 'out' -in $result.Output -and 'err' -in $result.Output) 'Native exit/output preservation'
$result = & $realProbe -FilePath $pwsh -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 20') -TimeoutSeconds 1
Assert-True ($result.ExitCode -eq -1 -and $result.Output[0] -match 'timed out') 'Native timeout'
$result = & $realProbe -FilePath (Join-Path $RepositoryRoot 'tests/absent-fixture.exe') -ArgumentList @()
Assert-True ($result.ExitCode -eq -1) 'Native start failure'
Write-Host 'PASS: health structure, CUDA contract/failure modes, optional dependencies and bounded native probes'

# Exercise the original report/exit block in child processes. Only dependency
# discovery is replaced; registration, CUDA classification and reporting stay real.
$reportTry = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })
Assert-True ($reportTry.Count -eq 1) 'Expected one top-level report block'
$fixtureHeader = @'
param([switch]$Json, [string]$Scenario)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$HealthSchema = 'videoai-health/v1'
$ChromePath = ''; $NvidiaSmiPath = ''
'@
$fixtureSource = $fixtureHeader + [char]10 + (($functions | ForEach-Object { $_.Extent.Text }) -join [char]10)
foreach ($entry in @(
    @('Test-WindowsEnvironment', 'Windows'),
    @('Test-PowerShellEnvironment', 'PowerShell'),
    @('Test-Uv', 'uv'),
    @('Test-Ffmpeg', 'FFmpeg'),
    @('Test-Ffprobe', 'ffprobe'),
    @('Test-Deno', 'Deno'),
    @('Test-GoogleChrome', 'Google Chrome'),
    @('Test-NvidiaGpuDriver', 'NVIDIA GPU/Driver')
)) {
    $fixtureSource += [char]10 + ('function {0} {{ New-HealthResult -Name ''{1}'' -Status PASS -Required $true -RequiredFor @(''Fixture'') }}' -f $entry[0], $entry[1])
}
$fixtureSource += [char]10 + @'
function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    if ($Name -eq 'uv') { [PSCustomObject]@{ Source = 'fixture-uv.exe' } }
}
function Invoke-HealthProbe {
    param($FilePath, $ArgumentList)
    foreach ($flag in @('--offline', '--no-python-downloads')) {
        if ($flag -notin $ArgumentList) { throw "Missing offline flag: $flag" }
    }
    if ($Scenario -eq 'missing') {
        return [PSCustomObject]@{ ExitCode = 1; Output = @('network is disabled; no cached package') }
    }
    [PSCustomObject]@{
        ExitCode = 0
        Output = @('{"ok":true,"cuda_device_count":1,"cuda_compute_types":["float16"],"versions":{"analysis-video":"0.1.1","faster-whisper":"1.2.1","ctranslate2":"4.8.2","nvidia-cublas-cu12":"12.9.2.10","nvidia-cudnn-cu12":"9.26.0.51"}}')
    }
}
if ($Scenario -eq 'error') { function Test-WindowsEnvironment { throw 'fixture checker error' } }
'@
$fixtureSource += [char]10 + $reportTry[0].Extent.Text
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureDir = Join-Path $tempRoot ('VideoAI-health-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureDir
try {
    $fixturePath = Join-Path $fixtureDir 'checker.ps1'
    [IO.File]::WriteAllText($fixturePath, $fixtureSource.Replace(([string][char]13 + [char]10), [string][char]10), [Text.UTF8Encoding]::new($false))
    foreach ($scenario in @('ready', 'missing', 'error')) {
        $expectedExit = switch ($scenario) { ready { 0 }; missing { 1 }; error { 2 } }
        $jsonResult = & $realProbe -FilePath $pwsh -ArgumentList @('-NoProfile', '-File', $fixturePath, '-Json', '-Scenario', $scenario)
        Assert-True ($jsonResult.ExitCode -eq $expectedExit) "$scenario JSON exit: $($jsonResult.Output)"
        $report = ($jsonResult.Output -join [char]10) | ConvertFrom-Json
        Assert-True ($report.Schema -eq 'videoai-health/v1') 'Report schema'
        if ($scenario -eq 'error') {
            Assert-True ($report.Error -eq 'fixture checker error') 'Structured checker error'
        }
        else {
            Assert-True ($report.Checks.Count -eq 11 -and $report.Summary.Total -eq 11) 'Eleven actual report checks'
            Assert-True (@($report.Checks | Where-Object Required).Count -eq 9) 'Nine required report checks'
            Assert-True ($report.Summary.OptionalMissing -eq 2) 'Optional absence reported'
            Assert-True ($report.Summary.MissingRequired -eq $expectedExit) 'Required failure summary'
            Assert-True ($report.Summary.Pass -eq (9 - $expectedExit)) 'Pass summary'
            $runtime = $report.Checks | Where-Object Name -eq 'VideoAI CUDA Runtime'
            Assert-True ($runtime.Status -eq $(if ($scenario -eq 'ready') { 'PASS' } else { 'MISSING' })) 'Runtime classification in report'
        }
        $human = & $realProbe -FilePath $pwsh -ArgumentList @('-NoProfile', '-File', $fixturePath, '-Scenario', $scenario)
        Assert-True ($human.ExitCode -eq $expectedExit) "$scenario human exit"
    }
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixtureDir)
    Assert-True ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf) -like 'VideoAI-health-*') 'Unsafe health fixture cleanup path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'PASS: complete reports and human/JSON exit contracts 0, 1, 2'
