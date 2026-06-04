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
    [switch]$RunDictation
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")

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

function Assert-JsonPropertyEquals {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [object]$Expected
    )

    if (!($Object.PSObject.Properties.Name -contains $Name)) {
        throw "Expected JSON property '$Name' was not found"
    }

    $actual = $Object.$Name
    if ($actual -ne $Expected) {
        throw "Expected JSON property '$Name' to equal '$Expected', got '$actual'"
    }

    Write-Host "asserted_json=$Name"
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

if ($RestoreClipboard -and $NoRestoreClipboard) {
    throw "RestoreClipboard and NoRestoreClipboard are mutually exclusive"
}

if ($NoRestoreClipboard -and $hasExplicitClipboardRestoreDelay) {
    throw "NoRestoreClipboard and ClipboardRestoreDelaySeconds are mutually exclusive"
}

if ($ClipboardRestoreDelaySeconds -lt 0) {
    throw "ClipboardRestoreDelaySeconds must be non-negative"
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

$hasExplicitApiKeyEnv = $PSBoundParameters.ContainsKey("ApiKeyEnv")
$apiKeyEnvValue = if ([string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
    ""
} else {
    [Environment]::GetEnvironmentVariable($ApiKeyEnv)
}
$hasWhisperCLI = ![string]::IsNullOrWhiteSpace($WhisperCLI)
$hasWhisperModel = ![string]::IsNullOrWhiteSpace($WhisperModel)
$usesWhisperCLI = $hasWhisperCLI -or $hasWhisperModel

if ($usesWhisperCLI -and (!$hasWhisperCLI -or !$hasWhisperModel)) {
    throw "WhisperCLI and WhisperModel must be provided together"
}

if ($RunDictation -and !$usesWhisperCLI -and
    [string]::IsNullOrWhiteSpace($ApiKeyName) -and
    (!$hasExplicitApiKeyEnv -or [string]::IsNullOrWhiteSpace($apiKeyEnvValue))) {
    throw "RunDictation requires -ApiKeyEnv with a set environment variable, or pass -ApiKeyName with a saved key"
}

$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$shouldUseHoldHook = $UseHoldHook -or !$UseToggle
$dictationOutput = Join-Path $OutputDir "windows-agent-smoke.wav"
$dictationLog = Join-Path $OutputDir "windows-agent-dictate.log"

Invoke-Step "agent doctor" {
    $doctorOutput = & $AgentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $doctorOutput
        throw "RomaWindowsAgent doctor failed"
    }
    Write-Host $doctorOutput
    Assert-OutputContains -Output $doctorOutput -Expected "agent=roma-windows-agent"
    Assert-OutputContains -Output $doctorOutput -Expected "os_permission_grants=microphone"
    Assert-OutputContains -Output $doctorOutput -Expected "native_capabilities=RegisterHotKey"
    Assert-OutputContains -Output $doctorOutput -Expected "default_record_seconds=2.0"
    Assert-OutputContains -Output $doctorOutput -Expected "default_hold_timeout_seconds=15.0"
    Assert-OutputContains -Output $doctorOutput -Expected "default_hold_timeout_milliseconds=15000"
    Assert-OutputContains -Output $doctorOutput -Expected "default_clipboard_restore_delay_seconds=2.0"
    Assert-OutputContains -Output $doctorOutput -Expected "maximum_clipboard_restore_delay_seconds=4294967.295"
    Assert-OutputContains -Output $doctorOutput -Expected "admin_required=false"
    Assert-OutputContains -Output $doctorOutput -Expected "startup_launcher=run-windows-agent.ps1"
    Assert-OutputContains -Output $doctorOutput -Expected "startup_launch_mode=listen"
    Assert-OutputContains -Output $doctorOutput -Expected "startup_permission_prompt=false"
    Assert-OutputContains -Output $doctorOutput -Expected "screen_capture_required=false"
    if ($isWindowsHost) {
        Assert-OutputContains -Output $doctorOutput -Expected "runtime_available=true"
    }
}

if (![string]::IsNullOrWhiteSpace($ApiKeyName) -and
    $hasExplicitApiKeyEnv -and
    ![string]::IsNullOrWhiteSpace($apiKeyEnvValue)) {
    Invoke-Step "agent save key" {
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
        Assert-OutputContains -Output $saveKeyOutput -Expected "stored=true"
        Assert-OutputContains -Output $saveKeyOutput -Expected "key=$ApiKeyName"
    }
} elseif ($RunDictation -and ![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    Write-Host ""
    Write-Host "== agent save key skipped =="
    Write-Host "using existing stored key '$ApiKeyName' from $SecretDir"
}

Invoke-Step "agent config" {
    $configArgs = @(
        "write-config",
        "--config", $ConfigPath,
        "--out", $dictationOutput
    )
    if ($usesWhisperCLI) {
        $configArgs += @("--whisper-cli", $WhisperCLI, "--whisper-model", $WhisperModel)
        if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
            $configArgs += @("--whisper-output-dir", $WhisperOutputDir)
        }
        foreach ($argument in $WhisperArgument) {
            if (![string]::IsNullOrWhiteSpace($argument)) {
                $configArgs += @("--whisper-arg", $argument)
            }
        }
    } else {
        $configArgs += @("--endpoint", $Endpoint, "--model", $Model)
    }
    if ($shouldUseHoldHook) {
        $configArgs += @("--hold-hook", "--timeout", "$HoldTimeoutSeconds")
    } else {
        $configArgs += @("--toggle", "--seconds", "$RecordSeconds")
    }
    if (!$usesWhisperCLI) {
        if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
            $configArgs += @("--api-key-name", $ApiKeyName, "--secret-dir", $SecretDir)
        } else {
            $configArgs += @("--api-key-env", $ApiKeyEnv)
        }
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
    if ($RestoreClipboard) {
        $configArgs += "--restore-clipboard"
    }
    if ($NoRestoreClipboard) {
        $configArgs += "--no-restore-clipboard"
    }
    if ($hasExplicitClipboardRestoreDelay) {
        $configArgs += @("--clipboard-restore-delay", "$ClipboardRestoreDelaySeconds")
    }

    $configOutput = & $AgentPath @configArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $configOutput
        throw "RomaWindowsAgent write-config failed"
    }
    Write-Host $configOutput
    Assert-OutputContains -Output $configOutput -Expected "written=true"
    Assert-OutputContains -Output $configOutput -Expected "config=$ConfigPath"
    Assert-OutputContains -Output $configOutput -Expected "restore_clipboard_after_paste="
    Assert-OutputContains -Output $configOutput -Expected "clipboard_restore_delay_seconds="
    Assert-NonEmptyFile -Path $ConfigPath

    $configJson = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($usesWhisperCLI) {
        Assert-JsonPropertyEquals -Object $configJson -Name "whisperCLIPath" -Expected $WhisperCLI
        Assert-JsonPropertyEquals -Object $configJson -Name "whisperModelPath" -Expected $WhisperModel
    } else {
        Assert-JsonPropertyEquals -Object $configJson -Name "endpoint" -Expected $Endpoint
        Assert-JsonPropertyEquals -Object $configJson -Name "model" -Expected $Model
    }
    Assert-JsonPropertyEquals -Object $configJson -Name "outputPath" -Expected $dictationOutput
    Assert-JsonPropertyEquals -Object $configJson -Name "usesHoldHook" -Expected $shouldUseHoldHook
    if ($PasteDictation) {
        Assert-JsonPropertyEquals -Object $configJson -Name "shouldPaste" -Expected $true
    }
    if ($RestoreClipboard) {
        Assert-JsonPropertyEquals -Object $configJson -Name "restoreClipboardAfterPaste" -Expected $true
    }
    if ($NoRestoreClipboard) {
        Assert-JsonPropertyEquals -Object $configJson -Name "restoreClipboardAfterPaste" -Expected $false
    }
    if ($hasExplicitClipboardRestoreDelay) {
        Assert-JsonPropertyEquals `
            -Object $configJson `
            -Name "clipboardRestoreDelaySeconds" `
            -Expected $ClipboardRestoreDelaySeconds
    }
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

        $dictateOutput = & $AgentPath dictate --config $ConfigPath 2>&1 | Out-String
        Write-Host $dictateOutput
        Set-Content -LiteralPath $dictationLog -Value $dictateOutput -Encoding UTF8
        if ($LASTEXITCODE -ne 0) {
            throw "RomaWindowsAgent dictate failed"
        }
        Assert-WavFileWithBytes -Path $dictationOutput
        Assert-NonEmptyFile -Path $dictationLog
        Assert-OutputContains -Output $dictateOutput -Expected "wrote="
        Assert-OutputContains -Output $dictateOutput -Expected "included_pre_roll_seconds="
        Assert-OutputContains -Output $dictateOutput -Expected "processed_transcript_text="
        if ($PasteDictation) {
            Assert-OutputContains -Output $dictateOutput -Expected "paste_sent=true"
        } else {
            Assert-OutputContains -Output $dictateOutput -Expected "paste_sent=false"
        }
    }
} else {
    Write-Host ""
    Write-Host "== agent dictate skipped =="
    Write-Host "rerun with -RunDictation after setting a real transcription endpoint and API key"
}

Write-Host ""
Write-Host "agent_exe=$AgentPath"
Write-Host "config=$ConfigPath"
if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    Write-Host "secret_dir=$SecretDir"
    Write-Host "api_key_name=$ApiKeyName"
}
Write-Host "smoke_artifacts=$OutputDir"
Write-Host "run_dictation=$($RunDictation.IsPresent)"
if ($RunDictation) {
    Write-Host "dictation_log=$dictationLog"
}
