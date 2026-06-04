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

function Invoke-GitLines {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    try {
        $output = & git @Arguments 2>$null
        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        return @($output)
    } catch {
        return @()
    }
}

function Get-GitMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    Push-Location $RepositoryRoot
    try {
        $commit = (@(Invoke-GitLines -Arguments @("rev-parse", "--verify", "HEAD")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($commit)) {
            throw "Could not resolve source git commit"
        }

        $branch = (@(Invoke-GitLines -Arguments @("rev-parse", "--abbrev-ref", "HEAD")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = "unknown"
        }

        $repository = (@(Invoke-GitLines -Arguments @("config", "--get", "remote.roma-just-talk.url")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($repository)) {
            $repository = (@(Invoke-GitLines -Arguments @("config", "--get", "remote.origin.url")) -join "`n").Trim()
        }
        if ([string]::IsNullOrWhiteSpace($repository)) {
            $repository = "unknown"
        }

        $statusLines = @(Invoke-GitLines -Arguments @("status", "--porcelain"))
        return @{
            Commit = $commit
            Branch = $branch
            Repository = $repository
            Dirty = ($statusLines.Count -gt 0).ToString().ToLowerInvariant()
        }
    } finally {
        Pop-Location
    }
}

function New-FileProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        path = $Path
        exists = $true
        bytes = $item.Length
    }
}

function Get-CurrentWindowsUserSid {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or $null -eq $identity.User) {
        throw "Current Windows user SID was not available"
    }

    return [string]$identity.User.Value
}

function Write-LaptopPreflightCheckerSmokeReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportPath,
        [Parameter(Mandatory = $true)]
        [string]$PackageDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperCLIPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperModelPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$GitMetadata
    )

    New-Item -ItemType Directory -Force -Path $ProofDir | Out-Null
    $micPreflightPath = Join-Path $ProofDir "ci-mic-preflight.wav"
    $wavBytes = [byte[]]::new(46)
    $riffBytes = [System.Text.Encoding]::ASCII.GetBytes("RIFF")
    [System.Array]::Copy($riffBytes, $wavBytes, $riffBytes.Length)
    [System.IO.File]::WriteAllBytes($micPreflightPath, $wavBytes)

    $report = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        proof_session_id = [guid]::NewGuid().ToString("D")
        proof_mode = "windows-laptop-preflight"
        preflight_only = $true
        package_dir = $PackageDir
        proof_dir = $ProofDir
        manifest = [ordered]@{
            source_repository = $GitMetadata.Repository
            source_branch = $GitMetadata.Branch
            source_commit = $GitMetadata.Commit
            source_dirty = $GitMetadata.Dirty
        }
        package_identity = [ordered]@{
            algorithm = "sha256"
            fingerprint = "0000000000000000000000000000000000000000000000000000000000000000"
            entry_count = 0
        }
        os = [ordered]@{
            platform = [System.Environment]::OSVersion.Platform.ToString()
            version = [System.Environment]::OSVersion.VersionString
            machine = $env:COMPUTERNAME
            user_name = $env:USERNAME
            user_domain = $env:USERDOMAIN
            user_sid = Get-CurrentWindowsUserSid
        }
        preflights = [ordered]@{
            hotkey_delivery = $true
            microphone = $true
            local_whisper = $true
        }
        preflight_outputs = [ordered]@{
            hotkey_delivery = [ordered]@{
                output_present = $true
                waiting_for_hold = $true
                key_down = $true
                key_up = $true
                observed_events_present = $true
            }
            microphone = [ordered]@{
                output_present = $true
                wrote_present = $true
                sample_rate_16000 = $true
                channels_mono = $true
            }
            local_whisper = [ordered]@{
                output_present = $true
                transcription_client_whisper = $true
                network_required_false = $true
                executable_present = $true
                model_file_present = $true
            }
        }
        files = [ordered]@{
            proof_agent = New-FileProof -Path $ProofAgentPath
            mic_preflight_wav = New-FileProof -Path $micPreflightPath
            whisper_cli = New-FileProof -Path $WhisperCLIPath
            whisper_model = New-FileProof -Path $WhisperModelPath
        }
    }

    $report |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host "laptop_preflight_checker_smoke_report=$ReportPath"
}

function Write-LaptopProofGuide {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    @'
Roma Just Talk Windows laptop proof

Run these commands from this artifact directory.

Preflight only, before cloud credentials:

powershell -ExecutionPolicy Bypass -File .\run-windows-laptop-proof.ps1 -PackageDir . -ProofDir C:\tmp\roma-windows-laptop-proof -PreflightOnly -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin

Full laptop proof, after cloud credentials and local whisper are ready:

powershell -ExecutionPolicy Bypass -File .\run-windows-laptop-proof.ps1 -PackageDir . -ProofDir C:\tmp\roma-windows-laptop-proof -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin

Expected proof markers:

proof_set_ok=laptop-preflight
windows_laptop_preflight_ok=true
windows_laptop_preflight_report=C:\tmp\roma-windows-laptop-proof\preflight-proof.json
proof_set_laptop_preflight_package_fingerprint=
proof_set_laptop_preflight_matches_full=true
proof_set_source_dirty=false
proof_set_ok=full-laptop
windows_laptop_proof_ok=true

Full proof validates four JSON reports: preflight, cloud dictation, local whisper dictation, and local whisper Notepad paste.
Do not claim Windows support until the full laptop proof passes on the target Windows machine.
'@ | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "laptop_proof_guide=$OutputPath"
}

$packageRoot = Resolve-Path "$PSScriptRoot\.."
if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "package-windows-agent.ps1 must run on Windows so packaged executables and Swift runtime DLLs are Windows artifacts"
}

$gitMetadata = Get-GitMetadata -RepositoryRoot $packageRoot
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $packageRoot
try {
    Invoke-Step "build RomaWindowsAgent" {
        swift build -c $Configuration --product RomaWindowsAgent
    }

    Invoke-Step "build RomaProofAgent" {
        swift build -c $Configuration --product RomaProofAgent
    }

    Invoke-Step "build RomaWhisperCLIMock" {
        swift build -c $Configuration --product RomaWhisperCLIMock
    }

    $buildDirectory = Join-Path $packageRoot ".build"
    $agentSource = Resolve-ProductExecutable -BuildDirectory $buildDirectory -Configuration $Configuration -Name "RomaWindowsAgent"
    $proofAgentSource = Resolve-ProductExecutable -BuildDirectory $buildDirectory -Configuration $Configuration -Name "RomaProofAgent"
    $mockWhisperSource = Resolve-ProductExecutable -BuildDirectory $buildDirectory -Configuration $Configuration -Name "RomaWhisperCLIMock"
    $agentOutput = Join-Path $OutputDir "RomaWindowsAgent.exe"
    $proofAgentOutput = Join-Path $OutputDir "RomaProofAgent.exe"
    $mockWhisperOutput = Join-Path $OutputDir "RomaWhisperCLIMock.exe"
    $smokeScriptSource = Join-Path $PSScriptRoot "smoke-windows-agent.ps1"
    $smokeScriptOutput = Join-Path $OutputDir "smoke-windows-agent.ps1"
    $runScriptSource = Join-Path $PSScriptRoot "run-windows-agent.ps1"
    $runScriptOutput = Join-Path $OutputDir "run-windows-agent.ps1"
    $installScriptSource = Join-Path $PSScriptRoot "install-windows-agent.ps1"
    $installScriptOutput = Join-Path $OutputDir "install-windows-agent.ps1"
    $proofScriptSource = Join-Path $PSScriptRoot "prove-windows-agent-artifact.ps1"
    $proofScriptOutput = Join-Path $OutputDir "prove-windows-agent-artifact.ps1"
    $laptopProofScriptSource = Join-Path $PSScriptRoot "run-windows-laptop-proof.ps1"
    $laptopProofScriptOutput = Join-Path $OutputDir "run-windows-laptop-proof.ps1"
    $checkReportScriptSource = Join-Path $PSScriptRoot "check-windows-proof-report.ps1"
    $checkReportScriptOutput = Join-Path $OutputDir "check-windows-proof-report.ps1"
    $checkSetScriptSource = Join-Path $PSScriptRoot "check-windows-proof-set.ps1"
    $checkSetScriptOutput = Join-Path $OutputDir "check-windows-proof-set.ps1"
    $laptopProofGuideOutput = Join-Path $OutputDir "WINDOWS-LAPTOP-PROOF.txt"
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
    $laptopPreflightCheckerSmokeDir = Join-Path $OutputDir "laptop-preflight-checker-smoke"
    $laptopPreflightCheckerSmokeReport = Join-Path $laptopPreflightCheckerSmokeDir "preflight-proof.json"

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

        Copy-Item -LiteralPath $proofAgentSource.FullName -Destination $proofAgentOutput -Force
        $proofAgentItem = Get-Item -LiteralPath $proofAgentOutput
        if ($proofAgentItem.Length -le 0) {
            throw "RomaProofAgent.exe is empty: $proofAgentOutput"
        }
        Write-Host "proof_agent_exe=$proofAgentOutput"
        Write-Host "proof_agent_bytes=$($proofAgentItem.Length)"

        $proofAgentPdbSource = [System.IO.Path]::ChangeExtension($proofAgentSource.FullName, ".pdb")
        if (Test-Path -LiteralPath $proofAgentPdbSource) {
            $proofAgentPdbOutput = Join-Path $OutputDir "RomaProofAgent.pdb"
            Copy-Item -LiteralPath $proofAgentPdbSource -Destination $proofAgentPdbOutput -Force
            Write-Host "proof_agent_pdb=$proofAgentPdbOutput"
        }

        Copy-Item -LiteralPath $mockWhisperSource.FullName -Destination $mockWhisperOutput -Force
        $mockWhisperItem = Get-Item -LiteralPath $mockWhisperOutput
        if ($mockWhisperItem.Length -le 0) {
            throw "RomaWhisperCLIMock.exe is empty: $mockWhisperOutput"
        }
        Write-Host "whisper_cli_mock=$mockWhisperOutput"
        Write-Host "whisper_cli_mock_bytes=$($mockWhisperItem.Length)"

        Copy-Item -LiteralPath $smokeScriptSource -Destination $smokeScriptOutput -Force
        Write-Host "smoke_script=$smokeScriptOutput"
        Copy-Item -LiteralPath $runScriptSource -Destination $runScriptOutput -Force
        Write-Host "run_script=$runScriptOutput"
        Copy-Item -LiteralPath $installScriptSource -Destination $installScriptOutput -Force
        Write-Host "install_script=$installScriptOutput"
        Copy-Item -LiteralPath $proofScriptSource -Destination $proofScriptOutput -Force
        Write-Host "proof_script=$proofScriptOutput"
        Copy-Item -LiteralPath $laptopProofScriptSource -Destination $laptopProofScriptOutput -Force
        Write-Host "laptop_proof_script=$laptopProofScriptOutput"
        Copy-Item -LiteralPath $checkReportScriptSource -Destination $checkReportScriptOutput -Force
        Write-Host "check_report_script=$checkReportScriptOutput"
        Copy-Item -LiteralPath $checkSetScriptSource -Destination $checkSetScriptOutput -Force
        Write-Host "check_set_script=$checkSetScriptOutput"
        Write-LaptopProofGuide -OutputPath $laptopProofGuideOutput
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

    Invoke-Step "packaged proof agent smoke" {
        $proofAgentOutputText = & $proofAgentOutput doctor 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $proofAgentOutputText
            throw "RomaProofAgent doctor failed"
        }
        Write-Host $proofAgentOutputText
        Assert-OutputContains -Output $proofAgentOutputText -Expected "default_record_seconds=2.0"
        Assert-OutputContains -Output $proofAgentOutputText -Expected "default_hold_timeout_seconds=15.0"
        Assert-OutputContains -Output $proofAgentOutputText -Expected "default_hold_timeout_milliseconds=15000"
        Assert-OutputContains -Output $proofAgentOutputText -Expected "default_clipboard_restore_delay_seconds=2.0"
        Assert-OutputContains -Output $proofAgentOutputText -Expected "maximum_clipboard_restore_delay_seconds=4294967.295"
        Assert-OutputContains -Output $proofAgentOutputText -Expected "windows_paste_adapter_source=true"
        Assert-OutputContains -Output $proofAgentOutputText -Expected "windows_dictation_runtime_uses_pipeline_source=true"
        Assert-OutputContains -Output $proofAgentOutputText -Expected "windows_dictation_proof_source=true"
    }

    Invoke-Step "packaged listener smoke" {
        $listenerOutputText = & $agentOutput listen `
            --config $configPath `
            --max-sessions 0 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $listenerOutputText
            throw "RomaWindowsAgent listen smoke failed"
        }
        Write-Host $listenerOutputText
        Assert-OutputContains -Output $listenerOutputText -Expected "mode=listen"
        Assert-OutputContains -Output $listenerOutputText -Expected "listen_completed_sessions=0"
    }

    Invoke-Step "packaged local whisper config smoke" {
        & $smokeScriptOutput `
            -AgentPath $agentOutput `
            -OutputDir (Join-Path $OutputDir "local-whisper-smoke") `
            -ConfigPath $localWhisperConfigPath `
            -WhisperCLI $mockWhisperOutput `
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
            -WhisperCLI $mockWhisperOutput `
            -WhisperModel $agentOutput `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0 `
            -CreateShortcut `
            -ShortcutDir $localWhisperShortcutDir
    }

    Invoke-Step "laptop preflight report checker smoke" {
        Write-LaptopPreflightCheckerSmokeReport `
            -ReportPath $laptopPreflightCheckerSmokeReport `
            -PackageDir $OutputDir `
            -ProofDir $laptopPreflightCheckerSmokeDir `
            -ProofAgentPath $proofAgentOutput `
            -WhisperCLIPath $mockWhisperOutput `
            -WhisperModelPath $agentOutput `
            -GitMetadata $gitMetadata
        $checkerOutputText = & $checkSetScriptOutput `
            -LaptopPreflightReportPath $laptopPreflightCheckerSmokeReport `
            -RequireLaptopPreflight 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $checkerOutputText
            throw "Laptop preflight report checker smoke failed"
        }
        Write-Host $checkerOutputText
        Assert-OutputContains -Output $checkerOutputText -Expected "proof_set_ok=laptop-preflight"
    }

    $manifestPath = Join-Path $OutputDir "manifest.txt"
    $agentFile = Get-Item -LiteralPath $agentOutput
    @(
        "agent=RomaWindowsAgent",
        "configuration=$Configuration",
        "source_repository=$($gitMetadata.Repository)",
        "source_branch=$($gitMetadata.Branch)",
        "source_commit=$($gitMetadata.Commit)",
        "source_dirty=$($gitMetadata.Dirty)",
        "source=$($agentSource.FullName)",
        "output=$agentOutput",
        "proof_agent=RomaProofAgent.exe",
        "sample_config=$configPath",
        "sample_local_whisper_config=$localWhisperConfigPath",
        "whisper_cli_mock=RomaWhisperCLIMock.exe",
        "install_proof_dir=$installProofDir",
        "install_proof_config=$installProofConfigPath",
        "install_proof_shortcut=$shortcutPath",
        "local_whisper_install_proof_dir=$localWhisperInstallProofDir",
        "local_whisper_install_config=$localWhisperInstallConfigPath",
        "local_whisper_shortcut=$localWhisperShortcutPath",
        "laptop_preflight_checker_smoke_report=$laptopPreflightCheckerSmokeReport",
        "smoke_script=$smokeScriptOutput",
        "run_script=$runScriptOutput",
        "install_script=$installScriptOutput",
        "proof_script=$proofScriptOutput",
        "laptop_proof_script=$laptopProofScriptOutput",
        "laptop_proof_guide=$laptopProofGuideOutput",
        "check_report_script=$checkReportScriptOutput",
        "check_set_script=$checkSetScriptOutput",
        "swift_runtime_dir=$($swiftRuntime.Directory)",
        "swift_runtime_dlls=$($swiftRuntime.DllCount)",
        "bytes=$($agentFile.Length)"
    ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host ""
    Write-Host "package_artifacts=$OutputDir"
    Write-Host "source_commit=$($gitMetadata.Commit)"
    Write-Host "source_dirty=$($gitMetadata.Dirty)"
    Write-Host "manifest=$manifestPath"
} finally {
    Pop-Location
}
