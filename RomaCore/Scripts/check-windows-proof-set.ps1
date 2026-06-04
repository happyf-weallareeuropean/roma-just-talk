param(
    [string]$DoctorOnlyReportPath = "",
    [string]$CloudDictationReportPath = "",
    [string]$LocalWhisperDictationReportPath = "",
    [string]$LocalWhisperNotepadPasteReportPath = "",
    [string]$LaptopPreflightReportPath = "",
    [string]$PackagedWhisperMockInstallReportPath = "",
    [switch]$RequireDoctorOnly,
    [switch]$RequireCloudDictation,
    [switch]$RequireLocalWhisperDictation,
    [switch]$RequireLocalWhisperNotepadPaste,
    [switch]$RequireLaptopPreflight,
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

    return $Report.PSObject.Properties[$Name].Value
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

function Assert-NonEmptyReportString {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $value = [string](Require-ReportProperty -Report $Report -Name $Name -ReportName $ReportName)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Proof set report $ReportName has empty property: $Name"
    }

    Write-Host "proof_set_value=$ReportName.$Name value=$value"
    return $value
}

function Assert-ReportBoolean {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $actual = [bool](Require-ReportProperty -Report $Report -Name $Name -ReportName $ReportName)
    if ($actual -ne $Expected) {
        throw "Proof set report $ReportName expected $Name to be $Expected, got $actual"
    }

    Write-Host "proof_set_bool=$ReportName.$Name value=$actual"
}

function Assert-ReportFileProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [int64]$MinimumBytes = 1
    )

    $path = [string](Require-ReportProperty -Report $Proof -Name "path" -ReportName $Name)
    $exists = [bool](Require-ReportProperty -Report $Proof -Name "exists" -ReportName $Name)
    $bytes = [int64](Require-ReportProperty -Report $Proof -Name "bytes" -ReportName $Name)

    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Proof set file proof $Name has empty path"
    }
    if (!$exists) {
        throw "Proof set file proof $Name does not exist: $path"
    }
    if ($bytes -lt $MinimumBytes) {
        throw "Proof set file proof $Name has too few bytes: $path bytes=$bytes minimum=$MinimumBytes"
    }

    Write-Host "proof_set_file=$Name path=$path bytes=$bytes"
}

function Get-ReportPackageFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $packageIdentity = Require-ReportProperty -Report $Report -Name "package_identity" -ReportName $ReportName
    $algorithm = [string](Require-ReportProperty -Report $packageIdentity -Name "algorithm" -ReportName $ReportName)
    if ($algorithm -ne "sha256") {
        throw "Proof set report $ReportName has unsupported package identity algorithm: $algorithm"
    }

    return [string](Require-ReportProperty -Report $packageIdentity -Name "fingerprint" -ReportName $ReportName)
}

function Get-ReportSourceProvenance {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $manifest = Require-ReportProperty -Report $Report -Name "manifest" -ReportName $ReportName
    $repository = [string](Require-ReportProperty -Report $manifest -Name "source_repository" -ReportName $ReportName)
    $branch = [string](Require-ReportProperty -Report $manifest -Name "source_branch" -ReportName $ReportName)
    $commit = [string](Require-ReportProperty -Report $manifest -Name "source_commit" -ReportName $ReportName)
    $dirty = [string](Require-ReportProperty -Report $manifest -Name "source_dirty" -ReportName $ReportName)

    if ([string]::IsNullOrWhiteSpace($repository) -or $repository -eq "unknown") {
        throw "Proof set report $ReportName is missing source repository provenance"
    }
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Proof set report $ReportName is missing source branch provenance"
    }
    if ($commit -notmatch "^[0-9a-fA-F]{40}$") {
        throw "Proof set report $ReportName has invalid source commit provenance: $commit"
    }
    if ($dirty -ne "true" -and $dirty -ne "false") {
        throw "Proof set report $ReportName has invalid source dirty provenance: $dirty"
    }

    return [ordered]@{
        Repository = $repository
        Branch = $branch
        Commit = $commit
        Dirty = $dirty
    }
}

function Assert-SameArtifactSmokeProofSet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoctorOnlyReportPath,
        [Parameter(Mandatory = $true)]
        [string]$PackagedWhisperMockInstallReportPath
    )

    $reports = @(
        @{
            Name = "doctor_only"
            Report = (Read-ProofReport -Path $DoctorOnlyReportPath)
        },
        @{
            Name = "packaged_whisper_mock_install"
            Report = (Read-ProofReport -Path $PackagedWhisperMockInstallReportPath)
        }
    )

    $first = $reports[0]
    $firstName = [string]$first["Name"]
    $firstReport = $first["Report"]
    $firstOS = Require-ReportProperty -Report $firstReport -Name "os" -ReportName $firstName
    $expectedPlatform = [string](Require-ReportProperty -Report $firstOS -Name "platform" -ReportName $firstName)
    $expectedMachine = [string](Require-ReportProperty -Report $firstOS -Name "machine" -ReportName $firstName)
    $expectedUserName = [string](Require-ReportProperty -Report $firstOS -Name "user_name" -ReportName $firstName)
    $expectedUserDomain = [string](Require-ReportProperty -Report $firstOS -Name "user_domain" -ReportName $firstName)
    $expectedUserSid = [string](Require-ReportProperty -Report $firstOS -Name "user_sid" -ReportName $firstName)
    $expectedPackageDir = [string](Require-ReportProperty -Report $firstReport -Name "package_dir" -ReportName $firstName)
    $expectedPackageFingerprint = Get-ReportPackageFingerprint -Report $firstReport -ReportName $firstName
    $expectedSource = Get-ReportSourceProvenance -Report $firstReport -ReportName $firstName

    if ($expectedPlatform -ne "Win32NT") {
        throw "Artifact smoke proof must run on Windows, got platform $expectedPlatform"
    }
    if ([string]::IsNullOrWhiteSpace($expectedMachine)) {
        throw "Artifact smoke proof report is missing machine name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedUserName)) {
        throw "Artifact smoke proof report is missing Windows user name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedUserSid)) {
        throw "Artifact smoke proof report is missing Windows user SID"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageDir)) {
        throw "Artifact smoke proof report is missing package_dir"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageFingerprint)) {
        throw "Artifact smoke proof report is missing package identity fingerprint"
    }
    if ([string]$expectedSource['Dirty'] -ne "false") {
        throw "Artifact smoke proof requires a clean packaged source checkout, got source_dirty=$($expectedSource['Dirty'])"
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
            -Name "os.user_name" `
            -Expected $expectedUserName `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_name" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_domain" `
            -Expected $expectedUserDomain `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_domain" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_sid" `
            -Expected $expectedUserSid `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_sid" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_dir" `
            -Expected $expectedPackageDir `
            -Actual ([string](Require-ReportProperty -Report $report -Name "package_dir" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_identity.fingerprint" `
            -Expected $expectedPackageFingerprint `
            -Actual (Get-ReportPackageFingerprint -Report $report -ReportName $reportName) `
            -ReportName $reportName
        $source = Get-ReportSourceProvenance -Report $report -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_repository" `
            -Expected ([string]$expectedSource['Repository']) `
            -Actual ([string]$source['Repository']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_branch" `
            -Expected ([string]$expectedSource['Branch']) `
            -Actual ([string]$source['Branch']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_commit" `
            -Expected ([string]$expectedSource['Commit']) `
            -Actual ([string]$source['Commit']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_dirty" `
            -Expected ([string]$expectedSource['Dirty']) `
            -Actual ([string]$source['Dirty']) `
            -ReportName $reportName
    }

    Write-Host "proof_set_artifact_smoke_machine=$expectedMachine"
    Write-Host "proof_set_artifact_smoke_user=$expectedUserName"
    Write-Host "proof_set_artifact_smoke_user_sid=$expectedUserSid"
    Write-Host "proof_set_artifact_smoke_package_dir=$expectedPackageDir"
    Write-Host "proof_set_artifact_smoke_package_fingerprint=$expectedPackageFingerprint"
    Write-Host "proof_set_artifact_smoke_source_repository=$($expectedSource['Repository'])"
    Write-Host "proof_set_artifact_smoke_source_branch=$($expectedSource['Branch'])"
    Write-Host "proof_set_artifact_smoke_source_commit=$($expectedSource['Commit'])"
    Write-Host "proof_set_artifact_smoke_source_dirty=$($expectedSource['Dirty'])"
}

function Assert-LaptopPreflightReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $reportName = "laptop_preflight"
    $report = Read-ProofReport -Path $Path

    Assert-SameReportValue `
        -Name "proof_mode" `
        -Expected "windows-laptop-preflight" `
        -Actual ([string](Require-ReportProperty -Report $report -Name "proof_mode" -ReportName $reportName)) `
        -ReportName $reportName
    Assert-ReportBoolean -Report $report -Name "preflight_only" -Expected $true -ReportName $reportName
    $proofSessionId = Assert-NonEmptyReportString -Report $report -Name "proof_session_id" -ReportName $reportName
    $packageDir = Assert-NonEmptyReportString -Report $report -Name "package_dir" -ReportName $reportName
    $proofDir = Assert-NonEmptyReportString -Report $report -Name "proof_dir" -ReportName $reportName

    $os = Require-ReportProperty -Report $report -Name "os" -ReportName $reportName
    $platform = [string](Require-ReportProperty -Report $os -Name "platform" -ReportName $reportName)
    if ($platform -ne "Win32NT") {
        throw "Laptop preflight proof must run on Windows, got platform $platform"
    }
    $machine = Assert-NonEmptyReportString -Report $os -Name "machine" -ReportName $reportName
    $userName = Assert-NonEmptyReportString -Report $os -Name "user_name" -ReportName $reportName
    $userSid = Assert-NonEmptyReportString -Report $os -Name "user_sid" -ReportName $reportName

    $preflights = Require-ReportProperty -Report $report -Name "preflights" -ReportName $reportName
    Assert-ReportBoolean -Report $preflights -Name "hotkey_delivery" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $preflights -Name "microphone" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $preflights -Name "local_whisper" -Expected $true -ReportName $reportName

    $preflightOutputs = Require-ReportProperty -Report $report -Name "preflight_outputs" -ReportName $reportName
    $hotkeyOutput = Require-ReportProperty -Report $preflightOutputs -Name "hotkey_delivery" -ReportName $reportName
    Assert-ReportBoolean -Report $hotkeyOutput -Name "output_present" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $hotkeyOutput -Name "waiting_for_hold" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $hotkeyOutput -Name "key_down" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $hotkeyOutput -Name "key_up" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $hotkeyOutput -Name "observed_events_present" -Expected $true -ReportName $reportName

    $microphoneOutput = Require-ReportProperty -Report $preflightOutputs -Name "microphone" -ReportName $reportName
    Assert-ReportBoolean -Report $microphoneOutput -Name "output_present" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $microphoneOutput -Name "wrote_present" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $microphoneOutput -Name "sample_rate_16000" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $microphoneOutput -Name "channels_mono" -Expected $true -ReportName $reportName

    $localWhisperOutput = Require-ReportProperty -Report $preflightOutputs -Name "local_whisper" -ReportName $reportName
    Assert-ReportBoolean -Report $localWhisperOutput -Name "output_present" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $localWhisperOutput -Name "transcription_client_whisper" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $localWhisperOutput -Name "network_required_false" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $localWhisperOutput -Name "executable_present" -Expected $true -ReportName $reportName
    Assert-ReportBoolean -Report $localWhisperOutput -Name "model_file_present" -Expected $true -ReportName $reportName

    $files = Require-ReportProperty -Report $report -Name "files" -ReportName $reportName
    Assert-ReportFileProof -Proof (Require-ReportProperty -Report $files -Name "proof_agent" -ReportName $reportName) -Name "laptop_preflight.proof_agent"
    Assert-ReportFileProof -Proof (Require-ReportProperty -Report $files -Name "mic_preflight_wav" -ReportName $reportName) -Name "laptop_preflight.mic_preflight_wav" -MinimumBytes 45
    Assert-ReportFileProof -Proof (Require-ReportProperty -Report $files -Name "whisper_cli" -ReportName $reportName) -Name "laptop_preflight.whisper_cli"
    Assert-ReportFileProof -Proof (Require-ReportProperty -Report $files -Name "whisper_model" -ReportName $reportName) -Name "laptop_preflight.whisper_model"

    Write-Host "proof_set_laptop_preflight_session_id=$proofSessionId"
    Write-Host "proof_set_laptop_preflight_machine=$machine"
    Write-Host "proof_set_laptop_preflight_user=$userName"
    Write-Host "proof_set_laptop_preflight_user_sid=$userSid"
    Write-Host "proof_set_laptop_preflight_package_dir=$packageDir"
    Write-Host "proof_set_laptop_preflight_proof_dir=$proofDir"
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
    $expectedProofSessionId = [string](Require-ReportProperty -Report $firstReport -Name "proof_session_id" -ReportName $firstName)
    $firstOS = Require-ReportProperty -Report $firstReport -Name "os" -ReportName $firstName
    $expectedPlatform = [string](Require-ReportProperty -Report $firstOS -Name "platform" -ReportName $firstName)
    $expectedMachine = [string](Require-ReportProperty -Report $firstOS -Name "machine" -ReportName $firstName)
    $expectedUserName = [string](Require-ReportProperty -Report $firstOS -Name "user_name" -ReportName $firstName)
    $expectedUserDomain = [string](Require-ReportProperty -Report $firstOS -Name "user_domain" -ReportName $firstName)
    $expectedUserSid = [string](Require-ReportProperty -Report $firstOS -Name "user_sid" -ReportName $firstName)
    $expectedPackageDir = [string](Require-ReportProperty -Report $firstReport -Name "package_dir" -ReportName $firstName)
    $expectedPackageFingerprint = Get-ReportPackageFingerprint -Report $firstReport -ReportName $firstName
    $expectedSource = Get-ReportSourceProvenance -Report $firstReport -ReportName $firstName

    if ($expectedPlatform -ne "Win32NT") {
        throw "Full laptop proof must run on Windows, got platform $expectedPlatform"
    }
    if ([string]::IsNullOrWhiteSpace($expectedProofSessionId)) {
        throw "Full laptop proof report is missing proof_session_id; use run-windows-laptop-proof.ps1 or pass one shared ProofSessionId"
    }
    if ([string]::IsNullOrWhiteSpace($expectedMachine)) {
        throw "Full laptop proof report is missing machine name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedUserName)) {
        throw "Full laptop proof report is missing Windows user name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedUserSid)) {
        throw "Full laptop proof report is missing Windows user SID"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageDir)) {
        throw "Full laptop proof report is missing package_dir"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageFingerprint)) {
        throw "Full laptop proof report is missing package identity fingerprint"
    }
    if ([string]$expectedSource['Dirty'] -ne "false") {
        throw "Full laptop proof requires a clean packaged source checkout, got source_dirty=$($expectedSource['Dirty'])"
    }

    foreach ($entry in $reports) {
        $reportName = $entry["Name"]
        $report = $entry["Report"]
        Assert-SameReportValue `
            -Name "proof_session_id" `
            -Expected $expectedProofSessionId `
            -Actual ([string](Require-ReportProperty -Report $report -Name "proof_session_id" -ReportName $reportName)) `
            -ReportName $reportName
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
            -Name "os.user_name" `
            -Expected $expectedUserName `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_name" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_domain" `
            -Expected $expectedUserDomain `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_domain" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_sid" `
            -Expected $expectedUserSid `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_sid" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_dir" `
            -Expected $expectedPackageDir `
            -Actual ([string](Require-ReportProperty -Report $report -Name "package_dir" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_identity.fingerprint" `
            -Expected $expectedPackageFingerprint `
            -Actual (Get-ReportPackageFingerprint -Report $report -ReportName $reportName) `
            -ReportName $reportName
        $source = Get-ReportSourceProvenance -Report $report -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_repository" `
            -Expected ([string]$expectedSource['Repository']) `
            -Actual ([string]$source['Repository']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_branch" `
            -Expected ([string]$expectedSource['Branch']) `
            -Actual ([string]$source['Branch']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_commit" `
            -Expected ([string]$expectedSource['Commit']) `
            -Actual ([string]$source['Commit']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_dirty" `
            -Expected ([string]$expectedSource['Dirty']) `
            -Actual ([string]$source['Dirty']) `
            -ReportName $reportName
    }

    Write-Host "proof_set_session_id=$expectedProofSessionId"
    Write-Host "proof_set_machine=$expectedMachine"
    Write-Host "proof_set_user=$expectedUserName"
    Write-Host "proof_set_user_sid=$expectedUserSid"
    Write-Host "proof_set_package_dir=$expectedPackageDir"
    Write-Host "proof_set_package_fingerprint=$expectedPackageFingerprint"
    Write-Host "proof_set_source_repository=$($expectedSource['Repository'])"
    Write-Host "proof_set_source_branch=$($expectedSource['Branch'])"
    Write-Host "proof_set_source_commit=$($expectedSource['Commit'])"
    Write-Host "proof_set_source_dirty=$($expectedSource['Dirty'])"
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
    $RequireLaptopPreflight -or
    $RequirePackagedWhisperMockInstall

if (!$hasExplicitRequirement) {
    $RequireDoctorOnly = ![string]::IsNullOrWhiteSpace($DoctorOnlyReportPath)
    $RequireCloudDictation = ![string]::IsNullOrWhiteSpace($CloudDictationReportPath)
    $RequireLocalWhisperDictation = ![string]::IsNullOrWhiteSpace($LocalWhisperDictationReportPath)
    $RequireLocalWhisperNotepadPaste = ![string]::IsNullOrWhiteSpace($LocalWhisperNotepadPasteReportPath)
    $RequireLaptopPreflight = ![string]::IsNullOrWhiteSpace($LaptopPreflightReportPath)
    $RequirePackagedWhisperMockInstall = ![string]::IsNullOrWhiteSpace($PackagedWhisperMockInstallReportPath)
}

$hasRequirement = $RequireDoctorOnly -or
    $RequireCloudDictation -or
    $RequireLocalWhisperDictation -or
    $RequireLocalWhisperNotepadPaste -or
    $RequireLaptopPreflight -or
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

if ($RequireLaptopPreflight) {
    Write-Host ""
    Write-Host "== proof_set_check=laptop_preflight =="
    Assert-LaptopPreflightReport -Path $LaptopPreflightReportPath
    Write-Host "proof_set_requirement=laptop_preflight status=pass report=$LaptopPreflightReportPath"
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
    Assert-SameArtifactSmokeProofSet `
        -DoctorOnlyReportPath $DoctorOnlyReportPath `
        -PackagedWhisperMockInstallReportPath $PackagedWhisperMockInstallReportPath
    Write-Host "proof_set_ok=artifact-smoke"
} elseif ($RequireLaptopPreflight) {
    Write-Host "proof_set_ok=laptop-preflight"
} else {
    Write-Host "proof_set_ok=custom"
}
