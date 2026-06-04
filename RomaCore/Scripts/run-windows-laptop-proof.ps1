param(
    [string]$PackageDir = "",
    [string]$ProofDir = "",
    [string]$Endpoint = "",
    [string]$Model = "",
    [string]$ApiKeyEnv = "",
    [string]$ApiKeyName = "",
    [string]$SecretDir = "",
    [string]$WhisperCLI = "",
    [string]$WhisperModel = "",
    [string]$WhisperOutputDir = "",
    [string[]]$WhisperArgument = @(),
    [string]$Language = "",
    [string]$Prompt = "",
    [string[]]$WordReplacement = @("just talk=roma-just-talk"),
    [string]$CloudExpectedTranscriptText = "cloud pre roll proof",
    [string]$LocalWhisperExpectedTranscriptText = "local whisper pre roll proof",
    [string]$StartupShortcutDir = "",
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2
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

function Write-HoldDictationPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$ExpectedTranscriptText = ""
    )

    Write-Host ""
    Write-Host "ACTION_REQUIRED=$Name"
    Write-Host "focus_target=normal_text_field_or_notepad"
    if (![string]::IsNullOrWhiteSpace($ExpectedTranscriptText)) {
        Write-Host "say_expected_phrase_before_hotkey=$ExpectedTranscriptText"
    }
    Write-Host "hold_hotkey=Ctrl+Shift+R"
    Write-Host "speak_before_pressing_hotkey=true"
    Write-Host "release_hotkey_to_finish=true"
    Write-Host "hold_timeout_seconds=$HoldTimeoutSeconds"
}

function Write-NotepadPastePrompt {
    Write-Host ""
    Write-Host "ACTION_REQUIRED=local_whisper_notepad_paste"
    Write-Host "notepad=will_open_and_verify_file"
    Write-Host "manual_focus_required=false"
}

function Add-CommonProofArgs {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ArgumentList
    )

    if (![string]::IsNullOrWhiteSpace($Language)) {
        $ArgumentList += @("-Language", $Language)
    }
    if (![string]::IsNullOrWhiteSpace($Prompt)) {
        $ArgumentList += @("-Prompt", $Prompt)
    }

    $replacementValues = @(
        $WordReplacement |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    )
    if ($replacementValues.Count -gt 0) {
        $ArgumentList += "-WordReplacement"
        $ArgumentList += $replacementValues
    }

    $ArgumentList += @("-UseHoldHook")
    $ArgumentList += @("-HoldTimeoutSeconds", "$HoldTimeoutSeconds")
    $ArgumentList += @("-RecordSeconds", "$RecordSeconds")
    if ($RestoreClipboard) {
        $ArgumentList += "-RestoreClipboard"
    }
    if ($NoRestoreClipboard) {
        $ArgumentList += "-NoRestoreClipboard"
    }
    $ArgumentList += @("-ClipboardRestoreDelaySeconds", "$ClipboardRestoreDelaySeconds")

    return $ArgumentList
}

function Add-ShortcutProofArgs {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ArgumentList,
        [Parameter(Mandatory = $true)]
        [string]$ShortcutDir,
        [string]$StartupDir = ""
    )

    $ArgumentList += @(
        "-CreateShortcut",
        "-ShortcutDir", $ShortcutDir,
        "-CreateStartupShortcut"
    )
    if (![string]::IsNullOrWhiteSpace($StartupDir)) {
        $ArgumentList += @("-StartupShortcutDir", $StartupDir)
    }

    return $ArgumentList
}

if ($RestoreClipboard -and $NoRestoreClipboard) {
    throw "RestoreClipboard and NoRestoreClipboard are mutually exclusive"
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "Windows laptop proof must run on Windows"
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $PSScriptRoot
}
$PackageDir = Resolve-FullPath -Path $PackageDir

if ([string]::IsNullOrWhiteSpace($ProofDir)) {
    $ProofDir = Join-Path ([System.IO.Path]::GetTempPath()) "roma-windows-laptop-proof"
}
$ProofDir = Resolve-FullPath -Path $ProofDir
New-Item -ItemType Directory -Force -Path $ProofDir | Out-Null
if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
    $StartupShortcutDir = Resolve-FullPath -Path $StartupShortcutDir
}

if ([string]::IsNullOrWhiteSpace($Endpoint) -or
    [string]::IsNullOrWhiteSpace($Model)) {
    throw "Endpoint and Model are required for the cloud dictation proof"
}

if ([string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
    [string]::IsNullOrWhiteSpace($ApiKeyName)) {
    throw "Cloud proof requires ApiKeyEnv or ApiKeyName"
}

if ([string]::IsNullOrWhiteSpace($WhisperCLI) -or
    [string]::IsNullOrWhiteSpace($WhisperModel)) {
    throw "WhisperCLI and WhisperModel are required for local whisper laptop proof"
}
$WhisperCLI = Resolve-FullPath -Path $WhisperCLI
$WhisperModel = Resolve-FullPath -Path $WhisperModel
Require-File -Path $WhisperCLI
Require-File -Path $WhisperModel

$proofScript = Join-Path $PackageDir "prove-windows-agent-artifact.ps1"
$checkSetScript = Join-Path $PackageDir "check-windows-proof-set.ps1"
Require-File -Path $proofScript
Require-File -Path $checkSetScript

$proofSessionId = [guid]::NewGuid().ToString("D")

$cloudReport = Join-Path $ProofDir "cloud-dictation-proof.json"
$localWhisperDictationReport = Join-Path $ProofDir "local-whisper-dictation-proof.json"
$localWhisperNotepadReport = Join-Path $ProofDir "local-whisper-notepad-paste-proof.json"

$cloudInstallDir = Join-Path $ProofDir "cloud-install"
$cloudConfigPath = Join-Path $cloudInstallDir "windows-agent.json"
$localInstallDir = Join-Path $ProofDir "local-whisper-install"
$localConfigPath = Join-Path $localInstallDir "windows-agent.json"
$notepadInstallDir = Join-Path $ProofDir "local-whisper-notepad-install"
$notepadConfigPath = Join-Path $notepadInstallDir "windows-agent.json"

$cloudArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $cloudInstallDir,
    "-ConfigPath", $cloudConfigPath,
    "-ProofReportPath", $cloudReport,
    "-ProofSessionId", $proofSessionId,
    "-Endpoint", $Endpoint,
    "-Model", $Model
)
if (![string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
    $cloudArgs += @("-ApiKeyEnv", $ApiKeyEnv)
}
if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    $cloudArgs += @("-ApiKeyName", $ApiKeyName)
}
if (![string]::IsNullOrWhiteSpace($SecretDir)) {
    $cloudArgs += @("-SecretDir", (Resolve-FullPath -Path $SecretDir))
}
if (![string]::IsNullOrWhiteSpace($CloudExpectedTranscriptText)) {
    $cloudArgs += @("-ExpectedTranscriptText", $CloudExpectedTranscriptText)
}
$cloudArgs = Add-CommonProofArgs -ArgumentList $cloudArgs
$cloudArgs += @("-RunDictation", "-PasteDictation")
$cloudArgs = Add-ShortcutProofArgs `
    -ArgumentList $cloudArgs `
    -ShortcutDir (Join-Path $ProofDir "cloud-shortcuts") `
    -StartupDir $StartupShortcutDir

$localArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $localInstallDir,
    "-ConfigPath", $localConfigPath,
    "-ProofReportPath", $localWhisperDictationReport,
    "-ProofSessionId", $proofSessionId,
    "-WhisperCLI", $WhisperCLI,
    "-WhisperModel", $WhisperModel
)
if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
    $localArgs += @("-WhisperOutputDir", (Resolve-FullPath -Path $WhisperOutputDir))
}
$whisperArguments = @(
    $WhisperArgument |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) }
)
if ($whisperArguments.Count -gt 0) {
    $localArgs += "-WhisperArgument"
    $localArgs += $whisperArguments
}
if (![string]::IsNullOrWhiteSpace($LocalWhisperExpectedTranscriptText)) {
    $localArgs += @("-ExpectedTranscriptText", $LocalWhisperExpectedTranscriptText)
}
$localArgs = Add-CommonProofArgs -ArgumentList $localArgs
$localArgs += @("-RunDictation", "-PasteDictation")
$localArgs = Add-ShortcutProofArgs `
    -ArgumentList $localArgs `
    -ShortcutDir (Join-Path $ProofDir "local-whisper-shortcuts") `
    -StartupDir $StartupShortcutDir

$notepadArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $notepadInstallDir,
    "-ConfigPath", $notepadConfigPath,
    "-ProofReportPath", $localWhisperNotepadReport,
    "-ProofSessionId", $proofSessionId,
    "-WhisperCLI", $WhisperCLI,
    "-WhisperModel", $WhisperModel,
    "-RunNotepadPasteProof"
)
if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
    $notepadArgs += @("-WhisperOutputDir", (Resolve-FullPath -Path $WhisperOutputDir))
}
if ($whisperArguments.Count -gt 0) {
    $notepadArgs += "-WhisperArgument"
    $notepadArgs += $whisperArguments
}
$notepadArgs = Add-CommonProofArgs -ArgumentList $notepadArgs

Invoke-Step "cloud dictation laptop proof" {
    Write-HoldDictationPrompt -Name "cloud_dictation" -ExpectedTranscriptText $CloudExpectedTranscriptText
    & $proofScript @cloudArgs
}

Invoke-Step "local whisper dictation laptop proof" {
    Write-HoldDictationPrompt -Name "local_whisper_dictation" -ExpectedTranscriptText $LocalWhisperExpectedTranscriptText
    & $proofScript @localArgs
}

Invoke-Step "local whisper Notepad paste proof" {
    Write-NotepadPastePrompt
    & $proofScript @notepadArgs
}

Invoke-Step "full laptop proof set check" {
    & $checkSetScript `
        -CloudDictationReportPath $cloudReport `
        -LocalWhisperDictationReportPath $localWhisperDictationReport `
        -LocalWhisperNotepadPasteReportPath $localWhisperNotepadReport `
        -RequireFullLaptopProof
}

Write-Host ""
Write-Host "windows_laptop_proof_dir=$ProofDir"
Write-Host "windows_laptop_proof_session_id=$proofSessionId"
Write-Host "windows_laptop_cloud_report=$cloudReport"
Write-Host "windows_laptop_local_whisper_report=$localWhisperDictationReport"
Write-Host "windows_laptop_notepad_report=$localWhisperNotepadReport"
Write-Host "windows_laptop_proof_ok=true"
