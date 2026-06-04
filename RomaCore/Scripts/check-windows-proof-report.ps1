param(
    [Parameter(Mandatory = $true)]
    [string]$ProofReportPath,
    [string]$ExpectedMode = "",
    [switch]$RequireWindowsPlatform,
    [switch]$RequireInstall,
    [switch]$RequireShortcut,
    [switch]$RequireStartupShortcut,
    [switch]$RequirePermissionSurface,
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
    Assert-Boolean -Object $runtime -Name "reported_pre_roll" -Expected $true
    Assert-Boolean -Object $runtime -Name "reported_positive_pre_roll" -Expected $true
    Assert-NumberGreaterThan -Object $runtime -Name "included_pre_roll_seconds" -Minimum 0
    Assert-Boolean -Object $runtime -Name "reported_processed_text" -Expected $true

    return $runtime
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

$ProofReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProofReportPath)
if (!(Test-Path -LiteralPath $ProofReportPath)) {
    throw "Proof report was not found: $ProofReportPath"
}

$report = Get-Content -LiteralPath $ProofReportPath -Raw | ConvertFrom-Json
$dictationRuntime = $null

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
    Assert-FileProof -Proof (Require-Property -Object $report -Name "shortcut") -Name "shortcut"
}

if ($RequireStartupShortcut) {
    Assert-FileProof -Proof (Require-Property -Object $report -Name "startup_shortcut") -Name "startup_shortcut"
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
}

if ($RequirePaste) {
    Assert-Boolean -Object $report -Name "paste_dictation" -Expected $true
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "should_paste" -Expected $true
    if ($null -eq $dictationRuntime) {
        $dictationRuntime = Assert-DictationRuntimeProof -Report $report
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
