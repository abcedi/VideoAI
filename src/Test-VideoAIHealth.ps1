# VideoAI dependency and environment health checker.
# Read-only: does not install software or modify system configuration.

[CmdletBinding()]
param(
    [switch]$Json,

    [string]$ChromePath,

    [string]$NvidiaSmiPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$HealthSchema = "videoai-health/v1"
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-HealthProbe {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [int]$TimeoutSeconds = 60
    )

    # Bound dependency probes and keep stdout/stderr out of the JSON report.
    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $FilePath
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    foreach ($Argument in $ArgumentList) {
        $StartInfo.ArgumentList.Add($Argument)
    }
    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    try {
        $null = $Process.Start()
        $Stdout = $Process.StandardOutput.ReadToEndAsync()
        $Stderr = $Process.StandardError.ReadToEndAsync()
        if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
            $Process.Kill($true)
            return [PSCustomObject]@{ ExitCode = -1; Output = @('Dependency probe timed out.') }
        }
        return [PSCustomObject]@{
            ExitCode = $Process.ExitCode
            Output = @(($Stdout.GetAwaiter().GetResult() + "`n" + $Stderr.GetAwaiter().GetResult()) -split '\r?\n')
        }
    }
    catch {
        return [PSCustomObject]@{ ExitCode = -1; Output = @($_.Exception.Message) }
    }
    finally {
        $Process.Dispose()
    }
}

function New-HealthResult {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet("PASS", "MISSING", "OPTIONAL")]
        [string]$Status,

        [Parameter(Mandatory)]
        [bool]$Required,

        [Parameter(Mandatory)]
        [string[]]$RequiredFor,

        [string]$Version,

        [string]$Path,

        [string]$Detail
    )

    [PSCustomObject]@{
        Name        = $Name
        Status      = $Status
        Required    = $Required
        RequiredFor = $RequiredFor
        Version     = $Version
        Path        = $Path
        Detail      = $Detail
    }
}

function Test-WindowsEnvironment {
    $IsWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )

    if (-not $IsWindowsPlatform) {
        return New-HealthResult `
            -Name "Windows" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Core") `
            -Detail "VideoAI v0.6 is currently Windows-first."
    }

    if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64' -or
        [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -ne 'X64') {
        return New-HealthResult -Name "Windows" -Status "MISSING" -Required $true `
            -RequiredFor @("Core") -Detail "The current VideoAI CUDA distribution requires Windows x64 and an x64 PowerShell process."
    }

    return New-HealthResult `
        -Name "Windows" `
        -Status "PASS" `
        -Required $true `
        -RequiredFor @("Core") `
        -Version ([System.Environment]::OSVersion.Version.ToString()) `
        -Detail ([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)
}

function Test-PowerShellEnvironment {
    $Version = $PSVersionTable.PSVersion

    if ($Version.Major -lt 7) {
        return New-HealthResult `
            -Name "PowerShell" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Core", "GUI") `
            -Version $Version.ToString() `
            -Path (Get-Process -Id $PID).Path `
            -Detail "PowerShell 7 or newer is required."
    }

    return New-HealthResult `
        -Name "PowerShell" `
        -Status "PASS" `
        -Required $true `
        -RequiredFor @("Core", "GUI") `
        -Version $Version.ToString() `
        -Path (Get-Process -Id $PID).Path `
        -Detail "PowerShell runtime is available."
}

function Test-RequiredCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [string[]]$RequiredFor,

        [Parameter(Mandatory)]
        [string[]]$VersionArguments,

        [Parameter(Mandatory)]
        [string]$MissingDetail,

        [Parameter(Mandatory)]
        [string]$AvailableDetail,

        [bool]$Required = $true
    )

    $MissingStatus = if ($Required) { "MISSING" } else { "OPTIONAL" }

    $Command = Get-Command `
        $CommandName `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $Command -or ($CommandName -eq "python" -and $Command.Source -match '[\\/]WindowsApps[\\/]') ) {
        return New-HealthResult `
            -Name $Name `
            -Status $MissingStatus `
            -Required $Required `
            -RequiredFor $RequiredFor `
            -Detail $MissingDetail
    }

    $Probe = Invoke-HealthProbe -FilePath $Command.Source -ArgumentList $VersionArguments
    $VersionOutput = $Probe.Output
    $ExitCode = $Probe.ExitCode

    $VersionLines = @(
        $VersionOutput |
            ForEach-Object {
                ([string]$_).Trim()
            } |
            Where-Object {
                $_
            }
    )

    if ($ExitCode -ne 0) {
        return New-HealthResult `
            -Name $Name `
            -Status $MissingStatus `
            -Required $Required `
            -RequiredFor $RequiredFor `
            -Path $Command.Source `
            -Detail (
                "$Name was found but its version probe failed " +
                "with exit code $ExitCode."
            )
    }

    if ($VersionLines.Count -eq 0) {
        return New-HealthResult `
            -Name $Name `
            -Status $MissingStatus `
            -Required $Required `
            -RequiredFor $RequiredFor `
            -Path $Command.Source `
            -Detail "$Name was found but returned no version information."
    }

    return New-HealthResult `
        -Name $Name `
        -Status "PASS" `
        -Required $Required `
        -RequiredFor $RequiredFor `
        -Version $VersionLines[0] `
        -Path $Command.Source `
        -Detail $AvailableDetail
}

function Test-Uv {
    return Test-RequiredCommand `
        -Name "uv" -CommandName "uv" `
        -RequiredFor @("Core", "Conversion", "YouTube", "TikTok") `
        -VersionArguments @("--version") `
        -MissingDetail "uv is required for VideoAI runtime dependency orchestration." `
        -AvailableDetail "uv is available."
}

function Test-Ffmpeg {
    return Test-RequiredCommand `
        -Name "FFmpeg" `
        -CommandName "ffmpeg" `
        -RequiredFor @("Conversion", "YouTube") `
        -VersionArguments @("-version") `
        -MissingDetail "FFmpeg is required for VideoAI media processing." `
        -AvailableDetail "FFmpeg is available."
}

function Test-Ffprobe {
    return Test-RequiredCommand `
        -Name "ffprobe" `
        -CommandName "ffprobe" `
        -RequiredFor @("Conversion", "YouTube", "TikTok") `
        -VersionArguments @("-version") `
        -MissingDetail "ffprobe is required for media validation and probing." `
        -AvailableDetail "ffprobe is available."
}

function Test-Deno {
    return Test-RequiredCommand `
        -Name "Deno" `
        -CommandName "deno" `
        -RequiredFor @("YouTube") `
        -VersionArguments @("--version") `
        -MissingDetail "Deno is required by the current YouTube acquisition path." `
        -AvailableDetail "Deno is available."
}

function Test-GoogleChrome {
    param(
        [string]$ExplicitPath
    )

    $Candidates = @()

    if ($ExplicitPath) {
        $Candidates += $ExplicitPath
    }
    else {
        $PathCommand = Get-Command `
            "chrome.exe" `
            -CommandType Application `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($PathCommand) {
            $Candidates += $PathCommand.Source
        }

        $IsWindowsPlatform =
            [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                [System.Runtime.InteropServices.OSPlatform]::Windows
            )

        if ($IsWindowsPlatform) {
            $RegistryPaths = @(
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
                "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
            )

            foreach ($RegistryPath in $RegistryPaths) {
                if (Test-Path -LiteralPath $RegistryPath) {
                    $RegistryItem = Get-Item `
                        -LiteralPath $RegistryPath `
                        -ErrorAction SilentlyContinue

                    if ($RegistryItem) {
                        $RegistryValue = $RegistryItem.GetValue("")

                        if ($RegistryValue) {
                            $Candidates += ([string]$RegistryValue).Trim('"')
                        }
                    }
                }
            }
        }

        if ($env:ProgramFiles) {
            $Candidates += Join-Path `
                $env:ProgramFiles `
                "Google\Chrome\Application\chrome.exe"
        }

        $ProgramFilesX86 =
            [Environment]::GetEnvironmentVariable(
                "ProgramFiles(x86)"
            )

        if ($ProgramFilesX86) {
            $Candidates += Join-Path `
                $ProgramFilesX86 `
                "Google\Chrome\Application\chrome.exe"
        }

        if ($env:LOCALAPPDATA) {
            $Candidates += Join-Path `
                $env:LOCALAPPDATA `
                "Google\Chrome\Application\chrome.exe"
        }
    }

    $ChromeExecutable = @(
        $Candidates |
            Where-Object {
                $_ -and
                (Test-Path -LiteralPath $_ -PathType Leaf)
            } |
            Select-Object -Unique
    ) |
        Select-Object -First 1

    if (-not $ChromeExecutable) {
        $Detail = if ($ExplicitPath) {
            "Google Chrome was not found at the explicitly supplied path."
        }
        else {
            "Google Chrome is required by the current TikTok acquisition path."
        }

        return New-HealthResult `
            -Name "Google Chrome" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("TikTok") `
            -Detail $Detail
    }

    $ChromeItem = Get-Item `
        -LiteralPath $ChromeExecutable `
        -ErrorAction Stop

    $Version = $ChromeItem.VersionInfo.ProductVersion

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = $ChromeItem.VersionInfo.FileVersion
    }

    return New-HealthResult `
        -Name "Google Chrome" `
        -Status "PASS" `
        -Required $true `
        -RequiredFor @("TikTok") `
        -Version $Version `
        -Path $ChromeItem.FullName `
        -Detail "Google Chrome is available for Playwright TikTok acquisition."
}

function Test-NvidiaGpuDriver {
    param(
        [string]$ExplicitPath
    )

    $Candidates = @()

    if ($ExplicitPath) {
        $Candidates += $ExplicitPath
    }

    if (-not $ExplicitPath) {
        $PathCommand = Get-Command `
            "nvidia-smi.exe" `
            -CommandType Application `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($PathCommand) {
            $Candidates += $PathCommand.Source
        }

        if ($env:SystemRoot) {
            $Candidates += Join-Path `
                $env:SystemRoot `
                "System32\nvidia-smi.exe"
        }

        if ($env:ProgramFiles) {
            $Candidates += Join-Path `
                $env:ProgramFiles `
                "NVIDIA Corporation\NVSMI\nvidia-smi.exe"
        }
    }

    $NvidiaExecutable = @(
        $Candidates |
            Where-Object {
                $_ -and
                (Test-Path -LiteralPath $_ -PathType Leaf)
            } |
            Select-Object -Unique
    ) |
        Select-Object -First 1

    if (-not $NvidiaExecutable) {
        $Detail = if ($ExplicitPath) {
            "nvidia-smi was not found at the explicitly supplied path."
        }
        else {
            "An NVIDIA GPU and working NVIDIA driver are required by the current conversion path."
        }

        return New-HealthResult `
            -Name "NVIDIA GPU/Driver" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Detail $Detail
    }

    $NvidiaItem = Get-Item `
        -LiteralPath $NvidiaExecutable `
        -ErrorAction Stop

    try {
        $NativeProbe = Invoke-HealthProbe -FilePath $NvidiaItem.FullName -ArgumentList @("--query-gpu=name", "--format=csv,noheader")
        $GpuOutput = $NativeProbe.Output
        $GpuExit = $NativeProbe.ExitCode
    }
    catch {
        return New-HealthResult `
            -Name "NVIDIA GPU/Driver" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $NvidiaItem.FullName `
            -Detail "nvidia-smi was found but could not be executed."
    }

    if ($GpuExit -ne 0) {
        return New-HealthResult `
            -Name "NVIDIA GPU/Driver" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $NvidiaItem.FullName `
            -Detail "nvidia-smi GPU query failed with exit code $GpuExit."
    }

    $GpuNames = @(
        $GpuOutput |
            ForEach-Object {
                ([string]$_).Trim()
            } |
            Where-Object {
                $_
            }
    )

    if ($GpuNames.Count -eq 0) {
        return New-HealthResult `
            -Name "NVIDIA GPU/Driver" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $NvidiaItem.FullName `
            -Detail "nvidia-smi returned no NVIDIA GPUs."
    }

    try {
        $NativeProbe = Invoke-HealthProbe -FilePath $NvidiaItem.FullName -ArgumentList @("--query-gpu=driver_version", "--format=csv,noheader")
        $DriverOutput = $NativeProbe.Output
        $DriverExit = $NativeProbe.ExitCode
    }
    catch {
        return New-HealthResult `
            -Name "NVIDIA GPU/Driver" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $NvidiaItem.FullName `
            -Detail "The NVIDIA driver version query could not be executed."
    }

    if ($DriverExit -ne 0) {
        return New-HealthResult `
            -Name "NVIDIA GPU/Driver" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $NvidiaItem.FullName `
            -Detail "NVIDIA driver query failed with exit code $DriverExit."
    }

    $DriverVersions = @(
        $DriverOutput |
            ForEach-Object {
                ([string]$_).Trim()
            } |
            Where-Object {
                $_
            }
    )

    if ($DriverVersions.Count -eq 0) {
        return New-HealthResult `
            -Name "NVIDIA GPU/Driver" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $NvidiaItem.FullName `
            -Detail "nvidia-smi returned no NVIDIA driver version."
    }

    if ($DriverVersions.Count -ne $GpuNames.Count) {
        return New-HealthResult `
            -Name "NVIDIA GPU/Driver" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $NvidiaItem.FullName `
            -Detail "NVIDIA GPU and driver query counts were inconsistent."
    }

    $UniqueDriverVersions = @(
        $DriverVersions |
            Select-Object -Unique
    )

    $VersionText =
        "Driver " +
        ($UniqueDriverVersions -join ", ")

    $GpuText =
        $GpuNames -join "; "

    return New-HealthResult `
        -Name "NVIDIA GPU/Driver" `
        -Status "PASS" `
        -Required $true `
        -RequiredFor @("Conversion") `
        -Version $VersionText `
        -Path $NvidiaItem.FullName `
        -Detail (
            "GPU(s): $GpuText. NVIDIA GPU and driver are visible; " +
            "VideoAI CUDA runtime readiness is checked separately."
        )
}



function Test-VideoAICudaRuntime {
    $UvCommand = Get-Command `
        "uv" `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $UvCommand) {
        return New-HealthResult `
            -Name "VideoAI CUDA Runtime" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Detail "uv is unavailable, so the VideoAI CUDA runtime cannot be probed."
    }

    $ProbeCode = @"
import json
import os
import shutil
import subprocess
from pathlib import Path
from importlib.metadata import version, PackageNotFoundError

def package_version(name):
    try:
        return version(name)
    except PackageNotFoundError:
        return None

def one_bin(mod):
    roots = list(mod.__path__)

    if len(roots) != 1:
        raise RuntimeError(
            f"Expected one package root for {mod.__name__}; found {roots}"
        )

    path = Path(roots[0]) / "bin"

    if not path.is_dir():
        raise RuntimeError(f"NVIDIA DLL directory missing: {path}")

    return path

try:
    import nvidia.cublas
    import nvidia.cudnn

    cublas = one_bin(nvidia.cublas)
    cudnn = one_bin(nvidia.cudnn)

    required_dlls = [
        cublas / "cublas64_12.dll",
        cublas / "cublasLt64_12.dll",
        cudnn / "cudnn64_9.dll",
    ]

    missing_dlls = [
        str(path)
        for path in required_dlls
        if not path.is_file()
    ]

    if missing_dlls:
        raise RuntimeError(
            "Required NVIDIA DLL(s) missing: "
            + ", ".join(missing_dlls)
        )

    os.environ["PATH"] = (
        str(cublas)
        + os.pathsep
        + str(cudnn)
        + os.pathsep
        + os.environ.get("PATH", "")
    )

    dll_handles = []

    if os.name == "nt":
        dll_handles.append(os.add_dll_directory(str(cublas)))
        dll_handles.append(os.add_dll_directory(str(cudnn)))

    import ctranslate2
    import faster_whisper

    device_count = ctranslate2.get_cuda_device_count()

    compute_types = []

    if device_count > 0:
        compute_types = sorted(
            ctranslate2.get_supported_compute_types("cuda", 0)
        )

    analysis_video = shutil.which("analysis-video")

    if not analysis_video:
        raise RuntimeError(
            "analysis-video executable is unavailable in the pinned uv environment"
        )

    doctor_process = subprocess.run(
        [analysis_video, "doctor"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=os.environ.copy(),
        timeout=30,
    )

    if doctor_process.returncode != 0:
        raise RuntimeError(
            "analysis-video doctor failed with exit code "
            + str(doctor_process.returncode)
        )

    doctor = json.loads(doctor_process.stdout)

    speech = (
        doctor.get("capabilities", {})
        .get("speech-recognition", {})
    )

    result = {
        "ok": (
            device_count > 0
            and doctor.get("ok") is True
            and speech.get("available") is True
            and speech.get("resolved_backend") == "faster-whisper"
            and speech.get("cuda_available") is True
        ),
        "cuda_device_count": device_count,
        "cuda_compute_types": compute_types,
        "versions": {
            "analysis-video": package_version("analysis-video"),
            "faster-whisper": package_version("faster-whisper"),
            "ctranslate2": package_version("ctranslate2"),
            "nvidia-cublas-cu12": package_version("nvidia-cublas-cu12"),
            "nvidia-cudnn-cu12": package_version("nvidia-cudnn-cu12"),
        },
    }

    print(json.dumps(result))

    if not result["ok"]:
        raise SystemExit(11)

except Exception as exc:
    print(
        json.dumps(
            {
                "ok": False,
                "error": f"{type(exc).__name__}: {exc}",
            }
        )
    )
    raise SystemExit(10)
"@

    $NativeProbe = Invoke-HealthProbe -FilePath $UvCommand.Source -ArgumentList @(
        "run", "--no-project", "--offline", "--no-python-downloads", "--no-progress",
        "--with", "analysis-video[cuda]==0.1.1", "python", "-c", $ProbeCode
    )
    $ProbeOutput = $NativeProbe.Output
    $ProbeExit = $NativeProbe.ExitCode

    $OutputLines = @(
        $ProbeOutput |
            ForEach-Object {
                ([string]$_).Trim()
            } |
            Where-Object {
                $_
            }
    )

    $JsonCandidates = @(
        $OutputLines |
            Where-Object {
                $_.StartsWith("{") -and
                $_.EndsWith("}")
            }
    )

    $Probe = $null

    if ($JsonCandidates.Count -gt 0) {
        try {
            $Probe =
                $JsonCandidates[-1] |
                ConvertFrom-Json -AsHashtable
        }
        catch {
            $Probe = $null
        }
    }

    if ($ProbeExit -ne 0) {
        $FailureDetail = $null

        if (
            $Probe -and
            $Probe.ContainsKey("error") -and
            $Probe.error
        ) {
            $FailureDetail = [string]$Probe.error
        }

        if (-not $FailureDetail) {
            $FailureDetail =
                ($OutputLines | Select-Object -Last 3) -join " "
        }

        if ([string]::IsNullOrWhiteSpace($FailureDetail)) {
            $FailureDetail =
                "The offline pinned CUDA runtime probe failed."
        }

        return New-HealthResult `
            -Name "VideoAI CUDA Runtime" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $UvCommand.Source `
            -Detail (
                "Offline analysis-video[cuda]==0.1.1 runtime is not ready: " +
                $FailureDetail
            )
    }

    if (-not $Probe) {
        return New-HealthResult `
            -Name "VideoAI CUDA Runtime" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $UvCommand.Source `
            -Detail "CUDA runtime probe returned no parseable JSON result."
    }

    $RequiredVersions = @('analysis-video', 'faster-whisper', 'ctranslate2', 'nvidia-cublas-cu12', 'nvidia-cudnn-cu12')
    $ValidProbe = $Probe -is [System.Collections.IDictionary] -and
        $Probe.ContainsKey('ok') -and $Probe.ok -is [bool] -and $Probe.ok -and
        $Probe.ContainsKey('versions') -and $Probe.versions -is [System.Collections.IDictionary] -and
        $Probe.ContainsKey('cuda_compute_types') -and $Probe.cuda_compute_types -is [array] -and
        $Probe.ContainsKey('cuda_device_count') -and
        ($Probe.cuda_device_count -is [long] -or $Probe.cuda_device_count -is [int]) -and
        $Probe.cuda_device_count -gt 0
    if ($ValidProbe) {
        foreach ($Package in $RequiredVersions) {
            if (-not $Probe.versions.ContainsKey($Package) -or
                [string]::IsNullOrWhiteSpace([string]$Probe.versions[$Package])) {
                $ValidProbe = $false
            }
        }
        $ValidProbe = $ValidProbe -and $Probe.versions['analysis-video'] -eq '0.1.1'
    }
    if (-not $ValidProbe) {
        return New-HealthResult `
            -Name "VideoAI CUDA Runtime" `
            -Status "MISSING" `
            -Required $true `
            -RequiredFor @("Conversion") `
            -Path $UvCommand.Source `
            -Detail "Pinned VideoAI CUDA runtime did not report ready."
    }

    $Versions = $Probe.versions

    $VersionText = (
        "analysis-video {0}; faster-whisper {1}; CTranslate2 {2}" -f
        $Versions.'analysis-video',
        $Versions.'faster-whisper',
        $Versions.'ctranslate2'
    )

    $ComputeTypes = @(
        $Probe.cuda_compute_types |
            ForEach-Object {
                [string]$_
            }
    ) -join ", "

    $Detail = (
        ("CUDA devices: {0}; compute types: {1}; cuBLAS {2}; cuDNN {3}; " +
        "analysis-video doctor resolved faster-whisper with CUDA.") -f
        $Probe.cuda_device_count,
        $ComputeTypes,
        $Versions.'nvidia-cublas-cu12',
        $Versions.'nvidia-cudnn-cu12'
    )

    return New-HealthResult `
        -Name "VideoAI CUDA Runtime" `
        -Status "PASS" `
        -Required $true `
        -RequiredFor @("Conversion") `
        -Version $VersionText `
        -Path $UvCommand.Source `
        -Detail $Detail
}

try {
    $Checks = @(
        Test-WindowsEnvironment
        Test-PowerShellEnvironment
        Test-Uv
        Test-Ffmpeg
        Test-Ffprobe
        Test-Deno
        Test-GoogleChrome -ExplicitPath $ChromePath
        Test-NvidiaGpuDriver -ExplicitPath $NvidiaSmiPath
        Test-VideoAICudaRuntime
        Test-RequiredCommand -Name "System Python" -CommandName "python" `
            -RequiredFor @("Development") -VersionArguments @("--version") -Required $false `
            -MissingDetail "Optional: uv manages the conversion Python environment." `
            -AvailableDetail "System Python is available; conversion uses the uv environment."
        Test-RequiredCommand -Name "WinGet" -CommandName "winget" `
            -RequiredFor @("Installation") -VersionArguments @("--version") -Required $false `
            -MissingDetail "Optional: WinGet can help install dependencies." `
            -AvailableDetail "WinGet is available; no packages were installed or updated."
    )

    $MissingRequired = @(
        $Checks |
            Where-Object {
                $_.Required -and
                $_.Status -eq "MISSING"
            }
    )

    $Summary = [PSCustomObject]@{
        Total           = $Checks.Count
        Pass            = @($Checks | Where-Object Status -eq "PASS").Count
        MissingRequired = $MissingRequired.Count
        OptionalMissing = @($Checks | Where-Object Status -eq "OPTIONAL").Count
    }

    $Report = [PSCustomObject]@{
        Schema       = $HealthSchema
        GeneratedUtc = [DateTime]::UtcNow.ToString("o")
        Architecture = [PSCustomObject]@{
            OS = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            Process = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        }
        Checks       = $Checks
        Summary      = $Summary
    }

    if ($Json) {
        $Report | ConvertTo-Json -Depth 6
    }
    else {
        Write-Host "`n===== VideoAI Health Check ====="
        Write-Host "Schema: $HealthSchema"
        Write-Host ""

        $Checks |
            Select-Object `
                Name,
                Status,
                Required,
                @{N="RequiredFor";E={$_.RequiredFor -join ", "}},
                Version,
                Path,
                Detail |
            Format-Table -Wrap -AutoSize

        Write-Host ""
        Write-Host (
            "Summary: {0} PASS, {1} required MISSING, {2} optional missing" -f
            $Summary.Pass,
            $Summary.MissingRequired,
            $Summary.OptionalMissing
        )
    }

    if ($MissingRequired.Count -gt 0) {
        exit 1
    }

    exit 0
}
catch {
    if ($Json) {
        [PSCustomObject]@{
            Schema = $HealthSchema
            Error  = $_.Exception.Message
        } | ConvertTo-Json -Depth 4
    }
    else {
        [Console]::Error.WriteLine("Health checker failed: $($_.Exception.Message)")
    }

    exit 2
}