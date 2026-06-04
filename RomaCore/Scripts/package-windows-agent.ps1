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

function Resolve-ProductExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BuildDirectory,
        [Parameter(Mandatory = $true)]
        [string]$Configuration,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $preferred = Join-Path $BuildDirectory "$Configuration\$Name.exe"
    if (Test-Path -LiteralPath $preferred) {
        return Get-Item -LiteralPath $preferred
    }

    $matchingConfiguration = Get-ChildItem -Path $BuildDirectory -Filter "$Name.exe" -Recurse |
        Where-Object { $_.FullName -like "*\$Configuration\*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($matchingConfiguration) {
        return $matchingConfiguration
    }

    $anyExecutable = Get-ChildItem -Path $BuildDirectory -Filter "$Name.exe" -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($anyExecutable) {
        return $anyExecutable
    }

    $nonWindowsPreferred = Join-Path $BuildDirectory "$Configuration\$Name"
    if (Test-Path -LiteralPath $nonWindowsPreferred) {
        return Get-Item -LiteralPath $nonWindowsPreferred
    }

    throw "$Name executable was not found under $BuildDirectory"
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
            DllCount = 0
        }
    }

    $runtimeLibraries = @(
        Get-ChildItem -LiteralPath $runtimeDirectory.FullName -Filter "*.dll" |
            Sort-Object Name
    )
    foreach ($library in $runtimeLibraries) {
        Copy-Item -LiteralPath $library.FullName -Destination (Join-Path $OutputDir $library.Name) -Force
    }

    Write-Host "swift_runtime_dir=$($runtimeDirectory.FullName)"
    Write-Host "swift_runtime_dlls=$($runtimeLibraries.Count)"

    return @{
        Directory = $runtimeDirectory.FullName
        DllCount = $runtimeLibraries.Count
    }
}

function Assert-SwiftRuntimePackaged {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [Parameter(Mandatory = $true)]
        [hashtable]$SwiftRuntime
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return
    }

    if ($SwiftRuntime.DllCount -le 0) {
        throw "Swift runtime DLLs were not copied into the Windows agent artifact"
    }

    $swiftCore = Join-Path $OutputDir "swiftCore.dll"
    if (!(Test-Path -LiteralPath $swiftCore)) {
        throw "swiftCore.dll was not copied into the Windows agent artifact"
    }

    Write-Host "asserted_runtime_dll=swiftCore.dll"
}

$packageRoot = Resolve-Path "$PSScriptRoot\.."
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $packageRoot
try {
    Invoke-Step "build RomaWindowsAgent" {
        swift build -c $Configuration --product RomaWindowsAgent
    }

    Invoke-Step "build RomaWhisperCLIMock" {
        swift build -c $Configuration --product RomaWhisperCLIMock
    }

    $buildDirectory = Join-Path $packageRoot ".build"
    $agentSource = Resolve-ProductExecutable -BuildDirectory $buildDirectory -Configuration $Configuration -Name "RomaWindowsAgent"
    $mockWhisperSource = Resolve-ProductExecutable -BuildDirectory $buildDirectory -Configuration $Configuration -Name "RomaWhisperCLIMock"
    $agentOutput = Join-Path $OutputDir "RomaWindowsAgent.exe"
    $smokeScriptSource = Join-Path $PSScriptRoot "smoke-windows-agent.ps1"
    $smokeScriptOutput = Join-Path $OutputDir "smoke-windows-agent.ps1"
    $runScriptSource = Join-Path $PSScriptRoot "run-windows-agent.ps1"
    $runScriptOutput = Join-Path $OutputDir "run-windows-agent.ps1"
    $installScriptSource = Join-Path $PSScriptRoot "install-windows-agent.ps1"
    $installScriptOutput = Join-Path $OutputDir "install-windows-agent.ps1"
    $configPath = Join-Path $OutputDir "sample-windows-agent.json"
    $localWhisperConfigPath = Join-Path $OutputDir "sample-local-whisper-agent.json"
    $installProofDir = Join-Path $OutputDir "install-proof"
    $installProofConfigPath = Join-Path $installProofDir "windows-agent.json"
    $shortcutDir = Join-Path $OutputDir "shortcuts"
    $shortcutPath = Join-Path $shortcutDir "Roma Just Talk Agent.lnk"
    $localWhisperInstallProofDir = Join-Path $OutputDir "install-proof-local-whisper"
    $localWhisperInstallConfigPath = Join-Path $localWhisperInstallProofDir "windows-agent.json"
    $localWhisperShortcutDir = Join-Path $OutputDir "shortcuts-local-whisper"
    $localWhisperShortcutPath = Join-Path $localWhisperShortcutDir "Roma Just Talk Agent.lnk"

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
        Copy-Item -LiteralPath $runScriptSource -Destination $runScriptOutput -Force
        Write-Host "run_script=$runScriptOutput"
        Copy-Item -LiteralPath $installScriptSource -Destination $installScriptOutput -Force
        Write-Host "install_script=$installScriptOutput"
    }

    $swiftRuntime = @{}
    Invoke-Step "copy Swift runtime libraries" {
        $script:swiftRuntime = Copy-SwiftRuntimeLibraries -OutputDir $OutputDir
        Assert-SwiftRuntimePackaged -OutputDir $OutputDir -SwiftRuntime $script:swiftRuntime
    }

    Invoke-Step "packaged agent smoke" {
        & $smokeScriptOutput `
            -AgentPath $agentOutput `
            -OutputDir $OutputDir `
            -ConfigPath $configPath `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0
    }

    Invoke-Step "packaged local whisper config smoke" {
        & $smokeScriptOutput `
            -AgentPath $agentOutput `
            -OutputDir (Join-Path $OutputDir "local-whisper-smoke") `
            -ConfigPath $localWhisperConfigPath `
            -WhisperCLI $mockWhisperSource.FullName `
            -WhisperModel $agentOutput `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0
    }

    Invoke-Step "packaged agent install smoke" {
        & $installScriptOutput `
            -PackageDir $OutputDir `
            -InstallDir $installProofDir `
            -ConfigPath $installProofConfigPath `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0 `
            -CreateShortcut `
            -AllowSmokeShortcut `
            -ShortcutDir $shortcutDir
    }

    Invoke-Step "packaged local whisper install smoke" {
        & $installScriptOutput `
            -PackageDir $OutputDir `
            -InstallDir $localWhisperInstallProofDir `
            -ConfigPath $localWhisperInstallConfigPath `
            -WhisperCLI $mockWhisperSource.FullName `
            -WhisperModel $agentOutput `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0 `
            -CreateShortcut `
            -ShortcutDir $localWhisperShortcutDir
    }

    $manifestPath = Join-Path $OutputDir "manifest.txt"
    $agentFile = Get-Item -LiteralPath $agentOutput
    @(
        "agent=RomaWindowsAgent",
        "configuration=$Configuration",
        "source=$($agentSource.FullName)",
        "output=$agentOutput",
        "sample_config=$configPath",
        "sample_local_whisper_config=$localWhisperConfigPath",
        "whisper_cli_mock=$($mockWhisperSource.FullName)",
        "install_proof_dir=$installProofDir",
        "install_proof_config=$installProofConfigPath",
        "install_proof_shortcut=$shortcutPath",
        "local_whisper_install_proof_dir=$localWhisperInstallProofDir",
        "local_whisper_install_config=$localWhisperInstallConfigPath",
        "local_whisper_shortcut=$localWhisperShortcutPath",
        "smoke_script=$smokeScriptOutput",
        "run_script=$runScriptOutput",
        "install_script=$installScriptOutput",
        "swift_runtime_dir=$($swiftRuntime.Directory)",
        "swift_runtime_dlls=$($swiftRuntime.DllCount)",
        "bytes=$($agentFile.Length)"
    ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host ""
    Write-Host "package_artifacts=$OutputDir"
    Write-Host "manifest=$manifestPath"
} finally {
    Pop-Location
}
