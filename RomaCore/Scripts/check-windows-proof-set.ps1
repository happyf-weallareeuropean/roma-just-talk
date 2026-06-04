param(
    [string]$DoctorOnlyReportPath = "",
    [string]$CloudDictationReportPath = "",
    [string]$LocalWhisperDictationReportPath = "",
    [string]$LocalWhisperNotepadPasteReportPath = "",
    [string]$PackagedWhisperMockInstallReportPath = "",
    [switch]$RequireDoctorOnly,
    [switch]$RequireCloudDictation,
    [switch]$RequireLocalWhisperDictation,
    [switch]$RequireLocalWhisperNotepadPaste,
    [switch]$RequirePackagedWhisperMockInstall,
    [switch]$RequireArtifactSmokeProof,
    [switch]$RequireFullLaptopProof
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-RequiredReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Missing proof report path for $Name"
    }

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (!(Test-Path -LiteralPath $resolvedPath)) {
        throw ("Proof report was not found for {0}: {1}" -f $Name, $resolvedPath)
    }

    return $resolvedPath
}

function Invoke-ProofReportProfileCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Profile,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = Resolve-RequiredReportPath -Path $Path -Name $Name
    Write-Host ""
    Write-Host "== proof_set_check=$Name profile=$Profile =="
    & $script:checkReportScript `
        -ProofReportPath $resolvedPath `
        -RequireProofProfile $Profile
    Write-Host "proof_set_requirement=$Name status=pass report=$resolvedPath"
}

$script:checkReportScript = Join-Path $PSScriptRoot "check-windows-proof-report.ps1"
if (!(Test-Path -LiteralPath $script:checkReportScript)) {
    throw "check-windows-proof-report.ps1 was not found next to this script: $script:checkReportScript"
}

if ($RequireArtifactSmokeProof) {
    $RequireDoctorOnly = $true
    $RequirePackagedWhisperMockInstall = $true
}

if ($RequireFullLaptopProof) {
    $RequireCloudDictation = $true
    $RequireLocalWhisperDictation = $true
    $RequireLocalWhisperNotepadPaste = $true
}

$hasExplicitRequirement = $RequireDoctorOnly -or
    $RequireCloudDictation -or
    $RequireLocalWhisperDictation -or
    $RequireLocalWhisperNotepadPaste -or
    $RequirePackagedWhisperMockInstall

if (!$hasExplicitRequirement) {
    $RequireDoctorOnly = ![string]::IsNullOrWhiteSpace($DoctorOnlyReportPath)
    $RequireCloudDictation = ![string]::IsNullOrWhiteSpace($CloudDictationReportPath)
    $RequireLocalWhisperDictation = ![string]::IsNullOrWhiteSpace($LocalWhisperDictationReportPath)
    $RequireLocalWhisperNotepadPaste = ![string]::IsNullOrWhiteSpace($LocalWhisperNotepadPasteReportPath)
    $RequirePackagedWhisperMockInstall = ![string]::IsNullOrWhiteSpace($PackagedWhisperMockInstallReportPath)
}

$hasRequirement = $RequireDoctorOnly -or
    $RequireCloudDictation -or
    $RequireLocalWhisperDictation -or
    $RequireLocalWhisperNotepadPaste -or
    $RequirePackagedWhisperMockInstall

if (!$hasRequirement) {
    throw "Pass at least one proof report path or require a proof set"
}

if ($RequireDoctorOnly) {
    Invoke-ProofReportProfileCheck `
        -Name "doctor_only" `
        -Profile "doctor-only" `
        -Path $DoctorOnlyReportPath
}

if ($RequireCloudDictation) {
    Invoke-ProofReportProfileCheck `
        -Name "cloud_dictation" `
        -Profile "cloud-dictation" `
        -Path $CloudDictationReportPath
}

if ($RequireLocalWhisperDictation) {
    Invoke-ProofReportProfileCheck `
        -Name "local_whisper_dictation" `
        -Profile "local-whisper-dictation" `
        -Path $LocalWhisperDictationReportPath
}

if ($RequireLocalWhisperNotepadPaste) {
    Invoke-ProofReportProfileCheck `
        -Name "local_whisper_notepad_paste" `
        -Profile "local-whisper-notepad-paste" `
        -Path $LocalWhisperNotepadPasteReportPath
}

if ($RequirePackagedWhisperMockInstall) {
    Invoke-ProofReportProfileCheck `
        -Name "packaged_whisper_mock_install" `
        -Profile "packaged-whisper-mock-install" `
        -Path $PackagedWhisperMockInstallReportPath
}

if ($RequireFullLaptopProof) {
    Write-Host "proof_set_ok=full-laptop"
} elseif ($RequireArtifactSmokeProof) {
    Write-Host "proof_set_ok=artifact-smoke"
} else {
    Write-Host "proof_set_ok=custom"
}
