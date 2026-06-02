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

function Resolve-SwiftRuntimeDirectory {
    $pathSeparator = [System.IO.Path]::PathSeparator
    $pathDirectories = $env:PATH -split [regex]::Escape($pathSeparator) |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) }

    foreach ($directory in $pathDirectories) {
        $candidate = Join-Path $directory "swiftCore.dll"
        if (Test-Path -LiteralPath $candidate) {
            return Get-Item -LiteralPath $directory
        }
    }

    return $null
}

function Copy-SwiftRuntimeLibraries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $runtimeDirectory = Resolve-SwiftRuntimeDirectory
    if (!$runtimeDirectory) {
        Write-Host "swift_runtime_dir=not_found"
        Write-Host "swift_runtime_dlls=0"
        return @{
            Directory = ""
            Count = 0
        }
    }

    $runtimeLibraries = Get-ChildItem -LiteralPath $runtimeDirectory.FullName -Filter "*.dll" |
        Sort-Object Name
    foreach ($library in $runtimeLibraries) {
        Copy-Item -LiteralPath $library.FullName -Destination (Join-Path $OutputDir $library.Name) -Force
    }

    Write-Host "swift_runtime_dir=$($runtimeDirectory.FullName)"
    Write-Host "swift_runtime_dlls=$($runtimeLibraries.Count)"

    return @{
        Directory = $runtimeDirectory.FullName
        Count = $runtimeLibraries.Count
    }
}

$packageRoot = Resolve-Path "$PSScriptRoot\.."
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $packageRoot
try {
    Invoke-Step "build RomaWindowsAgent" {
        swift build -c $Configuration --product RomaWindowsAgent
    }

    $buildDirectory = Join-Path $packageRoot ".build"
    $agentSource = Resolve-AgentExecutable -BuildDirectory $buildDirectory -Configuration $Configuration
    $agentOutput = Join-Path $OutputDir "RomaWindowsAgent.exe"
    $smokeScriptSource = Join-Path $PSScriptRoot "smoke-windows-agent.ps1"
    $smokeScriptOutput = Join-Path $OutputDir "smoke-windows-agent.ps1"
    $configPath = Join-Path $OutputDir "sample-windows-agent.json"

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

        Copy-Item -LiteralPath $smokeScriptSource -Destination $smokeScriptOutput -Force
        Write-Host "smoke_script=$smokeScriptOutput"
    }

    $swiftRuntime = @{}
    Invoke-Step "copy Swift runtime libraries" {
        $script:swiftRuntime = Copy-SwiftRuntimeLibraries -OutputDir $OutputDir
    }

    Invoke-Step "packaged agent smoke" {
        & $smokeScriptOutput `
            -AgentPath $agentOutput `
            -OutputDir $OutputDir `
            -ConfigPath $configPath
    }

    $manifestPath = Join-Path $OutputDir "manifest.txt"
    $agentFile = Get-Item -LiteralPath $agentOutput
    @(
        "agent=RomaWindowsAgent",
        "configuration=$Configuration",
        "source=$($agentSource.FullName)",
        "output=$agentOutput",
        "sample_config=$configPath",
        "smoke_script=$smokeScriptOutput",
        "swift_runtime_dir=$($swiftRuntime.Directory)",
        "swift_runtime_dlls=$($swiftRuntime.Count)",
        "bytes=$($agentFile.Length)"
    ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host ""
    Write-Host "package_artifacts=$OutputDir"
    Write-Host "manifest=$manifestPath"
} finally {
    Pop-Location
}
