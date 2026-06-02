param(
    [string]$OutputDir = "$PSScriptRoot\..\proof-artifacts\windows-agent",
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release"
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

function Assert-OutputContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Expected
    )

    if (!$Output.Contains($Expected)) {
        throw "Expected command output to contain '$Expected'"
    }

    Write-Host "asserted_output=$Expected"
}

function Resolve-AgentExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BuildDirectory,
        [Parameter(Mandatory = $true)]
        [string]$Configuration
    )

    $preferred = Join-Path $BuildDirectory "$Configuration\RomaWindowsAgent.exe"
    if (Test-Path -LiteralPath $preferred) {
        return Get-Item -LiteralPath $preferred
    }

    $matchingConfiguration = Get-ChildItem -Path $BuildDirectory -Filter "RomaWindowsAgent.exe" -Recurse |
        Where-Object { $_.FullName -like "*\$Configuration\*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($matchingConfiguration) {
        return $matchingConfiguration
    }

    $anyExecutable = Get-ChildItem -Path $BuildDirectory -Filter "RomaWindowsAgent.exe" -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($anyExecutable) {
        return $anyExecutable
    }

    throw "RomaWindowsAgent.exe was not found under $BuildDirectory"
}

$packageRoot = Resolve-Path "$PSScriptRoot\.."
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $packageRoot
try {
    Invoke-Step "build RomaWindowsAgent" {
        swift build -c $Configuration --product RomaWindowsAgent
    }

    $buildDirectory = Join-Path $packageRoot ".build"
    $agentSource = Resolve-AgentExecutable -BuildDirectory $buildDirectory -Configuration $Configuration
    $agentOutput = Join-Path $OutputDir "RomaWindowsAgent.exe"

    Invoke-Step "copy agent executable" {
        Copy-Item -LiteralPath $agentSource.FullName -Destination $agentOutput -Force
        $agentItem = Get-Item -LiteralPath $agentOutput
        if ($agentItem.Length -le 0) {
            throw "RomaWindowsAgent.exe is empty: $agentOutput"
        }
        Write-Host "agent_exe=$agentOutput"
        Write-Host "bytes=$($agentItem.Length)"

        $pdbSource = [System.IO.Path]::ChangeExtension($agentSource.FullName, ".pdb")
        if (Test-Path -LiteralPath $pdbSource) {
            $pdbOutput = Join-Path $OutputDir "RomaWindowsAgent.pdb"
            Copy-Item -LiteralPath $pdbSource -Destination $pdbOutput -Force
            Write-Host "agent_pdb=$pdbOutput"
        }
    }

    Invoke-Step "agent doctor" {
        $doctorOutput = & $agentOutput doctor 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $doctorOutput
            throw "packaged RomaWindowsAgent doctor failed"
        }
        Write-Host $doctorOutput
        Assert-OutputContains -Output $doctorOutput -Expected "agent=roma-windows-agent"
        if ($isWindowsHost) {
            Assert-OutputContains -Output $doctorOutput -Expected "runtime_available=true"
        }
    }

    $configPath = Join-Path $OutputDir "sample-windows-agent.json"
    Invoke-Step "agent config sample" {
        $configOutput = & $agentOutput write-config `
            --config $configPath `
            --endpoint "http://127.0.0.1:1/v1/audio/transcriptions" `
            --model "mock-whisper" `
            --api-key-env "PATH" `
            --hold-hook `
            --paste `
            --replace "just talk=roma-just-talk" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $configOutput
            throw "packaged RomaWindowsAgent write-config failed"
        }
        Write-Host $configOutput
        Assert-OutputContains -Output $configOutput -Expected "written=true"
        Assert-OutputContains -Output $configOutput -Expected "config=$configPath"
        if (!(Test-Path -LiteralPath $configPath)) {
            throw "sample Windows agent config was not created: $configPath"
        }
    }

    $manifestPath = Join-Path $OutputDir "manifest.txt"
    $agentFile = Get-Item -LiteralPath $agentOutput
    @(
        "agent=RomaWindowsAgent",
        "configuration=$Configuration",
        "source=$($agentSource.FullName)",
        "output=$agentOutput",
        "sample_config=$configPath",
        "bytes=$($agentFile.Length)"
    ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host ""
    Write-Host "package_artifacts=$OutputDir"
    Write-Host "manifest=$manifestPath"
} finally {
    Pop-Location
}
