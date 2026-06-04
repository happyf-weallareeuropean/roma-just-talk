param(
    [Parameter(Mandatory = $true)]
    [string]$ProofReportPath,
    [switch]$RequireInstall,
    [switch]$RequireShortcut,
    [switch]$RequirePackagedMock,
    [switch]$RequireDictation,
    [switch]$RequirePaste
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

$ProofReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProofReportPath)
if (!(Test-Path -LiteralPath $ProofReportPath)) {
    throw "Proof report was not found: $ProofReportPath"
}

$report = Get-Content -LiteralPath $ProofReportPath -Raw | ConvertFrom-Json

Assert-NonEmptyString -Object $report -Name "generated_at"
Assert-NonEmptyString -Object $report -Name "proof_mode"
Assert-NonEmptyString -Object $report -Name "package_dir"
Assert-NonEmptyString -Object $report -Name "install_dir"

$files = Require-Property -Object $report -Name "files"
Assert-FileProof -Proof (Require-Property -Object $files -Name "packaged_agent") -Name "packaged_agent"

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

if ($RequireDictation) {
    Assert-Boolean -Object $report -Name "run_dictation" -Expected $true
    $config = Require-Property -Object $report -Name "config"
    $outputFile = Require-Property -Object $config -Name "output_file"
    Assert-FileProof -Proof $outputFile -Name "dictation_output" -MinimumBytes 45
}

if ($RequirePaste) {
    Assert-Boolean -Object $report -Name "paste_dictation" -Expected $true
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "should_paste" -Expected $true
}

Write-Host "proof_report_ok=$ProofReportPath"
