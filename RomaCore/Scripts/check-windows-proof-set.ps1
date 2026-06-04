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

function Read-ProofReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = Resolve-RequiredReportPath -Path $Path -Name "report"
    return Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -ErrorAction Stop
}

function Require-ReportProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    if ($null -eq $Report -or !($Report.PSObject.Properties.Name -contains $Name)) {
        throw "Proof set report $ReportName is missing property: $Name"
    }

    return $Report.$Name
}

function Assert-SameReportValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$Actual,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    if ($Expected -ne $Actual) {
        throw ("Proof set mismatch for {0} in {1}: expected '{2}', got '{3}'" -f $Name, $ReportName, $Expected, $Actual)
    }
}

function Assert-SameLaptopProofSet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CloudReportPath,
        [Parameter(Mandatory = $true)]
        [string]$LocalWhisperReportPath,
        [Parameter(Mandatory = $true)]
        [string]$NotepadReportPath
    )

    $reports = @(
        @{
            Name = "cloud_dictation"
            Report = (Read-ProofReport -Path $CloudReportPath)
        },
        @{
            Name = "local_whisper_dictation"
            Report = (Read-ProofReport -Path $LocalWhisperReportPath)
        },
        @{
            Name = "local_whisper_notepad_paste"
            Report = (Read-ProofReport -Path $NotepadReportPath)
        }
    )

    $first = $reports[0]
    $firstName = [string]$first["Name"]
    $firstReport = $first["Report"]
    $firstOS = Require-ReportProperty -Report $firstReport -Name "os" -ReportName $firstName
    $expectedPlatform = [string](Require-ReportProperty -Report $firstOS -Name "platform" -ReportName $firstName)
    $expectedMachine = [string](Require-ReportProperty -Report $firstOS -Name "machine" -ReportName $firstName)
    $expectedPackageDir = [string](Require-ReportProperty -Report $firstReport -Name "package_dir" -ReportName $firstName)

    if ($expectedPlatform -ne "Win32NT") {
        throw "Full laptop proof must run on Windows, got platform $expectedPlatform"
    }
    if ([string]::IsNullOrWhiteSpace($expectedMachine)) {
        throw "Full laptop proof report is missing machine name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageDir)) {
        throw "Full laptop proof report is missing package_dir"
    }

    foreach ($entry in $reports) {
        $reportName = $entry["Name"]
        $report = $entry["Report"]
        $reportOS = Require-ReportProperty -Report $report -Name "os" -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.platform" `
            -Expected $expectedPlatform `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "platform" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.machine" `
            -Expected $expectedMachine `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "machine" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_dir" `
            -Expected $expectedPackageDir `
            -Actual ([string](Require-ReportProperty -Report $report -Name "package_dir" -ReportName $reportName)) `
            -ReportName $reportName
    }

    Write-Host "proof_set_machine=$expectedMachine"
    Write-Host "proof_set_package_dir=$expectedPackageDir"
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
    Assert-SameLaptopProofSet `
        -CloudReportPath $CloudDictationReportPath `
        -LocalWhisperReportPath $LocalWhisperDictationReportPath `
        -NotepadReportPath $LocalWhisperNotepadPasteReportPath
    Write-Host "proof_set_ok=full-laptop"
} elseif ($RequireArtifactSmokeProof) {
    Write-Host "proof_set_ok=artifact-smoke"
} else {
    Write-Host "proof_set_ok=custom"
}
