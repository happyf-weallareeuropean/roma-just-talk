param(
    [string]$PackageDir = "",
    [string]$AgentPath = "",
    [string]$OutputDir = "",
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
    [switch]$RunDictation
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

function Assert-OutputContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Expected
    )

    if (!$Output.Contains($Expected)) {
        throw "Expected command output to contain '$Expected'"
    }

    Write-Host "asserted_output=$Expected"
}

function Assert-NonEmptyFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Expected file was not created: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) {
        throw "Expected non-empty file: $Path"
    }

    Write-Host "file=$Path"
    Write-Host "bytes=$($item.Length)"
}

function Assert-WavFileWithBytes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Assert-NonEmptyFile -Path $Path
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 44) {
        throw "Expected WAV payload larger than header: $Path bytes=$($item.Length)"
    }
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

if ($UseHoldHook -and $UseToggle) {
    throw "UseHoldHook and UseToggle are mutually exclusive"
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $PSScriptRoot
}
$PackageDir = Resolve-FullPath -Path $PackageDir

if ([string]::IsNullOrWhiteSpace($AgentPath)) {
    $AgentPath = Join-Path $PackageDir "RomaWindowsAgent.exe"
}
$AgentPath = Resolve-FullPath -Path $AgentPath

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path (Split-Path -Parent $AgentPath) "smoke"
}
$OutputDir = Resolve-FullPath -Path $OutputDir
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $OutputDir "windows-agent-smoke.json"
}
$ConfigPath = Resolve-FullPath -Path $ConfigPath

if ([string]::IsNullOrWhiteSpace($SecretDir) -and
    ![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    $SecretDir = Join-Path $OutputDir "secrets"
}
if (![string]::IsNullOrWhiteSpace($SecretDir)) {
    $SecretDir = Resolve-FullPath -Path $SecretDir
}

if (!(Test-Path -LiteralPath $AgentPath)) {
    throw "RomaWindowsAgent.exe was not found: $AgentPath"
}

if ($RunDictation -and [string]::IsNullOrWhiteSpace($ApiKeyName)) {
    $apiKeyValue = [Environment]::GetEnvironmentVariable($ApiKeyEnv)
    if ([string]::IsNullOrWhiteSpace($apiKeyValue)) {
        throw "RunDictation requires $ApiKeyEnv to be set, or pass -ApiKeyName with a saved key"
    }
}

$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$shouldUseHoldHook = $UseHoldHook -or !$UseToggle
$dictationOutput = Join-Path $OutputDir "windows-agent-smoke.wav"

Invoke-Step "agent doctor" {
    $doctorOutput = & $AgentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $doctorOutput
        throw "RomaWindowsAgent doctor failed"
    }
    Write-Host $doctorOutput
    Assert-OutputContains -Output $doctorOutput -Expected "agent=roma-windows-agent"
    if ($isWindowsHost) {
        Assert-OutputContains -Output $doctorOutput -Expected "runtime_available=true"
    }
}

Invoke-Step "agent config" {
    $configArgs = @(
        "write-config",
        "--config", $ConfigPath,
        "--endpoint", $Endpoint,
        "--model", $Model,
        "--out", $dictationOutput
    )
    if ($shouldUseHoldHook) {
        $configArgs += @("--hold-hook", "--timeout", "$HoldTimeoutSeconds")
    } else {
        $configArgs += @("--toggle", "--seconds", "$RecordSeconds")
    }
    if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
        $configArgs += @("--api-key-name", $ApiKeyName, "--secret-dir", $SecretDir)
    } else {
        $configArgs += @("--api-key-env", $ApiKeyEnv)
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

    $configOutput = & $AgentPath @configArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $configOutput
        throw "RomaWindowsAgent write-config failed"
    }
    Write-Host $configOutput
    Assert-OutputContains -Output $configOutput -Expected "written=true"
    Assert-OutputContains -Output $configOutput -Expected "config=$ConfigPath"
    Assert-NonEmptyFile -Path $ConfigPath
}

if ($RunDictation) {
    Invoke-Step "agent dictate" {
        if ($shouldUseHoldHook) {
            Write-Host "Say a phrase before Ctrl+Shift+R, hold Ctrl+Shift+R while speaking, then release it."
        } else {
            Write-Host "Say a phrase before Ctrl+Shift+R, press Ctrl+Shift+R, then say a phrase after it."
        }
        if ($PasteDictation) {
            Write-Host "Focus Notepad or another normal-integrity text field before transcription completes."
        }

        & $AgentPath dictate --config $ConfigPath
        if ($LASTEXITCODE -ne 0) {
            throw "RomaWindowsAgent dictate failed"
        }
        Assert-WavFileWithBytes -Path $dictationOutput
    }
} else {
    Write-Host ""
    Write-Host "== agent dictate skipped =="
    Write-Host "rerun with -RunDictation after setting a real transcription endpoint and API key"
}

Write-Host ""
Write-Host "agent_exe=$AgentPath"
Write-Host "config=$ConfigPath"
Write-Host "smoke_artifacts=$OutputDir"
Write-Host "run_dictation=$($RunDictation.IsPresent)"
