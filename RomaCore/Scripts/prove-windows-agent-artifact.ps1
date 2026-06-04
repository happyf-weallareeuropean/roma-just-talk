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
    [switch]$RunNotepadPasteProof,
    [string]$NotepadPasteProofPath = "",
    [string]$PasteProofText = "roma just talk proof",
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

function Invoke-ProofAgentDoctorCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    Write-Host ""
    Write-Host "-- $Name --"
    $output = & $script:proofAgentPath $Command 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaProofAgent $Command failed"
    }

    Write-Host $output
    return $output
}

function Invoke-PackagedListenerSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $output = & $agentPath listen `
        --config $ConfigPath `
        --max-sessions 0 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaWindowsAgent listen smoke failed"
    }

    Write-Host $output
    Assert-OutputContains -Output $output -Expected "mode=listen"
    Assert-OutputContains -Output $output -Expected "listen_completed_sessions=0"
    return $output
}

function Invoke-InstalledListenerSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $output = & $RunScriptPath `
        -InstallDir $InstallDir `
        -ConfigPath $ConfigPath `
        -Listen `
        -MaxSessions 0 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "Installed launcher listen smoke failed"
    }

    Write-Host $output
    Assert-OutputContains -Output $output -Expected "mode=RomaWindowsAgent listen"
    Assert-OutputContains -Output $output -Expected "listen_completed_sessions=0"
    return $output
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

function Get-FileHashProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $proof = Get-FileProof -Path $Path
    $proof["sha256"] = ""
    if ($proof["exists"]) {
        $proof["sha256"] = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    return $proof
}

function Get-PackageIdentityHash {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Entries
    )

    $inputText = [string]::Join("`n", $Entries)
    $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($inputText)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($inputBytes)
    } finally {
        $sha256.Dispose()
    }

    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
}

function Get-PackageIdentityProof {
    $relativePaths = @(
        "RomaWindowsAgent.exe",
        "RomaProofAgent.exe",
        "RomaWhisperCLIMock.exe",
        "smoke-windows-agent.ps1",
        "run-windows-agent.ps1",
        "install-windows-agent.ps1",
        "prove-windows-agent-artifact.ps1",
        "run-windows-laptop-proof.ps1",
        "check-windows-proof-report.ps1",
        "check-windows-proof-set.ps1",
        "manifest.txt"
    )

    $dlls = @(
        Get-ChildItem -LiteralPath $PackageDir -Filter "*.dll" |
            Sort-Object Name
    )
    foreach ($dll in $dlls) {
        $relativePaths += $dll.Name
    }

    $files = [ordered]@{}
    $entries = @()
    foreach ($relativePath in $relativePaths) {
        $path = Join-Path $PackageDir $relativePath
        $proof = Get-FileHashProof -Path $path
        $files[$relativePath] = $proof
        if (!$proof["exists"] -or [string]::IsNullOrWhiteSpace([string]$proof["sha256"])) {
            throw "Package identity file was not hashable: $path"
        }

        $entries += ("{0}|{1}|{2}" -f $relativePath, $proof["bytes"], $proof["sha256"])
    }

    return [ordered]@{
        algorithm = "sha256"
        fingerprint = (Get-PackageIdentityHash -Entries $entries)
        entry_count = $entries.Count
        entries = $entries
        files = $files
    }
}

function Get-ShortcutProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [string]$ConfigPath = "",
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $proof = Get-FileProof -Path $Path
    if (!$proof["exists"] -or
        [System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $proof
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $targetPath = [string]$shortcut.TargetPath
    $arguments = [string]$shortcut.Arguments
    $savedWorkingDirectory = [string]$shortcut.WorkingDirectory

    $proof["target_path"] = $targetPath
    $proof["arguments"] = $arguments
    $proof["working_directory"] = $savedWorkingDirectory
    $proof["description"] = [string]$shortcut.Description
    $proof["window_style"] = [int]$shortcut.WindowStyle
    $proof["target_is_powershell"] = $targetPath.EndsWith("powershell.exe", [System.StringComparison]::OrdinalIgnoreCase)
    $proof["references_run_script"] = ![string]::IsNullOrWhiteSpace($RunScriptPath) -and $arguments.Contains($RunScriptPath)
    $proof["references_config_path"] = ![string]::IsNullOrWhiteSpace($ConfigPath) -and $arguments.Contains($ConfigPath)
    $proof["has_config_path_argument"] = $arguments.Contains("-ConfigPath")
    $proof["runs_listener"] = $arguments.Contains("-Listen")
    $proof["working_directory_is_install_dir"] = $savedWorkingDirectory.Equals($WorkingDirectory, [System.StringComparison]::OrdinalIgnoreCase)

    return $proof
}

function Wait-ProcessMainWindow {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 10
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process exited before creating a main window: pid=$($Process.Id)"
        }
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            Write-Host "process_window=ready pid=$($Process.Id) handle=$($Process.MainWindowHandle)"
            return
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out waiting for process main window: pid=$($Process.Id)"
}

function Set-ProcessForeground {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 5
    )

    $shell = New-Object -ComObject WScript.Shell
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process exited before activation: pid=$($Process.Id)"
        }
        if ($shell.AppActivate($Process.Id)) {
            Write-Host "process_foreground=activated pid=$($Process.Id)"
            return $shell
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out activating process: pid=$($Process.Id)"
}

function New-NotepadPasteProof {
    return [ordered]@{
        requested = $RunNotepadPasteProof.IsPresent
        text = $PasteProofText
        output_present = $false
        target_process_id = 0
        paste_sent = $false
        text_found = $false
        verified = $false
        file = Get-FileProof -Path $NotepadPasteProofPath
    }
}

function Invoke-NotepadPasteProof {
    $proof = New-NotepadPasteProof
    if (!$RunNotepadPasteProof) {
        return $proof
    }

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw "RunNotepadPasteProof requires Windows"
    }
    if ([string]::IsNullOrWhiteSpace($PasteProofText)) {
        throw "PasteProofText must not be empty"
    }

    $notepadParent = Split-Path -Parent $NotepadPasteProofPath
    if (![string]::IsNullOrWhiteSpace($notepadParent)) {
        New-Item -ItemType Directory -Force -Path $notepadParent | Out-Null
    }
    Set-Content -LiteralPath $NotepadPasteProofPath -Encoding UTF8 -NoNewline -Value ""

    $notepad = Start-Process `
        -FilePath "notepad.exe" `
        -ArgumentList @("`"$NotepadPasteProofPath`"") `
        -PassThru

    try {
        Wait-ProcessMainWindow -Process $notepad
        $proof["target_process_id"] = $notepad.Id
        $pasteOutput = & $script:proofAgentPath windows-paste-proof `
            --text $PasteProofText `
            --target-process-id $notepad.Id 2>&1 | Out-String
        $proof["output_present"] = ![string]::IsNullOrWhiteSpace($pasteOutput)
        Write-Host $pasteOutput
        if ($LASTEXITCODE -ne 0) {
            throw "RomaProofAgent windows-paste-proof failed for Notepad"
        }
        Assert-OutputContains -Output $pasteOutput -Expected "target_process_id=$($notepad.Id)"
        Assert-OutputContains -Output $pasteOutput -Expected "paste_sent=true"
        $proof["paste_sent"] = $true

        $shell = Set-ProcessForeground -Process $notepad
        $shell.SendKeys("^s")
        Start-Sleep -Milliseconds 750

        $savedText = Get-Content -LiteralPath $NotepadPasteProofPath -Raw
        $proof["text_found"] = $savedText.Contains($PasteProofText)
        if (!$proof["text_found"]) {
            throw "Notepad file did not contain pasted proof text: $NotepadPasteProofPath"
        }

        $proof["verified"] = $true
        $proof["file"] = Get-FileProof -Path $NotepadPasteProofPath
        Write-Host "notepad_paste_file=$NotepadPasteProofPath"
        Write-Host "notepad_paste_verified=true"
        return $proof
    } finally {
        if ($null -ne $notepad) {
            $notepad.Refresh()
            if (!$notepad.HasExited) {
                $null = $notepad.CloseMainWindow()
                Start-Sleep -Milliseconds 500
                $notepad.Refresh()
            }
            if (!$notepad.HasExited) {
                Stop-Process -Id $notepad.Id -Force
            }
        }
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
    $wrotePath = Get-OutputValue -Content $content -Name "wrote"
    $durationSeconds = Get-OutputNumber -Content $content -Name "duration_seconds"
    $includedPreRollSeconds = Get-OutputNumber -Content $content -Name "included_pre_roll_seconds"
    $rawTranscriptLength = Get-OutputNumber -Content $content -Name "raw_transcript_length"
    $processedTranscriptLength = Get-OutputNumber -Content $content -Name "processed_transcript_length"
    $proof["reported_wrote"] = $content.Contains("wrote=")
    $proof["wrote_path"] = $wrotePath
    if (![string]::IsNullOrWhiteSpace($wrotePath)) {
        $proof["wrote_file"] = Get-FileProof -Path $wrotePath
    }
    $proof["reported_pre_roll"] = $content.Contains("included_pre_roll_seconds=")
    $proof["duration_seconds"] = $durationSeconds
    $proof["included_pre_roll_seconds"] = $includedPreRollSeconds
    $proof["reported_positive_duration"] = ($null -ne $durationSeconds) -and ($durationSeconds -gt 0)
    $proof["reported_positive_pre_roll"] = ($null -ne $includedPreRollSeconds) -and ($includedPreRollSeconds -gt 0)
    $proof["raw_transcript_length"] = $rawTranscriptLength
    $proof["processed_transcript_length"] = $processedTranscriptLength
    $proof["reported_positive_raw_transcript"] = ($null -ne $rawTranscriptLength) -and ($rawTranscriptLength -gt 0)
    $proof["reported_positive_processed_transcript"] = ($null -ne $processedTranscriptLength) -and ($processedTranscriptLength -gt 0)
    $proof["reported_processed_text"] = $content.Contains("processed_transcript_text=")
    $proof["reported_paste_sent"] = $content.Contains("paste_sent=true")
    $proof["reported_paste_not_sent"] = $content.Contains("paste_sent=false")
    $proof["reported_hold_mode"] = $content.Contains("recording_mode=hold")
    $proof["reported_waiting_for_hold_key_down"] = $content.Contains("waiting_for_key_down=")
    $proof["reported_hold_key_down"] = $content.Contains("hold_key_down=true")
    $proof["reported_hold_key_up"] = $content.Contains("hold_key_up=true")

    return $proof
}

function Get-OutputValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match($Content, "(?m)^$escapedName=(.+?)\s*$")
    if (!$match.Success) {
        return ""
    }

    return $match.Groups[1].Value
}

function Get-OutputNumber {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match($Content, "(?m)^$escapedName=([+-]?\d+(?:\.\d+)?)\s*$")
    if (!$match.Success) {
        return $null
    }

    return [double]::Parse(
        $match.Groups[1].Value,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-DoctorOutputProof {
    param(
        [string]$Output = ""
    )

    return [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        runtime_available = $Output.Contains("runtime_available=true")
        os_permission_grants_microphone = $Output.Contains("os_permission_grants=microphone")
        native_capabilities_register_hotkey = $Output.Contains("native_capabilities=RegisterHotKey")
        no_admin_required = $Output.Contains("admin_required=false")
        no_startup_permission_prompt = $Output.Contains("startup_permission_prompt=false")
        no_screen_capture_required = $Output.Contains("screen_capture_required=false")
    }
}

function Get-ProofAgentDoctorOutputProof {
    param(
        [string]$Output = ""
    )

    return [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        swift_core = $Output.Contains("swift_core=true")
        pre_roll_config = $Output.Contains("pre_roll_seconds=")
        windows_paste_adapter_source = $Output.Contains("windows_paste_adapter_source=true")
        windows_permission_surface_source = $Output.Contains("windows_permission_surface_source=true")
        windows_dictation_runtime_source = $Output.Contains("windows_dictation_runtime_source=true")
        windows_dictation_proof_source = $Output.Contains("windows_dictation_proof_source=true")
        miniaudio_capture_adapter_source = $Output.Contains("miniaudio_capture_adapter_source=true")
        openai_compatible_transcription_source = $Output.Contains("openai_compatible_transcription_source=true")
        whisper_cli_transcription_source = $Output.Contains("whisper_cli_transcription_source=true")
        transcription_output_filter_source = $Output.Contains("transcription_output_filter_source=true")
        word_replacement_processor_source = $Output.Contains("word_replacement_processor_source=true")
    }
}

function Get-NativeDoctorOutputProof {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [string]$ExpectedMarker
    )

    return [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        platform_windows = $Output.Contains("platform=windows")
        expected_marker = $ExpectedMarker
        expected_marker_present = $Output.Contains($ExpectedMarker)
    }
}

function Get-ListenerSmokeProof {
    param(
        [string]$Output = ""
    )

    return [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        mode_listen = $Output.Contains("mode=listen")
        zero_session = $Output.Contains("max_sessions=0")
        completed_zero_sessions = $Output.Contains("listen_completed_sessions=0")
    }
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
    $installedRunScriptPath = Join-Path $InstallDir "run-windows-agent.ps1"

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
        doctor = [ordered]@{
            packaged_agent = (Get-DoctorOutputProof -Output $script:packagedAgentDoctorOutput)
            packaged_proof_agent = (Get-ProofAgentDoctorOutputProof -Output $script:packagedProofAgentDoctorOutput)
            packaged_native_doctors = [ordered]@{
                register_hotkey = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["register_hotkey"]) -ExpectedMarker "windows_hotkey_runtime=true")
                keyboard_hook = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["keyboard_hook"]) -ExpectedMarker "runtime=true")
                paste = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["paste"]) -ExpectedMarker "windows_paste_runtime=true")
                dpapi_secret = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["dpapi_secret"]) -ExpectedMarker "dpapi_runtime=true")
                miniaudio_capture = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["miniaudio_capture"]) -ExpectedMarker "native_capture_adapter=true")
            }
            installed_launcher = (Get-DoctorOutputProof -Output $script:installedLauncherDoctorOutput)
        }
        packaged_listener = (Get-ListenerSmokeProof -Output $script:packagedListenerOutput)
        installed_listener = (Get-ListenerSmokeProof -Output $script:installedListenerOutput)
        files = [ordered]@{
            packaged_agent = (Get-FileProof -Path $agentPath)
            packaged_proof_agent = (Get-FileProof -Path $script:proofAgentPath)
            packaged_whisper_cli_mock = (Get-FileProof -Path $script:packagedWhisperCLI)
            installed_agent = (Get-FileProof -Path (Join-Path $InstallDir "RomaWindowsAgent.exe"))
            installed_run_script = (Get-FileProof -Path (Join-Path $InstallDir "run-windows-agent.ps1"))
        }
        manifest = $script:artifactManifest
        package_identity = (Get-PackageIdentityProof)
    }
    if (![string]::IsNullOrWhiteSpace($shortcutPath)) {
        $report["shortcut"] = Get-ShortcutProof `
            -Path $shortcutPath `
            -RunScriptPath $installedRunScriptPath `
            -ConfigPath $ConfigPath `
            -WorkingDirectory $InstallDir
    }
    if (![string]::IsNullOrWhiteSpace($startupShortcutPath)) {
        $report["startup_shortcut"] = Get-ShortcutProof `
            -Path $startupShortcutPath `
            -RunScriptPath $installedRunScriptPath `
            -ConfigPath $ConfigPath `
            -WorkingDirectory $InstallDir
    }
    if ($RunDictation) {
        $report["dictation_runtime"] = Get-DictationRuntimeProof
    }
    if ($RunNotepadPasteProof) {
        $report["notepad_paste"] = $script:notepadPasteProof
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
if ([string]::IsNullOrWhiteSpace($NotepadPasteProofPath)) {
    $NotepadPasteProofPath = Join-Path $InstallDir "smoke\notepad-paste-proof.txt"
}
$NotepadPasteProofPath = Resolve-FullPath -Path $NotepadPasteProofPath

$agentPath = Join-Path $PackageDir "RomaWindowsAgent.exe"
$script:proofAgentPath = Join-Path $PackageDir "RomaProofAgent.exe"
$smokeScript = Join-Path $PackageDir "smoke-windows-agent.ps1"
$installScript = Join-Path $PackageDir "install-windows-agent.ps1"
$runScript = Join-Path $PackageDir "run-windows-agent.ps1"
$proofScript = Join-Path $PackageDir "prove-windows-agent-artifact.ps1"
$laptopProofScript = Join-Path $PackageDir "run-windows-laptop-proof.ps1"
$checkReportScript = Join-Path $PackageDir "check-windows-proof-report.ps1"
$checkSetScript = Join-Path $PackageDir "check-windows-proof-set.ps1"
$manifestPath = Join-Path $PackageDir "manifest.txt"
$script:artifactManifest = @{}
$script:packagedWhisperCLI = ""
$script:packagedAgentDoctorOutput = ""
$script:packagedProofAgentDoctorOutput = ""
$script:packagedListenerOutput = ""
$script:installedListenerOutput = ""
$script:packagedNativeDoctorOutputs = [ordered]@{
    register_hotkey = ""
    keyboard_hook = ""
    paste = ""
    dpapi_secret = ""
    miniaudio_capture = ""
}
$script:installedLauncherDoctorOutput = ""
$script:notepadPasteProof = New-NotepadPasteProof

Invoke-Step "artifact files" {
    Require-File -Path $agentPath
    Require-File -Path $script:proofAgentPath
    Require-File -Path $smokeScript
    Require-File -Path $installScript
    Require-File -Path $runScript
    Require-File -Path $proofScript
    Require-File -Path $laptopProofScript
    Require-File -Path $checkReportScript
    Require-File -Path $checkSetScript
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
        "proof_agent",
        "whisper_cli_mock",
        "smoke_script",
        "run_script",
        "install_script",
        "proof_script",
        "laptop_proof_script",
        "check_report_script",
        "check_set_script",
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
    $script:proofAgentPath = Resolve-PackagePath -Path $script:artifactManifest["proof_agent"]
    Require-File -Path $script:proofAgentPath
    Write-Host "manifest_proof_agent_path=$script:proofAgentPath"
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
    $script:packagedAgentDoctorOutput = & $agentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:packagedAgentDoctorOutput
        throw "RomaWindowsAgent doctor failed"
    }
    Write-Host $script:packagedAgentDoctorOutput
}

Invoke-Step "packaged proof agent doctor" {
    $script:packagedProofAgentDoctorOutput = & $script:proofAgentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:packagedProofAgentDoctorOutput
        throw "RomaProofAgent doctor failed"
    }
    Write-Host $script:packagedProofAgentDoctorOutput
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_paste_adapter_source=true"
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_dictation_proof_source=true"
}

Invoke-Step "packaged listener smoke" {
    $script:packagedListenerOutput = Invoke-PackagedListenerSmoke -ConfigPath (Join-Path $PackageDir "sample-windows-agent.json")
}

Invoke-Step "packaged native proof doctors" {
    $script:packagedNativeDoctorOutputs["register_hotkey"] = Invoke-ProofAgentDoctorCommand -Name "register hotkey" -Command "windows-hotkey-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["register_hotkey"]) -Expected "windows_hotkey_runtime=true"

    $script:packagedNativeDoctorOutputs["keyboard_hook"] = Invoke-ProofAgentDoctorCommand -Name "keyboard hook" -Command "windows-keyboard-hook-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["keyboard_hook"]) -Expected "runtime=true"

    $script:packagedNativeDoctorOutputs["paste"] = Invoke-ProofAgentDoctorCommand -Name "paste" -Command "windows-paste-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["paste"]) -Expected "windows_paste_runtime=true"

    $script:packagedNativeDoctorOutputs["dpapi_secret"] = Invoke-ProofAgentDoctorCommand -Name "dpapi secret" -Command "windows-secret-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["dpapi_secret"]) -Expected "dpapi_runtime=true"

    $script:packagedNativeDoctorOutputs["miniaudio_capture"] = Invoke-ProofAgentDoctorCommand -Name "miniaudio capture" -Command "miniaudio-capture-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["miniaudio_capture"]) -Expected "native_capture_adapter=true"
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
    $script:installedLauncherDoctorOutput = & $installedRun @runArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:installedLauncherDoctorOutput
        throw "Installed launcher doctor failed"
    }
    Write-Host $script:installedLauncherDoctorOutput
}

Invoke-Step "installed listener smoke" {
    $installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
    Require-File -Path $installedRun
    $script:installedListenerOutput = Invoke-InstalledListenerSmoke `
        -RunScriptPath $installedRun `
        -ConfigPath $ConfigPath
}

if ($RunNotepadPasteProof) {
    Invoke-Step "notepad paste proof" {
        $script:notepadPasteProof = Invoke-NotepadPasteProof
    }
}

Write-ProofReport -Mode $proofMode -IsDoctorOnly $false

Write-Host ""
Write-Host "artifact_proof=ok"
Write-Host "package_dir=$PackageDir"
Write-Host "install_dir=$InstallDir"
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    Write-Host "config=$ConfigPath"
}
