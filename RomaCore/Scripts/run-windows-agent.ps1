param(
    [string]$InstallDir = "",
    [string]$AgentPath = "",
    [string]$ConfigPath = "",
    [string]$Endpoint = "",
    [string]$Model = "",
    [string]$ApiKeyEnv = "",
    [string]$ApiKeyName = "",
    [string]$SecretDir = "",
    [string]$Language = "",
    [string]$Prompt = "",
    [string[]]$WordReplacement = @(),
    [switch]$UseHoldHook,
    [switch]$UseToggle,
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$PasteDictation,
    [switch]$NoPaste,
    [switch]$DoctorOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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

if ($UseHoldHook -and $UseToggle) {
    throw "UseHoldHook and UseToggle are mutually exclusive"
}

if ($PasteDictation -and $NoPaste) {
    throw "PasteDictation and NoPaste are mutually exclusive"
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not set; pass -InstallDir explicitly"
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA "roma-just-talk\agent"
}
$InstallDir = Resolve-FullPath -Path $InstallDir

if ([string]::IsNullOrWhiteSpace($AgentPath)) {
    $AgentPath = Join-Path $InstallDir "RomaWindowsAgent.exe"
}
$AgentPath = Resolve-FullPath -Path $AgentPath
Require-File -Path $AgentPath

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

Write-Host "agent_exe=$AgentPath"
Write-Host "config=$ConfigPath"

$doctorOutput = & $AgentPath doctor 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host $doctorOutput
    throw "RomaWindowsAgent doctor failed"
}
Write-Host $doctorOutput
if ($DoctorOnly) {
    exit 0
}

$hasEndpoint = ![string]::IsNullOrWhiteSpace($Endpoint)
$hasModel = ![string]::IsNullOrWhiteSpace($Model)
$hasConfig = Test-Path -LiteralPath $ConfigPath

if ($hasEndpoint -or $hasModel) {
    if (!$hasEndpoint -or !$hasModel) {
        throw "Endpoint and Model must be provided together to write config"
    }

    if (![string]::IsNullOrWhiteSpace($ApiKeyName) -and
        ![string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
        ![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($ApiKeyEnv))) {
        $saveKeyArgs = @(
            "save-key-from-env",
            "--key", $ApiKeyName,
            "--value-env", $ApiKeyEnv,
            "--secret-dir", $SecretDir
        )
        $saveKeyOutput = & $AgentPath @saveKeyArgs 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $saveKeyOutput
            throw "RomaWindowsAgent save-key-from-env failed"
        }
        Write-Host $saveKeyOutput
    }

    $configArgs = @(
        "write-config",
        "--config", $ConfigPath,
        "--endpoint", $Endpoint,
        "--model", $Model
    )
    if ($UseHoldHook -or !$UseToggle) {
        $configArgs += @("--hold-hook", "--timeout", "$HoldTimeoutSeconds")
    } else {
        $configArgs += @("--toggle", "--seconds", "$RecordSeconds")
    }
    if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
        $configArgs += @("--api-key-name", $ApiKeyName, "--secret-dir", $SecretDir)
    } elseif (![string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
        $configArgs += @("--api-key-env", $ApiKeyEnv)
    } else {
        throw "Pass ApiKeyEnv or ApiKeyName when writing config"
    }
    if (![string]::IsNullOrWhiteSpace($Language)) {
        $configArgs += @("--language", $Language)
    }
    if (![string]::IsNullOrWhiteSpace($Prompt)) {
        $configArgs += @("--prompt", $Prompt)
    }
    foreach ($replacement in $WordReplacement) {
        if (![string]::IsNullOrWhiteSpace($replacement)) {
            $configArgs += @("--replace", $replacement)
        }
    }
    if ($PasteDictation) {
        $configArgs += "--paste"
    }
    if ($NoPaste) {
        $configArgs += "--no-paste"
    }

    $configOutput = & $AgentPath @configArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $configOutput
        throw "RomaWindowsAgent write-config failed"
    }
    Write-Host $configOutput
    $hasConfig = $true
}

if (!$hasConfig) {
    throw "Config was not found at $ConfigPath; rerun with Endpoint, Model, and ApiKeyEnv or ApiKeyName"
}

Write-Host "waiting_for_hotkey=Ctrl+Shift+R"
Write-Host "mode=RomaWindowsAgent dictate"
& $AgentPath dictate --config $ConfigPath
if ($LASTEXITCODE -ne 0) {
    throw "RomaWindowsAgent dictate failed"
}
