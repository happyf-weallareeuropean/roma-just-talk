param(
    [string]$PackageDir = "",
    [string]$InstallDir = "",
    [string]$ConfigPath = "",
    [string]$Endpoint = "http://127.0.0.1:1/v1/audio/transcriptions",
    [string]$Model = "mock-whisper",
    [string]$ApiKeyEnv = "PATH",
    [string]$ApiKeyName = "",
    [string]$SecretDir = "",
    [string]$WhisperCLI = "",
    [string]$WhisperModel = "",
    [string]$WhisperOutputDir = "",
    [string[]]$WhisperArgument = @(),
    [string]$Language = "",
    [string]$Prompt = "",
    [string[]]$WordReplacement = @("just talk=roma-just-talk"),
    [switch]$UseHoldHook,
    [switch]$UseToggle,
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$PasteDictation,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2,
    [switch]$RunDictation,
    [switch]$SkipSmoke,
    [switch]$CreateShortcut,
    [switch]$CreateStartupShortcut,
    [switch]$AllowSmokeShortcut,
    [string]$ShortcutDir = "",
    [string]$ShortcutName = "Roma Just Talk Agent.lnk",
    [string]$StartupShortcutDir = "",
    [string]$StartupShortcutName = "Roma Just Talk Agent.lnk"
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

function New-AgentShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath,
        [Parameter(Mandatory = $true)]
        [string]$RunScript,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$RunScript`" -ConfigPath `"$ConfigPath`""
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.WindowStyle = 7
    $shortcut.Save()

    Require-File -Path $ShortcutPath
    $savedShortcut = $shell.CreateShortcut($ShortcutPath)
    if (!$savedShortcut.Arguments.Contains("-ConfigPath") -or
        !$savedShortcut.Arguments.Contains($ConfigPath)) {
        throw "Shortcut does not reference config path: $ConfigPath"
    }

    return $savedShortcut
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

$hasExplicitEndpoint = $PSBoundParameters.ContainsKey("Endpoint")
$hasExplicitModel = $PSBoundParameters.ContainsKey("Model")
$hasExplicitConfigPath = $PSBoundParameters.ContainsKey("ConfigPath") -and ![string]::IsNullOrWhiteSpace($ConfigPath)
$hasExplicitWhisperCLI = $PSBoundParameters.ContainsKey("WhisperCLI")
$hasExplicitWhisperModel = $PSBoundParameters.ContainsKey("WhisperModel")
$hasExplicitApiKeyEnv = $PSBoundParameters.ContainsKey("ApiKeyEnv") -and ![string]::IsNullOrWhiteSpace($ApiKeyEnv)
$hasExplicitApiKeyName = ![string]::IsNullOrWhiteSpace($ApiKeyName)
$hasCloudShortcutConfig = $hasExplicitEndpoint -and $hasExplicitModel -and ($hasExplicitApiKeyEnv -or $hasExplicitApiKeyName)
$hasWhisperShortcutConfig = $hasExplicitWhisperCLI -and $hasExplicitWhisperModel
$hasExistingShortcutConfig = $SkipSmoke -and $hasExplicitConfigPath
$shortcutHasRunnableConfig = $hasCloudShortcutConfig -or $hasWhisperShortcutConfig -or $hasExistingShortcutConfig

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (($hasExplicitEndpoint -or $hasExplicitModel -or $hasExplicitWhisperCLI -or $hasExplicitWhisperModel -or $RunDictation) -and
        ![string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $ConfigPath = Join-Path $env:APPDATA "roma-just-talk\windows-agent.json"
    } else {
        $ConfigPath = Join-Path $InstallDir "smoke\windows-agent-smoke.json"
    }
}
$ConfigPath = Resolve-FullPath -Path $ConfigPath

if ($RestoreClipboard -and $NoRestoreClipboard) {
    throw "RestoreClipboard and NoRestoreClipboard are mutually exclusive"
}

if ($ClipboardRestoreDelaySeconds -lt 0) {
    throw "ClipboardRestoreDelaySeconds must be non-negative"
}

if ([string]::IsNullOrWhiteSpace($SecretDir) -and
    ![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    $SecretDir = Join-Path $InstallDir "secrets"
}
if (![string]::IsNullOrWhiteSpace($SecretDir)) {
    $SecretDir = Resolve-FullPath -Path $SecretDir
}

$agentSource = Join-Path $PackageDir "RomaWindowsAgent.exe"
$smokeSource = Join-Path $PackageDir "smoke-windows-agent.ps1"
$runSource = Join-Path $PackageDir "run-windows-agent.ps1"
Require-File -Path $agentSource
Require-File -Path $smokeSource
Require-File -Path $runSource

Invoke-Step "copy package files" {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $knownFiles = @(
        "RomaWindowsAgent.exe",
        "RomaWhisperCLIMock.exe",
        "RomaWindowsAgent.pdb",
        "smoke-windows-agent.ps1",
        "run-windows-agent.ps1",
        "install-windows-agent.ps1",
        "prove-windows-agent-artifact.ps1",
        "check-windows-proof-report.ps1",
        "manifest.txt",
        "sample-windows-agent.json",
        "sample-local-whisper-agent.json"
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

$packageWhisperMock = Join-Path $PackageDir "RomaWhisperCLIMock.exe"
$installedWhisperMock = Join-Path $InstallDir "RomaWhisperCLIMock.exe"
if ($hasExplicitWhisperCLI -and
    (Resolve-FullPath -Path $WhisperCLI) -eq (Resolve-FullPath -Path $packageWhisperMock) -and
    (Test-Path -LiteralPath $installedWhisperMock)) {
    $WhisperCLI = $installedWhisperMock
    Write-Host "installed_whisper_cli_mock=$WhisperCLI"
}
$installedAgent = Join-Path $InstallDir "RomaWindowsAgent.exe"
if ($hasExplicitWhisperModel -and
    (Resolve-FullPath -Path $WhisperModel) -eq (Resolve-FullPath -Path $agentSource) -and
    (Test-Path -LiteralPath $installedAgent)) {
    $WhisperModel = $installedAgent
    Write-Host "installed_whisper_model_mock=$WhisperModel"
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
        if ($hasExplicitWhisperCLI) {
            $smokeArgs += @("-WhisperCLI", $WhisperCLI)
        }
        if ($hasExplicitWhisperModel) {
            $smokeArgs += @("-WhisperModel", $WhisperModel)
        }
        if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
            $smokeArgs += @("-WhisperOutputDir", $WhisperOutputDir)
        }
        $whisperArguments = @(
            $WhisperArgument |
                Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        )
        if ($whisperArguments.Count -gt 0) {
            $smokeArgs += "-WhisperArgument"
            $smokeArgs += $whisperArguments
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
        if ($RestoreClipboard) {
            $smokeArgs += "-RestoreClipboard"
        }
        if ($NoRestoreClipboard) {
            $smokeArgs += "-NoRestoreClipboard"
        }
        if ($PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")) {
            $smokeArgs += @("-ClipboardRestoreDelaySeconds", "$ClipboardRestoreDelaySeconds")
        }
        if ($RunDictation) {
            $smokeArgs += "-RunDictation"
        }

        & $installedSmoke @smokeArgs
    }

    Invoke-Step "installed launcher doctor" {
        $installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
        Require-File -Path $installedRun
        & $installedRun `
            -InstallDir $InstallDir `
            -ConfigPath $ConfigPath `
            -DoctorOnly
    }
}

if ($CreateShortcut -or $CreateStartupShortcut) {
    Invoke-Step "create user shortcut" {
        if (!$shortcutHasRunnableConfig -and !$AllowSmokeShortcut) {
            throw "Shortcut creation requires cloud Endpoint/Model with ApiKeyEnv/ApiKeyName, local WhisperCLI/WhisperModel, or -SkipSmoke with -ConfigPath"
        }
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            throw "Shortcut creation is only available on Windows"
        }
        $runScript = Join-Path $InstallDir "run-windows-agent.ps1"
        Require-File -Path $runScript

        if ($CreateShortcut) {
            if ([string]::IsNullOrWhiteSpace($ShortcutDir)) {
                $programs = [System.Environment]::GetFolderPath("Programs")
                if ([string]::IsNullOrWhiteSpace($programs)) {
                    throw "Start Menu Programs folder was not found"
                }
                $ShortcutDir = Join-Path $programs "Roma Just Talk"
            }
            $ShortcutDir = Resolve-FullPath -Path $ShortcutDir
            New-Item -ItemType Directory -Force -Path $ShortcutDir | Out-Null

            $shortcutPath = Join-Path $ShortcutDir $ShortcutName
            $savedShortcut = New-AgentShortcut `
                -ShortcutPath $shortcutPath `
                -RunScript $runScript `
                -ConfigPath $ConfigPath `
                -WorkingDirectory $InstallDir `
                -Description "Start roma-just-talk Windows dictation agent"
            Write-Host "shortcut=$shortcutPath"
            Write-Host "shortcut_args=$($savedShortcut.Arguments)"
        }

        if ($CreateStartupShortcut) {
            if ([string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
                $startup = [System.Environment]::GetFolderPath("Startup")
                if ([string]::IsNullOrWhiteSpace($startup)) {
                    throw "Startup folder was not found"
                }
                $StartupShortcutDir = $startup
            }
            $StartupShortcutDir = Resolve-FullPath -Path $StartupShortcutDir
            New-Item -ItemType Directory -Force -Path $StartupShortcutDir | Out-Null

            $startupShortcutPath = Join-Path $StartupShortcutDir $StartupShortcutName
            $savedStartupShortcut = New-AgentShortcut `
                -ShortcutPath $startupShortcutPath `
                -RunScript $runScript `
                -ConfigPath $ConfigPath `
                -WorkingDirectory $InstallDir `
                -Description "Start roma-just-talk Windows dictation agent at login"
            Write-Host "startup_shortcut=$startupShortcutPath"
            Write-Host "startup_shortcut_args=$($savedStartupShortcut.Arguments)"
        }
    }
}

Write-Host ""
$installedSmoke = Join-Path $InstallDir "smoke-windows-agent.ps1"
$installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
Write-Host "installed_agent=$installedAgent"
Write-Host "installed_smoke=$installedSmoke"
Write-Host "installed_run=$installedRun"
Write-Host "config=$ConfigPath"
