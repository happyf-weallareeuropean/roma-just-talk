param(
    [string]$PackageDir = "",
    [string]$InstallDir = "",
    [string]$ConfigPath = "",
    [string]$ProofReportPath = "",
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
    [switch]$UseHoldHook,
    [switch]$UseToggle,
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$PasteDictation,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2,
    [switch]$UsePackagedWhisperMock,
    [switch]$RunDictation,
    [switch]$CreateShortcut,
    [switch]$CreateStartupShortcut,
    [string]$ShortcutDir = "",
    [string]$StartupShortcutDir = "",
    [switch]$DoctorOnly
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

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Resolve-PackagePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return Resolve-FullPath -Path $Path
    }

    return Resolve-FullPath -Path (Join-Path $PackageDir $Path)
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

function Read-Manifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $manifest = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or !$line.Contains("=")) {
            continue
        }

        $separator = $line.IndexOf("=")
        $key = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        $manifest[$key] = $value
    }

    return $manifest
}

function Require-ManifestKey {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (!$Manifest.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Manifest[$Key])) {
        throw "Manifest key was not found: $Key"
    }

    Write-Host "manifest_$Key=$($Manifest[$Key])"
}

function Get-FileProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $exists = Test-Path -LiteralPath $Path
    $bytes = 0
    if ($exists) {
        $bytes = (Get-Item -LiteralPath $Path).Length
    }

    return [ordered]@{
        path = $Path
        exists = $exists
        bytes = $bytes
    }
}

function Get-ConfigProof {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        return [ordered]@{
            path = ""
            exists = $false
        }
    }

    $proof = Get-FileProof -Path $ConfigPath
    if (!$proof["exists"]) {
        return $proof
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($config.PSObject.Properties.Name -contains "outputPath") {
        $outputPath = [string]$config.outputPath
        $proof["output_path"] = $outputPath
        if (![string]::IsNullOrWhiteSpace($outputPath)) {
            $proof["output_file"] = Get-FileProof -Path $outputPath
        }
    }
    if ($config.PSObject.Properties.Name -contains "usesHoldHook") {
        $proof["uses_hold_hook"] = [bool]$config.usesHoldHook
    }
    if ($config.PSObject.Properties.Name -contains "shouldPaste") {
        $proof["should_paste"] = [bool]$config.shouldPaste
    }
    if ($config.PSObject.Properties.Name -contains "restoreClipboardAfterPaste") {
        $proof["restore_clipboard_after_paste"] = [bool]$config.restoreClipboardAfterPaste
    }
    if ($config.PSObject.Properties.Name -contains "whisperCLIPath" -and
        ![string]::IsNullOrWhiteSpace([string]$config.whisperCLIPath)) {
        $proof["uses_whisper_cli"] = $true
        $proof["whisper_cli_path"] = [string]$config.whisperCLIPath
        $proof["whisper_cli_file"] = Get-FileProof -Path ([string]$config.whisperCLIPath)
        if ($config.PSObject.Properties.Name -contains "whisperModelPath") {
            $proof["whisper_model_path"] = [string]$config.whisperModelPath
            $proof["whisper_model_file"] = Get-FileProof -Path ([string]$config.whisperModelPath)
        }
    } else {
        $proof["uses_whisper_cli"] = $false
    }
    if ($config.PSObject.Properties.Name -contains "endpoint") {
        $proof["endpoint"] = [string]$config.endpoint
    }
    if ($config.PSObject.Properties.Name -contains "model") {
        $proof["model"] = [string]$config.model
    }

    return $proof
}

function Get-DictationRuntimeProof {
    $logPath = Join-Path (Join-Path $InstallDir "smoke") "windows-agent-dictate.log"
    $proof = Get-FileProof -Path $logPath
    if (!$proof["exists"]) {
        return $proof
    }

    $content = Get-Content -LiteralPath $logPath -Raw
    $proof["reported_wrote"] = $content.Contains("wrote=")
    $proof["reported_pre_roll"] = $content.Contains("included_pre_roll_seconds=")
    $proof["reported_processed_text"] = $content.Contains("processed_transcript_text=")
    $proof["reported_paste_sent"] = $content.Contains("paste_sent=true")
    $proof["reported_paste_not_sent"] = $content.Contains("paste_sent=false")

    return $proof
}

function Write-ProofReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [bool]$IsDoctorOnly
    )

    if ([string]::IsNullOrWhiteSpace($ProofReportPath)) {
        return
    }

    $reportParent = Split-Path -Parent $ProofReportPath
    if (![string]::IsNullOrWhiteSpace($reportParent)) {
        New-Item -ItemType Directory -Force -Path $reportParent | Out-Null
    }

    $shortcutPath = ""
    if (![string]::IsNullOrWhiteSpace($ShortcutDir)) {
        $shortcutPath = Join-Path $ShortcutDir "Roma Just Talk Agent.lnk"
    }
    $startupShortcutPath = ""
    if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
        $startupShortcutPath = Join-Path $StartupShortcutDir "Roma Just Talk Agent.lnk"
    } elseif ($CreateStartupShortcut) {
        $startup = [System.Environment]::GetFolderPath("Startup")
        if (![string]::IsNullOrWhiteSpace($startup)) {
            $startupShortcutPath = Join-Path $startup "Roma Just Talk Agent.lnk"
        }
    }

    $report = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        proof_mode = $Mode
        doctor_only = $IsDoctorOnly
        run_dictation = $RunDictation.IsPresent
        paste_dictation = $PasteDictation.IsPresent
        create_shortcut = $CreateShortcut.IsPresent
        create_startup_shortcut = $CreateStartupShortcut.IsPresent
        restore_clipboard = $RestoreClipboard.IsPresent
        no_restore_clipboard = $NoRestoreClipboard.IsPresent
        os = [ordered]@{
            platform = [System.Environment]::OSVersion.Platform.ToString()
            version = [System.Environment]::OSVersion.VersionString
            machine = $env:COMPUTERNAME
        }
        package_dir = $PackageDir
        install_dir = $InstallDir
        config = (Get-ConfigProof)
        files = [ordered]@{
            packaged_agent = (Get-FileProof -Path $agentPath)
            packaged_whisper_cli_mock = (Get-FileProof -Path $script:packagedWhisperCLI)
            installed_agent = (Get-FileProof -Path (Join-Path $InstallDir "RomaWindowsAgent.exe"))
            installed_run_script = (Get-FileProof -Path (Join-Path $InstallDir "run-windows-agent.ps1"))
        }
        manifest = $script:artifactManifest
    }
    if (![string]::IsNullOrWhiteSpace($shortcutPath)) {
        $report["shortcut"] = Get-FileProof -Path $shortcutPath
    }
    if (![string]::IsNullOrWhiteSpace($startupShortcutPath)) {
        $report["startup_shortcut"] = Get-FileProof -Path $startupShortcutPath
    }
    if ($RunDictation) {
        $report["dictation_runtime"] = Get-DictationRuntimeProof
    }

    $report |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $ProofReportPath -Encoding UTF8
    Write-Host "proof_report=$ProofReportPath"
}

if ($UseHoldHook -and $UseToggle) {
    throw "UseHoldHook and UseToggle are mutually exclusive"
}

if ($RestoreClipboard -and $NoRestoreClipboard) {
    throw "RestoreClipboard and NoRestoreClipboard are mutually exclusive"
}

if ($ClipboardRestoreDelaySeconds -lt 0) {
    throw "ClipboardRestoreDelaySeconds must be non-negative"
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $PSScriptRoot
}
$PackageDir = Resolve-FullPath -Path $PackageDir

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not set; pass -InstallDir explicitly"
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA "roma-just-talk\agent"
}
$InstallDir = Resolve-FullPath -Path $InstallDir

if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Resolve-FullPath -Path $ConfigPath
}
if (![string]::IsNullOrWhiteSpace($ProofReportPath)) {
    $ProofReportPath = Resolve-FullPath -Path $ProofReportPath
}

$agentPath = Join-Path $PackageDir "RomaWindowsAgent.exe"
$smokeScript = Join-Path $PackageDir "smoke-windows-agent.ps1"
$installScript = Join-Path $PackageDir "install-windows-agent.ps1"
$runScript = Join-Path $PackageDir "run-windows-agent.ps1"
$proofScript = Join-Path $PackageDir "prove-windows-agent-artifact.ps1"
$checkReportScript = Join-Path $PackageDir "check-windows-proof-report.ps1"
$manifestPath = Join-Path $PackageDir "manifest.txt"
$script:artifactManifest = @{}
$script:packagedWhisperCLI = ""

Invoke-Step "artifact files" {
    Require-File -Path $agentPath
    Require-File -Path $smokeScript
    Require-File -Path $installScript
    Require-File -Path $runScript
    Require-File -Path $proofScript
    Require-File -Path $checkReportScript
    Require-File -Path $manifestPath

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        Require-File -Path (Join-Path $PackageDir "swiftCore.dll")
    }
}

Invoke-Step "artifact manifest" {
    $script:artifactManifest = Read-Manifest -Path $manifestPath
    foreach ($key in @(
        "agent",
        "output",
        "whisper_cli_mock",
        "smoke_script",
        "run_script",
        "install_script",
        "proof_script",
        "check_report_script",
        "install_proof_config",
        "install_proof_shortcut",
        "local_whisper_install_config",
        "local_whisper_shortcut",
        "swift_runtime_dlls"
    )) {
        Require-ManifestKey -Manifest $script:artifactManifest -Key $key
    }
    $script:packagedWhisperCLI = Resolve-PackagePath -Path $script:artifactManifest["whisper_cli_mock"]
    Require-File -Path $script:packagedWhisperCLI
    Write-Host "manifest_whisper_cli_mock_path=$script:packagedWhisperCLI"
}

if ($UsePackagedWhisperMock) {
    if (![string]::IsNullOrWhiteSpace($WhisperCLI) -or
        ![string]::IsNullOrWhiteSpace($WhisperModel) -or
        ![string]::IsNullOrWhiteSpace($Endpoint) -or
        ![string]::IsNullOrWhiteSpace($Model)) {
        throw "UsePackagedWhisperMock cannot be combined with explicit WhisperCLI/WhisperModel or Endpoint/Model"
    }

    $WhisperCLI = $script:packagedWhisperCLI
    $WhisperModel = $agentPath
    Write-Host "packaged_whisper_cli=$WhisperCLI"
    Write-Host "packaged_whisper_model=$WhisperModel"
}

Invoke-Step "packaged agent doctor" {
    $doctorOutput = & $agentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $doctorOutput
        throw "RomaWindowsAgent doctor failed"
    }
    Write-Host $doctorOutput
}

if ($DoctorOnly) {
    Write-ProofReport -Mode "doctor-only" -IsDoctorOnly $true
    Write-Host ""
    Write-Host "artifact_doctor_only=true"
    exit 0
}

$hasEndpoint = ![string]::IsNullOrWhiteSpace($Endpoint)
$hasModel = ![string]::IsNullOrWhiteSpace($Model)
$hasWhisperCLI = ![string]::IsNullOrWhiteSpace($WhisperCLI)
$hasWhisperModel = ![string]::IsNullOrWhiteSpace($WhisperModel)
$usesCloud = $hasEndpoint -or $hasModel
$usesWhisper = $hasWhisperCLI -or $hasWhisperModel

if ($usesCloud -and $usesWhisper) {
    throw "Endpoint/Model and WhisperCLI/WhisperModel are mutually exclusive"
}

if ($usesCloud -and (!$hasEndpoint -or !$hasModel)) {
    throw "Endpoint and Model must be provided together"
}

if ($usesWhisper -and (!$hasWhisperCLI -or !$hasWhisperModel)) {
    throw "WhisperCLI and WhisperModel must be provided together"
}

if (!$usesCloud -and !$usesWhisper) {
    throw "Pass cloud Endpoint/Model/API key, local WhisperCLI/WhisperModel, or -UsePackagedWhisperMock"
}

if ($usesCloud -and
    [string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
    [string]::IsNullOrWhiteSpace($ApiKeyName)) {
    throw "Cloud proof requires ApiKeyEnv or ApiKeyName"
}

$proofMode = if ($UsePackagedWhisperMock) {
    "packaged-whisper-mock"
} elseif ($usesWhisper) {
    "local-whisper"
} else {
    "cloud"
}

$installArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $InstallDir
)
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    $installArgs += @("-ConfigPath", $ConfigPath)
}
if ($usesWhisper) {
    $installArgs += @("-WhisperCLI", $WhisperCLI, "-WhisperModel", $WhisperModel)
    if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
        $installArgs += @("-WhisperOutputDir", $WhisperOutputDir)
    }
    $whisperArguments = @(
        $WhisperArgument |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    )
    if ($whisperArguments.Count -gt 0) {
        $installArgs += "-WhisperArgument"
        $installArgs += $whisperArguments
    }
} else {
    $installArgs += @("-Endpoint", $Endpoint, "-Model", $Model)
    if (![string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
        $installArgs += @("-ApiKeyEnv", $ApiKeyEnv)
    }
    if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
        $installArgs += @("-ApiKeyName", $ApiKeyName)
    }
    if (![string]::IsNullOrWhiteSpace($SecretDir)) {
        $installArgs += @("-SecretDir", $SecretDir)
    }
}
if (![string]::IsNullOrWhiteSpace($Language)) {
    $installArgs += @("-Language", $Language)
}
if (![string]::IsNullOrWhiteSpace($Prompt)) {
    $installArgs += @("-Prompt", $Prompt)
}
$replacementValues = @(
    $WordReplacement |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) }
)
if ($replacementValues.Count -gt 0) {
    $installArgs += "-WordReplacement"
    $installArgs += $replacementValues
}
if ($UseHoldHook) {
    $installArgs += "-UseHoldHook"
}
if ($UseToggle) {
    $installArgs += "-UseToggle"
}
$installArgs += @("-HoldTimeoutSeconds", "$HoldTimeoutSeconds")
$installArgs += @("-RecordSeconds", "$RecordSeconds")
if ($PasteDictation) {
    $installArgs += "-PasteDictation"
}
if ($RestoreClipboard) {
    $installArgs += "-RestoreClipboard"
}
if ($NoRestoreClipboard) {
    $installArgs += "-NoRestoreClipboard"
}
if ($PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")) {
    $installArgs += @("-ClipboardRestoreDelaySeconds", "$ClipboardRestoreDelaySeconds")
}
if ($RunDictation) {
    $installArgs += "-RunDictation"
}
if ($CreateShortcut) {
    $installArgs += "-CreateShortcut"
    if (![string]::IsNullOrWhiteSpace($ShortcutDir)) {
        $installArgs += @("-ShortcutDir", $ShortcutDir)
    }
}
if ($CreateStartupShortcut) {
    $installArgs += "-CreateStartupShortcut"
    if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
        $installArgs += @("-StartupShortcutDir", $StartupShortcutDir)
    }
}

Invoke-Step "install packaged agent" {
    & $installScript @installArgs
}

Invoke-Step "installed launcher doctor" {
    $installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
    Require-File -Path $installedRun
    $runArgs = @(
        "-InstallDir", $InstallDir,
        "-DoctorOnly"
    )
    if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
        $runArgs += @("-ConfigPath", $ConfigPath)
    }
    & $installedRun @runArgs
}

Write-ProofReport -Mode $proofMode -IsDoctorOnly $false

Write-Host ""
Write-Host "artifact_proof=ok"
Write-Host "package_dir=$PackageDir"
Write-Host "install_dir=$InstallDir"
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    Write-Host "config=$ConfigPath"
}
