param(
    [Parameter(Mandatory = $true)]
    [string]$ProofReportPath,
    [string]$ExpectedMode = "",
    [ValidateSet("", "doctor-only", "cloud-dictation", "local-whisper-dictation", "local-whisper-notepad-paste", "packaged-whisper-mock-install")]
    [string]$RequireProofProfile = "",
    [switch]$RequireWindowsPlatform,
    [switch]$RequireInstall,
    [switch]$RequireShortcut,
    [switch]$RequireStartupShortcut,
    [switch]$RequirePermissionSurface,
    [switch]$RequireProofAgentSurface,
    [switch]$RequireNativeDoctorSurface,
    [switch]$RequirePackagedMock,
    [switch]$RequireHoldHook,
    [switch]$RequireCloudConfig,
    [switch]$RequireWhisperConfig,
    [switch]$RequireDictation,
    [switch]$RequirePaste,
    [switch]$RequireNotepadPaste
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-Property {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object -or !($Object.PSObject.Properties.Name -contains $Name)) {
        throw "Proof report property was not found: $Name"
    }

    return $Object.$Name
}

function Assert-FileProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [int64]$MinimumBytes = 1
    )

    $path = Require-Property -Object $Proof -Name "path"
    $exists = [bool](Require-Property -Object $Proof -Name "exists")
    $bytes = [int64](Require-Property -Object $Proof -Name "bytes")

    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "$Name path is empty"
    }
    if (!$exists) {
        throw "$Name does not exist: $path"
    }
    if ($bytes -lt $MinimumBytes) {
        throw "$Name has too few bytes: $path bytes=$bytes minimum=$MinimumBytes"
    }

    Write-Host "proof_file=$Name path=$path bytes=$bytes"
}

function Assert-ShortcutProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-FileProof -Proof $Proof -Name $Name
    Assert-NonEmptyString -Object $Proof -Name "target_path"
    Assert-NonEmptyString -Object $Proof -Name "arguments"
    Assert-NonEmptyString -Object $Proof -Name "working_directory"
    Assert-Boolean -Object $Proof -Name "target_is_powershell" -Expected $true
    Assert-Boolean -Object $Proof -Name "references_run_script" -Expected $true
    Assert-Boolean -Object $Proof -Name "has_config_path_argument" -Expected $true
    Assert-Boolean -Object $Proof -Name "references_config_path" -Expected $true
    Assert-Boolean -Object $Proof -Name "working_directory_is_install_dir" -Expected $true
}

function Assert-Boolean {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$Expected
    )

    $actual = [bool](Require-Property -Object $Object -Name $Name)
    if ($actual -ne $Expected) {
        throw "Expected $Name to be $Expected, got $actual"
    }

    Write-Host "proof_bool=$Name value=$actual"
}

function Assert-NonEmptyString {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $value = [string](Require-Property -Object $Object -Name $Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Expected non-empty proof report property: $Name"
    }

    Write-Host "proof_value=$Name value=$value"
}

function Assert-StringEquals {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Actual,
        [Parameter(Mandatory = $true)]
        [string]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Actual -ne $Expected) {
        throw "Expected $Name to be '$Expected', got '$Actual'"
    }

    Write-Host "proof_value=$Name value=$Actual"
}

function Assert-NumberGreaterThan {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [double]$Minimum
    )

    $actual = [double](Require-Property -Object $Object -Name $Name)
    if ($actual -le $Minimum) {
        throw "Expected $Name to be greater than $Minimum, got $actual"
    }

    Write-Host "proof_number=$Name value=$actual minimum=$Minimum"
}

function Assert-DictationRuntimeProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report
    )

    $runtime = Require-Property -Object $Report -Name "dictation_runtime"
    Assert-FileProof -Proof $runtime -Name "dictation_runtime_log"
    Assert-Boolean -Object $runtime -Name "reported_wrote" -Expected $true
    Assert-NonEmptyString -Object $runtime -Name "wrote_path"
    Assert-FileProof -Proof (Require-Property -Object $runtime -Name "wrote_file") -Name "dictation_runtime_wav"
    Assert-Boolean -Object $runtime -Name "reported_positive_duration" -Expected $true
    Assert-NumberGreaterThan -Object $runtime -Name "duration_seconds" -Minimum 0
    Assert-Boolean -Object $runtime -Name "reported_pre_roll" -Expected $true
    Assert-Boolean -Object $runtime -Name "reported_positive_pre_roll" -Expected $true
    Assert-NumberGreaterThan -Object $runtime -Name "included_pre_roll_seconds" -Minimum 0
    Assert-Boolean -Object $runtime -Name "reported_processed_text" -Expected $true
    Assert-Boolean -Object $runtime -Name "reported_positive_raw_transcript" -Expected $true
    Assert-Boolean -Object $runtime -Name "reported_positive_processed_transcript" -Expected $true
    Assert-NumberGreaterThan -Object $runtime -Name "raw_transcript_length" -Minimum 0
    Assert-NumberGreaterThan -Object $runtime -Name "processed_transcript_length" -Minimum 0

    return $runtime
}

function Assert-HoldHookRuntimeProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Runtime
    )

    Assert-Boolean -Object $Runtime -Name "reported_hold_mode" -Expected $true
    Assert-Boolean -Object $Runtime -Name "reported_waiting_for_hold_key_down" -Expected $true
    Assert-Boolean -Object $Runtime -Name "reported_hold_key_down" -Expected $true
    Assert-Boolean -Object $Runtime -Name "reported_hold_key_up" -Expected $true
}

function Assert-DoctorOutputProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "runtime_available" -Expected $true
    Assert-Boolean -Object $Proof -Name "os_permission_grants_microphone" -Expected $true
    Assert-Boolean -Object $Proof -Name "native_capabilities_register_hotkey" -Expected $true
    Assert-Boolean -Object $Proof -Name "no_admin_required" -Expected $true
    Assert-Boolean -Object $Proof -Name "no_startup_permission_prompt" -Expected $true
    Assert-Boolean -Object $Proof -Name "no_screen_capture_required" -Expected $true
    Write-Host "proof_doctor=$Name"
}

function Assert-ProofAgentDoctorOutputProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "swift_core" -Expected $true
    Assert-Boolean -Object $Proof -Name "pre_roll_config" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_paste_adapter_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_permission_surface_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_dictation_runtime_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_dictation_proof_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "miniaudio_capture_adapter_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "openai_compatible_transcription_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "whisper_cli_transcription_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "transcription_output_filter_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "word_replacement_processor_source" -Expected $true
    Write-Host "proof_agent_doctor=$Name"
}

function Assert-NativeDoctorOutputProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "platform_windows" -Expected $true
    Assert-NonEmptyString -Object $Proof -Name "expected_marker"
    Assert-Boolean -Object $Proof -Name "expected_marker_present" -Expected $true
    Write-Host "proof_native_doctor=$Name"
}

function Set-ExpectedModeFromProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    if (![string]::IsNullOrWhiteSpace($script:ExpectedMode) -and $script:ExpectedMode -ne $Mode) {
        throw "Proof profile $Profile expects mode $Mode, got ExpectedMode $script:ExpectedMode"
    }

    $script:ExpectedMode = $Mode
}

$ProofReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProofReportPath)
if (!(Test-Path -LiteralPath $ProofReportPath)) {
    throw "Proof report was not found: $ProofReportPath"
}

$report = Get-Content -LiteralPath $ProofReportPath -Raw | ConvertFrom-Json
$dictationRuntime = $null

switch ($RequireProofProfile) {
    "doctor-only" {
        Set-ExpectedModeFromProfile -Mode "doctor-only" -Profile $RequireProofProfile
        $RequireWindowsPlatform = $true
        $RequirePermissionSurface = $true
        $RequireProofAgentSurface = $true
        $RequireNativeDoctorSurface = $true
    }
    "cloud-dictation" {
        Set-ExpectedModeFromProfile -Mode "cloud" -Profile $RequireProofProfile
        $RequireWindowsPlatform = $true
        $RequireInstall = $true
        $RequireShortcut = $true
        $RequireStartupShortcut = $true
        $RequirePermissionSurface = $true
        $RequireProofAgentSurface = $true
        $RequireNativeDoctorSurface = $true
        $RequireHoldHook = $true
        $RequireCloudConfig = $true
        $RequireDictation = $true
        $RequirePaste = $true
    }
    "local-whisper-dictation" {
        Set-ExpectedModeFromProfile -Mode "local-whisper" -Profile $RequireProofProfile
        $RequireWindowsPlatform = $true
        $RequireInstall = $true
        $RequireShortcut = $true
        $RequireStartupShortcut = $true
        $RequirePermissionSurface = $true
        $RequireProofAgentSurface = $true
        $RequireNativeDoctorSurface = $true
        $RequireHoldHook = $true
        $RequireWhisperConfig = $true
        $RequireDictation = $true
        $RequirePaste = $true
    }
    "local-whisper-notepad-paste" {
        Set-ExpectedModeFromProfile -Mode "local-whisper" -Profile $RequireProofProfile
        $RequireWindowsPlatform = $true
        $RequireInstall = $true
        $RequirePermissionSurface = $true
        $RequireProofAgentSurface = $true
        $RequireNativeDoctorSurface = $true
        $RequireHoldHook = $true
        $RequireWhisperConfig = $true
        $RequireNotepadPaste = $true
    }
    "packaged-whisper-mock-install" {
        Set-ExpectedModeFromProfile -Mode "packaged-whisper-mock" -Profile $RequireProofProfile
        $RequireWindowsPlatform = $true
        $RequireInstall = $true
        $RequireShortcut = $true
        $RequireStartupShortcut = $true
        $RequirePermissionSurface = $true
        $RequireProofAgentSurface = $true
        $RequireNativeDoctorSurface = $true
        $RequirePackagedMock = $true
        $RequireHoldHook = $true
        $RequireWhisperConfig = $true
    }
    default {}
}

if (![string]::IsNullOrWhiteSpace($RequireProofProfile)) {
    Write-Host "proof_profile=$RequireProofProfile"
}

Assert-NonEmptyString -Object $report -Name "generated_at"
Assert-NonEmptyString -Object $report -Name "proof_mode"
Assert-NonEmptyString -Object $report -Name "package_dir"
Assert-NonEmptyString -Object $report -Name "install_dir"

if ($RequireWindowsPlatform) {
    $os = Require-Property -Object $report -Name "os"
    $platform = [string](Require-Property -Object $os -Name "platform")
    if ($platform -ne "Win32NT") {
        throw "Expected os.platform to be Win32NT, got $platform"
    }

    Write-Host "proof_windows_platform=$platform"
}

if (![string]::IsNullOrWhiteSpace($ExpectedMode)) {
    $actualMode = [string](Require-Property -Object $report -Name "proof_mode")
    if ($actualMode -ne $ExpectedMode) {
        throw "Expected proof_mode to be $ExpectedMode, got $actualMode"
    }

    Write-Host "proof_mode=$actualMode"
}

$files = Require-Property -Object $report -Name "files"
Assert-FileProof -Proof (Require-Property -Object $files -Name "packaged_agent") -Name "packaged_agent"
Assert-FileProof -Proof (Require-Property -Object $files -Name "packaged_proof_agent") -Name "packaged_proof_agent"

if ($RequirePackagedMock) {
    Assert-FileProof -Proof (Require-Property -Object $files -Name "packaged_whisper_cli_mock") -Name "packaged_whisper_cli_mock"
}

if ($RequireInstall) {
    Assert-FileProof -Proof (Require-Property -Object $files -Name "installed_agent") -Name "installed_agent"
    Assert-FileProof -Proof (Require-Property -Object $files -Name "installed_run_script") -Name "installed_run_script"

    $config = Require-Property -Object $report -Name "config"
    Assert-FileProof -Proof $config -Name "config"
}

if ($RequireShortcut) {
    Assert-ShortcutProof -Proof (Require-Property -Object $report -Name "shortcut") -Name "shortcut"
}

if ($RequireStartupShortcut) {
    Assert-ShortcutProof -Proof (Require-Property -Object $report -Name "startup_shortcut") -Name "startup_shortcut"
}

if ($RequirePermissionSurface) {
    $doctor = Require-Property -Object $report -Name "doctor"
    $packagedDoctor = Require-Property -Object $doctor -Name "packaged_agent"
    Assert-DoctorOutputProof -Proof $packagedDoctor -Name "packaged_agent"
    if ($RequireInstall) {
        $installedDoctor = Require-Property -Object $doctor -Name "installed_launcher"
        Assert-DoctorOutputProof -Proof $installedDoctor -Name "installed_launcher"
    }
}

if ($RequireProofAgentSurface) {
    $doctor = Require-Property -Object $report -Name "doctor"
    $packagedProofAgent = Require-Property -Object $doctor -Name "packaged_proof_agent"
    Assert-ProofAgentDoctorOutputProof -Proof $packagedProofAgent -Name "packaged_proof_agent"
}

if ($RequireNativeDoctorSurface) {
    $doctor = Require-Property -Object $report -Name "doctor"
    $nativeDoctors = Require-Property -Object $doctor -Name "packaged_native_doctors"
    foreach ($name in @(
        "register_hotkey",
        "keyboard_hook",
        "paste",
        "dpapi_secret",
        "miniaudio_capture"
    )) {
        Assert-NativeDoctorOutputProof `
            -Proof (Require-Property -Object $nativeDoctors -Name $name) `
            -Name $name
    }
}

if ($RequireHoldHook) {
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "uses_hold_hook" -Expected $true
}

if ($RequireCloudConfig) {
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "uses_whisper_cli" -Expected $false
    Assert-NonEmptyString -Object $config -Name "endpoint"
    Assert-NonEmptyString -Object $config -Name "model"
}

if ($RequireWhisperConfig) {
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "uses_whisper_cli" -Expected $true
    Assert-NonEmptyString -Object $config -Name "whisper_cli_path"
    Assert-NonEmptyString -Object $config -Name "whisper_model_path"
    Assert-FileProof -Proof (Require-Property -Object $config -Name "whisper_cli_file") -Name "whisper_cli"
    Assert-FileProof -Proof (Require-Property -Object $config -Name "whisper_model_file") -Name "whisper_model"
}

if ($RequireDictation) {
    Assert-Boolean -Object $report -Name "run_dictation" -Expected $true
    $config = Require-Property -Object $report -Name "config"
    $outputFile = Require-Property -Object $config -Name "output_file"
    Assert-FileProof -Proof $outputFile -Name "dictation_output" -MinimumBytes 45
    $dictationRuntime = Assert-DictationRuntimeProof -Report $report
    Assert-StringEquals `
        -Actual ([string](Require-Property -Object $dictationRuntime -Name "wrote_path")) `
        -Expected ([string](Require-Property -Object $outputFile -Name "path")) `
        -Name "dictation_runtime_wrote_path"
    if ($RequireHoldHook) {
        Assert-HoldHookRuntimeProof -Runtime $dictationRuntime
    }
}

if ($RequirePaste) {
    Assert-Boolean -Object $report -Name "paste_dictation" -Expected $true
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "should_paste" -Expected $true
    if ($null -eq $dictationRuntime) {
        $dictationRuntime = Assert-DictationRuntimeProof -Report $report
    }
    if ($RequireHoldHook) {
        Assert-HoldHookRuntimeProof -Runtime $dictationRuntime
    }
    Assert-Boolean -Object $dictationRuntime -Name "reported_paste_sent" -Expected $true
}

if ($RequireNotepadPaste) {
    $notepadPaste = Require-Property -Object $report -Name "notepad_paste"
    Assert-Boolean -Object $notepadPaste -Name "requested" -Expected $true
    Assert-Boolean -Object $notepadPaste -Name "output_present" -Expected $true
    Assert-Boolean -Object $notepadPaste -Name "paste_sent" -Expected $true
    Assert-Boolean -Object $notepadPaste -Name "text_found" -Expected $true
    Assert-Boolean -Object $notepadPaste -Name "verified" -Expected $true
    Assert-FileProof -Proof (Require-Property -Object $notepadPaste -Name "file") -Name "notepad_paste_file"
}

Write-Host "proof_report_ok=$ProofReportPath"
