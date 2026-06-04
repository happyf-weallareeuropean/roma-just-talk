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
    [string]$WhisperCLI = "",
    [string]$WhisperModel = "",
    [string]$WhisperOutputDir = "",
    [string[]]$WhisperArgument = @(),
    [string[]]$WordReplacement = @(),
    [switch]$SkipMic,
    [switch]$RunInteractiveHotkey,
    [switch]$RunInteractiveKeyboardHook,
    [switch]$RunInteractivePaste,
    [switch]$RunNotepadPasteProof,
    [switch]$RunInteractiveDictation,
    [switch]$RunInteractiveWindowsAgent,
    [switch]$UseHoldHook,
    [int]$HoldTimeoutSeconds = 15,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2,
    [double]$PasteFocusDelaySeconds = 5,
    [string]$NotepadPasteProofPath = "",
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

function Wait-ProcessMainWindow {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 10
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process exited before creating a main window: pid=$($Process.Id)"
        }
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            Write-Host "process_window=ready pid=$($Process.Id) handle=$($Process.MainWindowHandle)"
            return
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out waiting for process main window: pid=$($Process.Id)"
}

function Set-ProcessForeground {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 5
    )

    $shell = New-Object -ComObject WScript.Shell
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process exited before activation: pid=$($Process.Id)"
        }
        if ($shell.AppActivate($Process.Id)) {
            Write-Host "process_foreground=activated pid=$($Process.Id)"
            return $shell
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out activating process: pid=$($Process.Id)"
}

function Resolve-SwiftProductExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $binDirLines = @(swift build --show-bin-path)
    if ($LASTEXITCODE -ne 0 -or $binDirLines.Count -eq 0) {
        throw "Could not resolve SwiftPM binary path"
    }

    $binDir = ($binDirLines |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Last 1).Trim()
    $candidates = @(
        (Join-Path $binDir "$Name.exe"),
        (Join-Path $binDir $Name)
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "SwiftPM product executable was not found: $Name in $binDir"
}

function New-WindowsAgentConfigArgs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [string]$OutputPath = ""
    )

    $configArgs = @(
        "run", "RomaWindowsAgent", "write-config",
        "--config", $ConfigPath
    )
    if (![string]::IsNullOrWhiteSpace($OutputPath)) {
        $configArgs += @("--out", $OutputPath)
    }
    if (![string]::IsNullOrWhiteSpace($WhisperCLI)) {
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
        $configArgs += @("--endpoint", $TranscribeEndpoint, "--model", $TranscribeModel)
    }
    if ($UseHoldHook) {
        $configArgs += @("--hold-hook", "--timeout", "$HoldTimeoutSeconds")
    } else {
        $configArgs += @("--toggle", "--seconds", "$RecordSeconds")
    }
    if ([string]::IsNullOrWhiteSpace($WhisperCLI)) {
        if (![string]::IsNullOrWhiteSpace($TranscribeApiKeyName)) {
            $configArgs += @("--api-key-name", $TranscribeApiKeyName, "--secret-dir", $secretProofDir)
        } else {
            $configArgs += @("--api-key-env", $TranscribeApiKeyEnv)
        }
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

if ($NoRestoreClipboard -and $hasExplicitClipboardRestoreDelay) {
    throw "NoRestoreClipboard and ClipboardRestoreDelaySeconds are mutually exclusive"
}

if ($ClipboardRestoreDelaySeconds -lt 0) {
    throw "ClipboardRestoreDelaySeconds must be non-negative"
}

if ($PasteFocusDelaySeconds -lt 0) {
    throw "PasteFocusDelaySeconds must be non-negative"
}

if (![string]::IsNullOrWhiteSpace($NotepadPasteProofPath)) {
    $NotepadPasteProofPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($NotepadPasteProofPath)
}

if ((![string]::IsNullOrWhiteSpace($WhisperCLI) -or
    ![string]::IsNullOrWhiteSpace($WhisperModel)) -and
    (![string]::IsNullOrWhiteSpace($TranscribeEndpoint) -or
    ![string]::IsNullOrWhiteSpace($TranscribeModel) -or
    ![string]::IsNullOrWhiteSpace($TranscribeApiKeyName))) {
    throw "WhisperCLI/WhisperModel and TranscribeEndpoint/TranscribeModel/API-key-name are mutually exclusive for Windows agent config"
}

if ((![string]::IsNullOrWhiteSpace($WhisperCLI) -and [string]::IsNullOrWhiteSpace($WhisperModel)) -or
    ([string]::IsNullOrWhiteSpace($WhisperCLI) -and ![string]::IsNullOrWhiteSpace($WhisperModel))) {
    throw "WhisperCLI and WhisperModel must be provided together"
}

$hasLocalWhisper = ![string]::IsNullOrWhiteSpace($WhisperCLI)

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
        $proofAgentDoctorOutput = swift run RomaProofAgent doctor 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $proofAgentDoctorOutput
            throw "RomaProofAgent doctor failed"
        }
        Write-Host $proofAgentDoctorOutput
        Assert-OutputContains -Output $proofAgentDoctorOutput -Expected "default_record_seconds=2.0"
        Assert-OutputContains -Output $proofAgentDoctorOutput -Expected "default_hold_timeout_seconds=15.0"
        Assert-OutputContains -Output $proofAgentDoctorOutput -Expected "default_hold_timeout_milliseconds=15000"
        Assert-OutputContains -Output $proofAgentDoctorOutput -Expected "default_clipboard_restore_delay_seconds=2.0"
        Assert-OutputContains -Output $proofAgentDoctorOutput -Expected "maximum_clipboard_restore_delay_seconds=4294967.295"
    }

    Invoke-Step "windows agent doctor" {
        $windowsAgentDoctorOutput = swift run RomaWindowsAgent doctor 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $windowsAgentDoctorOutput
            throw "RomaWindowsAgent doctor failed"
        }
        Write-Host $windowsAgentDoctorOutput
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "os_permission_grants=microphone"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "native_capabilities=RegisterHotKey"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "default_record_seconds=2.0"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "default_hold_timeout_seconds=15.0"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "default_hold_timeout_milliseconds=15000"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "default_clipboard_restore_delay_seconds=2.0"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "maximum_clipboard_restore_delay_seconds=4294967.295"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "admin_required=false"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "startup_permission_prompt=false"
        Assert-OutputContains -Output $windowsAgentDoctorOutput -Expected "screen_capture_required=false"
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

    Invoke-Step "whisper.cpp CLI doctor" {
        swift run RomaProofAgent whisper-cli-doctor
    }

    Invoke-Step "whisper.cpp CLI mock proof" {
        swift build --product RomaWhisperCLIMock
        $mockWhisperCLI = Resolve-SwiftProductExecutable -Name "RomaWhisperCLIMock"
        $whisperOutput = swift run RomaProofAgent whisper-cli-proof `
            --audio $coreProof `
            --whisper-cli $mockWhisperCLI `
            --whisper-model $coreProof `
            --language en `
            --prompt "roma just talk" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $whisperOutput
            throw "whisper-cli-proof failed"
        }
        Write-Host $whisperOutput
        Assert-OutputContains -Output $whisperOutput -Expected "provider=whisper.cpp-cli"
        Assert-OutputContains -Output $whisperOutput -Expected "language=en"
        Assert-OutputContains -Output $whisperOutput -Expected "transcript_text=roma just talk local proof"
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
    $hasCloudTranscriptionConfig = ![string]::IsNullOrWhiteSpace($TranscribeEndpoint) -and
        ![string]::IsNullOrWhiteSpace($TranscribeModel) -and
        $hasTranscriptionKey
    $hasWindowsAgentTranscriptionConfig = $hasLocalWhisper -or $hasCloudTranscriptionConfig

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
        $keyboardHookDoctorOutput = swift run RomaProofAgent windows-keyboard-hook-doctor 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $keyboardHookDoctorOutput
            throw "RomaProofAgent windows-keyboard-hook-doctor failed"
        }
        Write-Host $keyboardHookDoctorOutput
        Assert-OutputContains -Output $keyboardHookDoctorOutput -Expected "default_timeout_seconds=15.0"
        Assert-OutputContains -Output $keyboardHookDoctorOutput -Expected "default_timeout_milliseconds=15000"
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
        $pasteDoctorOutput = swift run RomaProofAgent windows-paste-doctor 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $pasteDoctorOutput
            throw "RomaProofAgent windows-paste-doctor failed"
        }
        Write-Host $pasteDoctorOutput
        Assert-OutputContains -Output $pasteDoctorOutput -Expected "default_clipboard_restore_delay_seconds=2.0"
        Assert-OutputContains -Output $pasteDoctorOutput -Expected "maximum_clipboard_restore_delay_seconds=4294967.295"
    }

    Invoke-Step "windows permission doctor" {
        $permissionDoctorOutput = swift run RomaProofAgent windows-permission-doctor 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $permissionDoctorOutput
            throw "RomaProofAgent windows-permission-doctor failed"
        }
        Write-Host $permissionDoctorOutput
        Assert-OutputContains -Output $permissionDoctorOutput -Expected "os_permission_grants=microphone"
        Assert-OutputContains -Output $permissionDoctorOutput -Expected "native_capabilities=RegisterHotKey"
        Assert-OutputContains -Output $permissionDoctorOutput -Expected "admin_required=false"
        Assert-OutputContains -Output $permissionDoctorOutput -Expected "startup_permission_prompt=false"
        Assert-OutputContains -Output $permissionDoctorOutput -Expected "screen_capture_required=false"
    }

    Invoke-Step "windows secret doctor" {
        swift run RomaProofAgent windows-secret-doctor
    }

    Invoke-Step "windows secret proof" {
        swift run RomaProofAgent windows-secret-proof --dir $secretProofDir
    }

    $agentConfig = Join-Path $OutputDir "windows-agent.json"
    if ($hasWindowsAgentTranscriptionConfig) {
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
            if ($hasLocalWhisper) {
                Assert-OutputContains -Output $configOutput -Expected "transcription_client=whisper.cpp-cli"
                Assert-OutputContains -Output $configOutput -Expected "whisper_cli=$WhisperCLI"
            } else {
                Assert-OutputContains -Output $configOutput -Expected "transcription_client=openai-compatible"
                Assert-OutputContains -Output $configOutput -Expected "endpoint=$TranscribeEndpoint"
            }
            Assert-NonEmptyFile -Path $agentConfig
        }
    } else {
        Write-Host ""
        Write-Host "== windows agent config proof skipped =="
        Write-Host "pass local -WhisperCLI and -WhisperModel, or cloud -TranscribeEndpoint, -TranscribeModel, and key args to prove reusable agent config"
    }

    if ($RunInteractivePaste) {
        Invoke-Step "windows paste proof" {
            Write-Host "Focus Notepad or another normal-integrity text field within $PasteFocusDelaySeconds seconds."
            swift run RomaProofAgent windows-paste-proof --text $PasteText --focus-delay $PasteFocusDelaySeconds
        }
    } else {
        Write-Host ""
        Write-Host "== windows paste proof skipped =="
        Write-Host "rerun with -RunInteractivePaste after focusing Notepad"
    }

    if ($RunNotepadPasteProof) {
        Invoke-Step "notepad paste proof" {
            $notepadProofPath = $NotepadPasteProofPath
            if ([string]::IsNullOrWhiteSpace($notepadProofPath)) {
                $notepadProofPath = Join-Path $OutputDir "notepad-paste-proof.txt"
            }
            $notepadParent = Split-Path -Parent $notepadProofPath
            if (![string]::IsNullOrWhiteSpace($notepadParent)) {
                New-Item -ItemType Directory -Force -Path $notepadParent | Out-Null
            }
            Set-Content -LiteralPath $notepadProofPath -Encoding UTF8 -NoNewline -Value ""

            $notepad = Start-Process `
                -FilePath "notepad.exe" `
                -ArgumentList @("`"$notepadProofPath`"") `
                -PassThru

            try {
                Wait-ProcessMainWindow -Process $notepad
                $pasteOutput = swift run RomaProofAgent windows-paste-proof `
                    --text $PasteText `
                    --target-process-id $notepad.Id 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Write-Host $pasteOutput
                    throw "windows-paste-proof failed for Notepad"
                }
                Write-Host $pasteOutput
                Assert-OutputContains -Output $pasteOutput -Expected "target_process_id=$($notepad.Id)"
                Assert-OutputContains -Output $pasteOutput -Expected "paste_sent=true"

                $shell = Set-ProcessForeground -Process $notepad
                $shell.SendKeys("^s")
                Start-Sleep -Milliseconds 750

                $savedText = Get-Content -LiteralPath $notepadProofPath -Raw
                if (!$savedText.Contains($PasteText)) {
                    throw "Notepad file did not contain pasted proof text: $notepadProofPath"
                }

                Write-Host "notepad_paste_file=$notepadProofPath"
                Write-Host "notepad_paste_verified=true"
            } finally {
                if ($null -ne $notepad) {
                    $notepad.Refresh()
                    if (!$notepad.HasExited) {
                        $null = $notepad.CloseMainWindow()
                        Start-Sleep -Milliseconds 500
                        $notepad.Refresh()
                    }
                    if (!$notepad.HasExited) {
                        Stop-Process -Id $notepad.Id -Force
                    }
                }
            }
        }
    } else {
        Write-Host ""
        Write-Host "== notepad paste proof skipped =="
        Write-Host "rerun with -RunNotepadPasteProof to verify text lands in a saved Notepad file"
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
        Write-Host "rerun with -RunInteractiveDictation and cloud transcription args to prove proof-agent hotkey -> pre-roll WAV -> STT"
    }

    if ($RunInteractiveWindowsAgent) {
        if (!$hasWindowsAgentTranscriptionConfig) {
            throw "RunInteractiveWindowsAgent requires local -WhisperCLI and -WhisperModel, or cloud -TranscribeEndpoint, -TranscribeModel, and key args"
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
            if ($hasLocalWhisper) {
                Assert-OutputContains -Output $configOutput -Expected "transcription_client=whisper.cpp-cli"
            } else {
                Assert-OutputContains -Output $configOutput -Expected "transcription_client=openai-compatible"
            }
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
        Write-Host "rerun with -RunInteractiveWindowsAgent and local or cloud transcription args to prove the user-facing Windows agent"
    }

    Write-Host ""
    Write-Host "proof_artifacts=$OutputDir"
} finally {
    Pop-Location
}
