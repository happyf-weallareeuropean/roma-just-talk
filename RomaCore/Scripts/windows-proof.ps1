param(
    [string]$OutputDir = "$PSScriptRoot\..\proof-artifacts\windows",
    [int]$RecordSeconds = 2,
    [string]$PasteText = "roma just talk proof",
    [string]$TranscribeAudio = "",
    [string]$TranscribeEndpoint = "",
    [string]$TranscribeModel = "",
    [string]$TranscribeApiKeyEnv = "OPENAI_API_KEY",
    [string]$TranscribeApiKeyName = "",
    [string]$TranscribeLanguage = "",
    [string]$TranscribePrompt = "",
    [string[]]$WordReplacement = @(),
    [switch]$SkipMic,
    [switch]$RunInteractiveHotkey,
    [switch]$RunInteractiveKeyboardHook,
    [switch]$RunInteractivePaste,
    [switch]$RunInteractiveDictation,
    [switch]$RunInteractiveWindowsAgent,
    [switch]$UseHoldHook,
    [int]$HoldTimeoutSeconds = 15,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2,
    [switch]$PasteDictation
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

function Assert-FileWithBytes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Expected file was not created: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 44) {
        throw "Expected WAV payload larger than header: $Path bytes=$($item.Length)"
    }

    Write-Host "file=$Path"
    Write-Host "bytes=$($item.Length)"
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

function New-WindowsAgentConfigArgs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [string]$OutputPath = ""
    )

    $configArgs = @(
        "run", "RomaWindowsAgent", "write-config",
        "--config", $ConfigPath,
        "--endpoint", $TranscribeEndpoint,
        "--model", $TranscribeModel
    )
    if (![string]::IsNullOrWhiteSpace($OutputPath)) {
        $configArgs += @("--out", $OutputPath)
    }
    if ($UseHoldHook) {
        $configArgs += @("--hold-hook", "--timeout", "$HoldTimeoutSeconds")
    } else {
        $configArgs += @("--toggle", "--seconds", "$RecordSeconds")
    }
    if (![string]::IsNullOrWhiteSpace($TranscribeApiKeyName)) {
        $configArgs += @("--api-key-name", $TranscribeApiKeyName, "--secret-dir", $secretProofDir)
    } else {
        $configArgs += @("--api-key-env", $TranscribeApiKeyEnv)
    }
    if (![string]::IsNullOrWhiteSpace($TranscribeLanguage)) {
        $configArgs += @("--language", $TranscribeLanguage)
    }
    if (![string]::IsNullOrWhiteSpace($TranscribePrompt)) {
        $configArgs += @("--prompt", $TranscribePrompt)
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

    return $configArgs
}

if ($RestoreClipboard -and $NoRestoreClipboard) {
    throw "RestoreClipboard and NoRestoreClipboard are mutually exclusive"
}

if ($ClipboardRestoreDelaySeconds -lt 0) {
    throw "ClipboardRestoreDelaySeconds must be non-negative"
}

$packageRoot = Resolve-Path "$PSScriptRoot\.."
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $packageRoot
try {
    Invoke-Step "swift version" {
        swift --version
    }

    Invoke-Step "build" {
        swift build
    }

    Invoke-Step "core checks" {
        swift run RomaCoreChecks
    }

    Invoke-Step "agent doctor" {
        swift run RomaProofAgent doctor
    }

    Invoke-Step "windows agent doctor" {
        swift run RomaWindowsAgent doctor
    }

    $coreProof = Join-Path $OutputDir "core-proof.wav"
    Invoke-Step "core pre-roll wav proof" {
        swift run RomaProofAgent pre-roll-proof --out $coreProof
        Assert-FileWithBytes -Path $coreProof
    }

    Invoke-Step "miniaudio capture doctor" {
        swift run RomaProofAgent miniaudio-capture-doctor
    }

    $micProof = Join-Path $OutputDir "mic-proof.wav"
    if ($SkipMic) {
        Write-Host ""
        Write-Host "== miniaudio mic proof skipped =="
    } else {
        Invoke-Step "miniaudio mic proof" {
            swift run RomaProofAgent miniaudio-record-proof --out $micProof --seconds $RecordSeconds
            Assert-FileWithBytes -Path $micProof
        }
    }

    Invoke-Step "transcription doctor" {
        swift run RomaProofAgent transcribe-proof-doctor
    }

    $pipelineProof = Join-Path $OutputDir "pipeline-proof.wav"
    Invoke-Step "dictation pipeline cleanup proof" {
        $pipelineOutput = swift run RomaProofAgent dictation-pipeline-proof `
            --out $pipelineProof `
            --text "hmm... just talk." `
            --replace "just talk=roma-just-talk" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $pipelineOutput
            throw "dictation-pipeline-proof failed"
        }
        Write-Host $pipelineOutput
        Assert-FileWithBytes -Path $pipelineProof
        Assert-OutputContains -Output $pipelineOutput -Expected "raw_transcript_text=hmm... just talk."
        Assert-OutputContains -Output $pipelineOutput -Expected "processed_transcript_text=roma-just-talk"
        Assert-OutputContains -Output $pipelineOutput -Expected "word_replacements=1"
        Assert-OutputContains -Output $pipelineOutput -Expected "fake_paste_text=roma-just-talk"
        Assert-OutputContains -Output $pipelineOutput -Expected "paste_text_source=processed_transcript"
    }

    $transcribeAudioPath = $TranscribeAudio
    if ([string]::IsNullOrWhiteSpace($transcribeAudioPath) -and !$SkipMic) {
        $transcribeAudioPath = $micProof
    }

    $secretProofDir = Join-Path $OutputDir "secrets"
    $transcribeApiKeyEnvValue = if ([string]::IsNullOrWhiteSpace($TranscribeApiKeyEnv)) {
        ""
    } else {
        [Environment]::GetEnvironmentVariable($TranscribeApiKeyEnv)
    }
    $hasTranscriptionKey = ![string]::IsNullOrWhiteSpace($transcribeApiKeyEnvValue) -or
        ![string]::IsNullOrWhiteSpace($TranscribeApiKeyName)

    if (![string]::IsNullOrWhiteSpace($TranscribeApiKeyName) -and
        ![string]::IsNullOrWhiteSpace($transcribeApiKeyEnvValue)) {
        Invoke-Step "store transcription api key" {
            swift run RomaProofAgent windows-secret-save-from-env --dir $secretProofDir --key $TranscribeApiKeyName --value-env $TranscribeApiKeyEnv
        }
    }

    if (![string]::IsNullOrWhiteSpace($TranscribeEndpoint) -and
        ![string]::IsNullOrWhiteSpace($TranscribeModel) -and
        $hasTranscriptionKey -and
        ![string]::IsNullOrWhiteSpace($transcribeAudioPath)) {
        Invoke-Step "transcription proof" {
            $transcribeArgs = @(
                "run", "RomaProofAgent", "transcribe-proof",
                "--audio", $transcribeAudioPath,
                "--endpoint", $TranscribeEndpoint,
                "--model", $TranscribeModel
            )
            if (![string]::IsNullOrWhiteSpace($TranscribeApiKeyName)) {
                $transcribeArgs += @("--api-key-name", $TranscribeApiKeyName, "--secret-dir", $secretProofDir)
            } else {
                $transcribeArgs += @("--api-key-env", $TranscribeApiKeyEnv)
            }
            if (![string]::IsNullOrWhiteSpace($TranscribeLanguage)) {
                $transcribeArgs += @("--language", $TranscribeLanguage)
            }
            if (![string]::IsNullOrWhiteSpace($TranscribePrompt)) {
                $transcribeArgs += @("--prompt", $TranscribePrompt)
            }
            swift @transcribeArgs
        }
    } else {
        Write-Host ""
        Write-Host "== transcription proof skipped =="
        Write-Host "pass -TranscribeEndpoint, -TranscribeModel, and -TranscribeApiKeyEnv or -TranscribeApiKeyName; use -TranscribeAudio when -SkipMic is set"
    }

    Invoke-Step "windows hotkey doctor" {
        swift run RomaProofAgent windows-hotkey-doctor
    }

    if ($RunInteractiveHotkey) {
        Invoke-Step "windows hotkey proof" {
            Write-Host "Press Ctrl+Shift+R in this session to complete the proof."
            swift run RomaProofAgent windows-hotkey-proof
        }
    } else {
        Write-Host ""
        Write-Host "== windows hotkey proof skipped =="
        Write-Host "rerun with -RunInteractiveHotkey, then press Ctrl+Shift+R"
    }

    Invoke-Step "windows keyboard hook doctor" {
        swift run RomaProofAgent windows-keyboard-hook-doctor
    }

    if ($RunInteractiveKeyboardHook) {
        Invoke-Step "windows keyboard hook proof" {
            Write-Host "Press and release Ctrl+Shift+R in this session to complete the low-level hook proof."
            swift run RomaProofAgent windows-keyboard-hook-proof --timeout 15
        }
    } else {
        Write-Host ""
        Write-Host "== windows keyboard hook proof skipped =="
        Write-Host "rerun with -RunInteractiveKeyboardHook, then press and release Ctrl+Shift+R"
    }

    Invoke-Step "windows paste doctor" {
        swift run RomaProofAgent windows-paste-doctor
    }

    Invoke-Step "windows permission doctor" {
        swift run RomaProofAgent windows-permission-doctor
    }

    Invoke-Step "windows secret doctor" {
        swift run RomaProofAgent windows-secret-doctor
    }

    Invoke-Step "windows secret proof" {
        swift run RomaProofAgent windows-secret-proof --dir $secretProofDir
    }

    $agentConfig = Join-Path $OutputDir "windows-agent.json"
    if (![string]::IsNullOrWhiteSpace($TranscribeEndpoint) -and
        ![string]::IsNullOrWhiteSpace($TranscribeModel) -and
        $hasTranscriptionKey) {
        Invoke-Step "windows agent config proof" {
            $agentConfigArgs = New-WindowsAgentConfigArgs -ConfigPath $agentConfig
            $configOutput = swift @agentConfigArgs 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                Write-Host $configOutput
                throw "RomaWindowsAgent write-config failed"
            }
            Write-Host $configOutput
            Assert-OutputContains -Output $configOutput -Expected "written=true"
            Assert-OutputContains -Output $configOutput -Expected "config=$agentConfig"
            Assert-NonEmptyFile -Path $agentConfig
        }
    } else {
        Write-Host ""
        Write-Host "== windows agent config proof skipped =="
        Write-Host "pass -TranscribeEndpoint, -TranscribeModel, and -TranscribeApiKeyEnv or -TranscribeApiKeyName to prove reusable agent config"
    }

    if ($RunInteractivePaste) {
        Invoke-Step "windows paste proof" {
            Write-Host "Focus Notepad or another normal-integrity text field before this step."
            swift run RomaProofAgent windows-paste-proof --text $PasteText
        }
    } else {
        Write-Host ""
        Write-Host "== windows paste proof skipped =="
        Write-Host "rerun with -RunInteractivePaste after focusing Notepad"
    }

    if ($RunInteractiveDictation) {
        if ([string]::IsNullOrWhiteSpace($TranscribeEndpoint) -or
            [string]::IsNullOrWhiteSpace($TranscribeModel) -or
            !$hasTranscriptionKey) {
            throw "RunInteractiveDictation requires -TranscribeEndpoint, -TranscribeModel, and -TranscribeApiKeyEnv or -TranscribeApiKeyName"
        }

        $dictationProof = Join-Path $OutputDir "dictation-proof.wav"
        Invoke-Step "windows dictation proof" {
            if ($UseHoldHook) {
                Write-Host "Say a phrase before Ctrl+Shift+R, hold Ctrl+Shift+R while speaking, then release it."
            } else {
                Write-Host "Say a phrase before Ctrl+Shift+R, press Ctrl+Shift+R, then say a phrase after it."
            }
            if ($PasteDictation) {
                Write-Host "Focus Notepad or another normal-integrity text field before transcription completes."
            }
            $dictationArgs = @(
                "run", "RomaProofAgent", "windows-dictation-proof",
                "--out", $dictationProof,
                "--seconds", "$RecordSeconds",
                "--endpoint", $TranscribeEndpoint,
                "--model", $TranscribeModel
            )
            if ($UseHoldHook) {
                $dictationArgs += @("--hold-hook", "--timeout", "$HoldTimeoutSeconds")
            }
            if (![string]::IsNullOrWhiteSpace($TranscribeApiKeyName)) {
                $dictationArgs += @("--api-key-name", $TranscribeApiKeyName, "--secret-dir", $secretProofDir)
            } else {
                $dictationArgs += @("--api-key-env", $TranscribeApiKeyEnv)
            }
            if (![string]::IsNullOrWhiteSpace($TranscribeLanguage)) {
                $dictationArgs += @("--language", $TranscribeLanguage)
            }
            if (![string]::IsNullOrWhiteSpace($TranscribePrompt)) {
                $dictationArgs += @("--prompt", $TranscribePrompt)
            }
            foreach ($replacement in $WordReplacement) {
                if (![string]::IsNullOrWhiteSpace($replacement)) {
                    $dictationArgs += @("--replace", $replacement)
                }
            }
            if ($PasteDictation) {
                $dictationArgs += "--paste"
            }
            swift @dictationArgs
            Assert-FileWithBytes -Path $dictationProof
        }
    } else {
        Write-Host ""
        Write-Host "== windows dictation proof skipped =="
        Write-Host "rerun with -RunInteractiveDictation and transcription args to prove hotkey -> pre-roll WAV -> STT"
    }

    if ($RunInteractiveWindowsAgent) {
        if ([string]::IsNullOrWhiteSpace($TranscribeEndpoint) -or
            [string]::IsNullOrWhiteSpace($TranscribeModel) -or
            !$hasTranscriptionKey) {
            throw "RunInteractiveWindowsAgent requires -TranscribeEndpoint, -TranscribeModel, and -TranscribeApiKeyEnv or -TranscribeApiKeyName"
        }

        $agentProof = Join-Path $OutputDir "windows-agent-dictation.wav"
        Invoke-Step "windows agent dictate" {
            if ($UseHoldHook) {
                Write-Host "Say a phrase before Ctrl+Shift+R, hold Ctrl+Shift+R while speaking, then release it."
            } else {
                Write-Host "Say a phrase before Ctrl+Shift+R, press Ctrl+Shift+R, then say a phrase after it."
            }
            if ($PasteDictation) {
                Write-Host "Focus Notepad or another normal-integrity text field before transcription completes."
            }
            $agentConfigArgs = New-WindowsAgentConfigArgs -ConfigPath $agentConfig -OutputPath $agentProof
            $configOutput = swift @agentConfigArgs 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                Write-Host $configOutput
                throw "RomaWindowsAgent write-config failed"
            }
            Write-Host $configOutput
            Assert-OutputContains -Output $configOutput -Expected "written=true"
            Assert-NonEmptyFile -Path $agentConfig

            $agentArgs = @(
                "run", "RomaWindowsAgent", "dictate",
                "--config", $agentConfig
            )
            swift @agentArgs
            Assert-FileWithBytes -Path $agentProof
        }
    } else {
        Write-Host ""
        Write-Host "== windows agent dictate skipped =="
        Write-Host "rerun with -RunInteractiveWindowsAgent and transcription args to prove the user-facing Windows agent"
    }

    Write-Host ""
    Write-Host "proof_artifacts=$OutputDir"
} finally {
    Pop-Location
}
