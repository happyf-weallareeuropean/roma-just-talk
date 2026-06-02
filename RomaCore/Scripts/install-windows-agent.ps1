param(
    [string]$PackageDir = "",
    [string]$InstallDir = "",
    [string]$ConfigPath = "",
    [string]$Endpoint = "http://127.0.0.1:1/v1/audio/transcriptions",
    [string]$Model = "mock-whisper",
    [string]$ApiKeyEnv = "PATH",
    [string]$ApiKeyName = "",
    [string]$SecretDir = "",
    [string]$Language = "",
    [string]$Prompt = "",
    [string[]]$WordReplacement = @("just talk=roma-just-talk"),
    [switch]$UseHoldHook,
    [switch]$UseToggle,
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$PasteDictation,
    [switch]$RunDictation,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-Host ""
    Write-Host "== $Name =="
    & $Command
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Require-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Required file was not found: $Path"
    }
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $PSScriptRoot
}
$PackageDir = Resolve-FullPath -Path $PackageDir

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not set; pass -InstallDir explicitly"
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA "roma-just-talk\agent"
}
$InstallDir = Resolve-FullPath -Path $InstallDir

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (![string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $ConfigPath = Join-Path $env:APPDATA "roma-just-talk\windows-agent.json"
    } else {
        $ConfigPath = Join-Path $InstallDir "windows-agent.json"
    }
}
$ConfigPath = Resolve-FullPath -Path $ConfigPath

if ([string]::IsNullOrWhiteSpace($SecretDir) -and
    ![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    $SecretDir = Join-Path $InstallDir "secrets"
}
if (![string]::IsNullOrWhiteSpace($SecretDir)) {
    $SecretDir = Resolve-FullPath -Path $SecretDir
}

$agentSource = Join-Path $PackageDir "RomaWindowsAgent.exe"
$smokeSource = Join-Path $PackageDir "smoke-windows-agent.ps1"
Require-File -Path $agentSource
Require-File -Path $smokeSource

Invoke-Step "copy package files" {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $knownFiles = @(
        "RomaWindowsAgent.exe",
        "RomaWindowsAgent.pdb",
        "smoke-windows-agent.ps1",
        "install-windows-agent.ps1",
        "manifest.txt",
        "sample-windows-agent.json"
    )
    foreach ($file in $knownFiles) {
        $source = Join-Path $PackageDir $file
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $InstallDir $file) -Force
        }
    }

    $runtimeLibraries = @(
        Get-ChildItem -LiteralPath $PackageDir -Filter "*.dll" |
            Sort-Object Name
    )
    foreach ($library in $runtimeLibraries) {
        Copy-Item -LiteralPath $library.FullName -Destination (Join-Path $InstallDir $library.Name) -Force
    }

    Require-File -Path (Join-Path $InstallDir "RomaWindowsAgent.exe")
    Require-File -Path (Join-Path $InstallDir "smoke-windows-agent.ps1")
    Write-Host "install_dir=$InstallDir"
    Write-Host "runtime_dlls=$($runtimeLibraries.Count)"
}

if (!$SkipSmoke) {
    Invoke-Step "installed agent smoke" {
        $installedSmoke = Join-Path $InstallDir "smoke-windows-agent.ps1"
        $smokeArgs = @(
            "-PackageDir", $InstallDir,
            "-OutputDir", (Join-Path $InstallDir "smoke"),
            "-ConfigPath", $ConfigPath,
            "-Endpoint", $Endpoint,
            "-Model", $Model
        )
        if ($PSBoundParameters.ContainsKey("ApiKeyEnv")) {
            $smokeArgs += @("-ApiKeyEnv", $ApiKeyEnv)
        }
        if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
            $smokeArgs += @("-ApiKeyName", $ApiKeyName)
        }
        if (![string]::IsNullOrWhiteSpace($SecretDir)) {
            $smokeArgs += @("-SecretDir", $SecretDir)
        }
        if (![string]::IsNullOrWhiteSpace($Language)) {
            $smokeArgs += @("-Language", $Language)
        }
        if (![string]::IsNullOrWhiteSpace($Prompt)) {
            $smokeArgs += @("-Prompt", $Prompt)
        }
        $replacementValues = @(
            $WordReplacement |
                Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        )
        if ($replacementValues.Count -gt 0) {
            $smokeArgs += "-WordReplacement"
            $smokeArgs += $replacementValues
        }
        if ($UseHoldHook) {
            $smokeArgs += "-UseHoldHook"
        }
        if ($UseToggle) {
            $smokeArgs += "-UseToggle"
        }
        $smokeArgs += @("-HoldTimeoutSeconds", "$HoldTimeoutSeconds")
        $smokeArgs += @("-RecordSeconds", "$RecordSeconds")
        if ($PasteDictation) {
            $smokeArgs += "-PasteDictation"
        }
        if ($RunDictation) {
            $smokeArgs += "-RunDictation"
        }

        & $installedSmoke @smokeArgs
    }
}

Write-Host ""
$installedAgent = Join-Path $InstallDir "RomaWindowsAgent.exe"
$installedSmoke = Join-Path $InstallDir "smoke-windows-agent.ps1"
Write-Host "installed_agent=$installedAgent"
Write-Host "installed_smoke=$installedSmoke"
Write-Host "config=$ConfigPath"
