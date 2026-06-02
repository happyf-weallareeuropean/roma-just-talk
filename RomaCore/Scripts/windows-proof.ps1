param(
    [string]$OutputDir = "$PSScriptRoot\..\proof-artifacts\windows",
    [int]$RecordSeconds = 2,
    [string]$PasteText = "roma just talk proof",
    [switch]$SkipMic,
    [switch]$RunInteractiveHotkey,
    [switch]$RunInteractivePaste
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
        swift run RomaProofAgent doctor
    }

    $coreProof = Join-Path $OutputDir "core-proof.wav"
    Invoke-Step "core pre-roll wav proof" {
        swift run RomaProofAgent pre-roll-proof --out $coreProof
        Assert-FileWithBytes -Path $coreProof
    }

    Invoke-Step "miniaudio capture doctor" {
        swift run RomaProofAgent miniaudio-capture-doctor
    }

    if ($SkipMic) {
        Write-Host ""
        Write-Host "== miniaudio mic proof skipped =="
    } else {
        $micProof = Join-Path $OutputDir "mic-proof.wav"
        Invoke-Step "miniaudio mic proof" {
            swift run RomaProofAgent miniaudio-record-proof --out $micProof --seconds $RecordSeconds
            Assert-FileWithBytes -Path $micProof
        }
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

    Invoke-Step "windows paste doctor" {
        swift run RomaProofAgent windows-paste-doctor
    }

    if ($RunInteractivePaste) {
        Invoke-Step "windows paste proof" {
            Write-Host "Focus Notepad or another normal-integrity text field before this step."
            swift run RomaProofAgent windows-paste-proof --text $PasteText
        }
    } else {
        Write-Host ""
        Write-Host "== windows paste proof skipped =="
        Write-Host "rerun with -RunInteractivePaste after focusing Notepad"
    }

    Write-Host ""
    Write-Host "proof_artifacts=$OutputDir"
} finally {
    Pop-Location
}
