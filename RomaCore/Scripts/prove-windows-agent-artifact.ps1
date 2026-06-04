param(
    [string]$PackageDir = "",
    [string]$InstallDir = "",
    [string]$ConfigPath = "",
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
    [switch]$RunDictation,
    [switch]$CreateShortcut,
    [string]$ShortcutDir = "",
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

if (!$DoctorOnly -and !$usesCloud -and !$usesWhisper) {
    throw "Pass cloud Endpoint/Model/API key or local WhisperCLI/WhisperModel, or use -DoctorOnly"
}

if ($usesCloud -and
    [string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
    [string]::IsNullOrWhiteSpace($ApiKeyName)) {
    throw "Cloud proof requires ApiKeyEnv or ApiKeyName"
}

$agentPath = Join-Path $PackageDir "RomaWindowsAgent.exe"
$smokeScript = Join-Path $PackageDir "smoke-windows-agent.ps1"
$installScript = Join-Path $PackageDir "install-windows-agent.ps1"
$runScript = Join-Path $PackageDir "run-windows-agent.ps1"
$proofScript = Join-Path $PackageDir "prove-windows-agent-artifact.ps1"
$manifestPath = Join-Path $PackageDir "manifest.txt"

Invoke-Step "artifact files" {
    Require-File -Path $agentPath
    Require-File -Path $smokeScript
    Require-File -Path $installScript
    Require-File -Path $runScript
    Require-File -Path $proofScript
    Require-File -Path $manifestPath

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        Require-File -Path (Join-Path $PackageDir "swiftCore.dll")
    }
}

Invoke-Step "artifact manifest" {
    $manifest = Read-Manifest -Path $manifestPath
    foreach ($key in @(
        "agent",
        "output",
        "smoke_script",
        "run_script",
        "install_script",
        "proof_script",
        "install_proof_config",
        "install_proof_shortcut",
        "local_whisper_install_config",
        "local_whisper_shortcut",
        "swift_runtime_dlls"
    )) {
        Require-ManifestKey -Manifest $manifest -Key $key
    }
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
    Write-Host ""
    Write-Host "artifact_doctor_only=true"
    exit 0
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
    foreach ($argument in $WhisperArgument) {
        if (![string]::IsNullOrWhiteSpace($argument)) {
            $installArgs += @("-WhisperArgument", $argument)
        }
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
foreach ($replacement in $WordReplacement) {
    if (![string]::IsNullOrWhiteSpace($replacement)) {
        $installArgs += @("-WordReplacement", $replacement)
    }
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

Write-Host ""
Write-Host "artifact_proof=ok"
Write-Host "package_dir=$PackageDir"
Write-Host "install_dir=$InstallDir"
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    Write-Host "config=$ConfigPath"
}
