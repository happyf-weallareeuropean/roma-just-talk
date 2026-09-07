import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os
import VoiceInkCore
import VoiceInkQwen

@MainActor
class VoiceInkEngine: NSObject, ObservableObject {
    @Published var recordingState: VoiceInkRecordingState = .idle
    @Published var shouldCancelRecording = false
    var partialTranscript: String = ""
    var currentSession: TranscriptionSession?
    private var activeRecordingStartID: UUID?
    private var activePipelineTranscriptionID: UUID?
    private var canceledPipelineTranscriptionIDs = Set<UUID>()
    private var stopRequestedDuringStart = false
    private var qwenStartupWarmup: Task<Void, Never>?
    private weak var qwenRecordingSession: (any TranscriptionSession)?
    private var qwenRecordingModelName: String?

    let recorder = Recorder()
    var recordedFile: URL? = nil
    let recordingsDirectory: URL

    // Injected managers
    let whisperModelManager: WhisperModelManager
    let transcriptionModelManager: TranscriptionModelManager
    weak var recorderUIManager: RecorderUIManager?

    let modelContext: ModelContext
    internal let serviceRegistry: TranscriptionServiceRegistry
    let enhancementService: AIEnhancementService?
    private let pipeline: TranscriptionPipeline

    let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "VoiceInkEngine")

    init(
        modelContext: ModelContext,
        whisperModelManager: WhisperModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        qwenRuntimeResult: Result<QwenRuntime, Error>,
        enhancementService: AIEnhancementService? = nil
    ) {
        self.modelContext = modelContext
        self.whisperModelManager = whisperModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.enhancementService = enhancementService

        self.recordingsDirectory = VoiceInkMacOSStorageDirectories.recordingsDirectory

        let serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext,
            qwenRuntimeResult: qwenRuntimeResult,
            ownsQwenRuntime: true
        )
        self.serviceRegistry = serviceRegistry
        self.pipeline = TranscriptionPipeline(
            modelContext: modelContext,
            serviceRegistry: serviceRegistry,
            enhancementService: enhancementService
        )

        super.init()

        if let enhancementService {
            PowerModeSessionManager.shared.configure(engine: self, enhancementService: enhancementService)
        }

        setupNotifications()
        createRecordingsDirectoryIfNeeded()
    }

    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("❌ Error creating recordings directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    // MARK: - Toggle Record

    func toggleRecord(powerModeId: UUID? = nil) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.ensureStarted(
            event: "engine.toggle_requested",
            details: "source=non_shortcut state=\(String(describing: recordingState))"
        )
        latencyTrace.event(
            "engine.toggle.enter",
            details: "state=\(String(describing: recordingState))",
            token: traceToken
        )
        logger.notice("toggleRecord called – state=\(String(describing: self.recordingState), privacy: .public)")

        if recordingState == .starting {
            latencyTrace.event("engine.stop.deferred_during_start", token: traceToken)
            logger.notice("toggleRecord: deferring stop until in-flight recording start finishes")
            stopRequestedDuringStart = true
            return
        }

        if recordingState.isActivelyRecording {
            latencyTrace.event("engine.stop_path.enter", token: traceToken)
            await stopRecordingAndRunPipeline(latencyTraceToken: traceToken)
        } else {
            latencyTrace.event("engine.start_path.enter", token: traceToken)
            logger.notice("toggleRecord: entering start-recording branch")
            guard transcriptionModelManager.currentTranscriptionModel != nil else {
                NotificationManager.shared.showNotification(
                    title: VoiceInkRecordingNotificationPresentation.noTranscriptionModelSelected.title,
                    type: .error
                )
                await recorderUIManager?.dismissMiniRecorder()
                latencyTrace.finish(event: "engine.start.no_model", token: traceToken)
                return
            }
            activePipelineTranscriptionID = nil
            shouldCancelRecording = false
            stopRequestedDuringStart = false
            partialTranscript = ""

            let startLifecycleSpan = latencyTrace.begin("engine.start_lifecycle", token: traceToken)
            latencyTrace.event("engine.permission.request", token: traceToken)
            let granted = await requestRecordPermission(latencyTraceToken: traceToken)
            latencyTrace.event(
                "engine.permission.callback",
                details: "granted=\(granted)",
                token: traceToken
            )
            if granted {
                latencyTrace.event("engine.start_authorized.enter", token: traceToken)
                defer {
                    latencyTrace.event("engine.start_authorized.complete", token: traceToken)
                }

                        let startID = UUID()
                        self.activeRecordingStartID = startID
                        var powerModeConfigTask: Task<PowerModeConfig?, Never>?
                        let startupAudioRelay = RecordingStartupAudioRelay(
                            latencyTraceToken: traceToken
                        )
                        latencyTrace.event("engine.audio_relay.created", token: traceToken)

                        do {
                            let permanentURL = VoiceInkStoredAudioFile.recordingFileURL(in: self.recordingsDirectory)
                            self.recordedFile = permanentURL

                            self.currentSession?.cancel()
                            self.currentSession = nil
                            self.recorder.onAudioChunk = { data in
                                startupAudioRelay.handle(data)
                            }
                            self.recordingState = .starting
                            latencyTrace.event("engine.state.starting", token: traceToken)
                            self.logger.notice("toggleRecord: state=starting, starting audio hardware")

                            let startupPlan = VoiceInkMacOSRecordingStartupOrchestrationPolicy.plan(
                                powerModeConfigurationCount: PowerModeManager.shared.configurations.count
                            )
                            latencyTrace.event(
                                "engine.start_orchestration.plan",
                                details: "resolvePowerMode=\(startupPlan.shouldResolvePowerMode) prepareSessionBeforeRecorder=\(startupPlan.shouldPrepareTranscriptionSessionBeforeRecorder)",
                                token: traceToken
                            )

                            if startupPlan.shouldResolvePowerMode {
                                powerModeConfigTask = Task { @MainActor in
                                    guard !Task.isCancelled else { return nil }
                                    let span = latencyTrace.begin("power_mode.resolve", token: traceToken)
                                    let config = await ActiveWindowService.shared.resolveConfiguration(
                                        powerModeId: powerModeId,
                                        latencyTraceToken: traceToken
                                    )
                                    latencyTrace.end(span, details: "matched=\(config != nil)")
                                    guard !Task.isCancelled else {
                                        latencyTrace.event("power_mode.resolve.discarded", details: "reason=cancelled", token: traceToken)
                                        return nil
                                    }
                                    return config
                                }
                            } else {
                                powerModeConfigTask = nil
                                latencyTrace.event("power_mode.resolve.skipped", details: "reason=no_configurations", token: traceToken)
                            }

                            if startupPlan.shouldPrepareTranscriptionSessionBeforeRecorder,
                               let model = self.transcriptionModelManager.currentTranscriptionModel {
                                try await self.prepareRecordingTranscriptionSession(
                                    for: model,
                                    audioRelay: startupAudioRelay,
                                    latencyTraceToken: traceToken
                                )
                            }

                            let recorderStartSpan = latencyTrace.begin("recorder.start", token: traceToken)
                            do {
                                try await self.recorder.startRecording(
                                    toOutputFile: permanentURL,
                                    latencyTraceToken: traceToken
                                )
                                latencyTrace.end(recorderStartSpan, details: "result=success")
                            } catch {
                                latencyTrace.end(
                                    recorderStartSpan,
                                    details: "result=failure error=\(String(describing: type(of: error)))"
                                )
                                throw error
                            }

                            guard self.activeRecordingStartID == startID,
                                  self.recorderUIManager?.isRecorderSessionActive ?? true,
                                  !self.shouldCancelRecording else {
                                let shouldKeepRecordingFile = self.shouldCancelRecording
                                powerModeConfigTask?.cancel()
                                latencyTrace.event("power_mode.resolve.cancelled", details: "reason=start_aborted", token: traceToken)
                                if self.activeRecordingStartID == startID {
                                    await self.recorder.stopRecording(latencyTraceToken: traceToken)
                                    self.currentSession?.cancel()
                                    self.currentSession = nil
                                    self.recorder.onAudioChunk = nil
                                    startupAudioRelay.clear()
                                    if !shouldKeepRecordingFile {
                                        self.recordedFile = nil
                                    }
                                    self.recordingState = .idle
                                    self.activeRecordingStartID = nil
                                    self.stopRequestedDuringStart = false
                                }
                                latencyTrace.finish(
                                    event: "engine.start.aborted",
                                    details: "cancelRequested=\(self.shouldCancelRecording) recorderSessionActive=\(self.recorderUIManager?.isRecorderSessionActive ?? true)",
                                    token: traceToken
                                )
                                return
                            }

                            self.recordingState = .recording
                            latencyTrace.event("engine.state.recording", token: traceToken)
                            self.logger.notice("toggleRecord: recording started successfully, state=recording")

                            if let powerModeConfigTask {
                                let resolvedPowerModeConfig = await powerModeConfigTask.value
                                let powerModeActivationSpan = latencyTrace.begin("power_mode.activate", token: traceToken)
                                await PowerModeManager.shared.activateConfiguration(resolvedPowerModeConfig)
                                latencyTrace.end(powerModeActivationSpan)
                                self.logger.notice("toggleRecord: Power Mode config applied before streaming setup")
                            }

                            if self.recordingState.isActivelyRecording,
                               let model = self.transcriptionModelManager.currentTranscriptionModel {
                                if self.stopRequestedDuringStart,
                                   self.activeRecordingStartID == startID,
                                   model.supportsRecordedFileTranscription {
                                    self.stopRequestedDuringStart = false
                                    if self.currentSession == nil {
                                        if let startupStopSession = await self.prepareStartupStopStreamingSession(
                                            for: model,
                                            audioRelay: startupAudioRelay,
                                            latencyTraceToken: traceToken
                                        ) {
                                            self.currentSession = startupStopSession
                                            self.logger.notice("toggleRecord: stopping startup recording with streaming startup session")
                                        } else {
                                            self.recorder.onAudioChunk = nil
                                            startupAudioRelay.clear()
                                            self.logger.notice("toggleRecord: stopping startup recording before fallback streaming setup")
                                        }
                                    }
                                    await self.stopRecordingAndRunPipeline(latencyTraceToken: traceToken)
                                    return
                                }

                                if self.currentSession == nil {
                                    try await self.prepareRecordingTranscriptionSession(
                                        for: model,
                                        audioRelay: startupAudioRelay,
                                        latencyTraceToken: traceToken
                                    )
                                }
                            }

                            if self.stopRequestedDuringStart,
                               self.activeRecordingStartID == startID,
                               self.recordingState.isActivelyRecording {
                                self.stopRequestedDuringStart = false
                                latencyTrace.event("engine.deferred_stop.apply", token: traceToken)
                                self.logger.notice("toggleRecord: applying deferred stop after recording start")
                                await self.stopRecordingAndRunPipeline(latencyTraceToken: traceToken)
                                return
                            }

                            Task { @MainActor [weak self] in
                                guard let self else { return }

                                if let model = self.transcriptionModelManager.currentTranscriptionModel {
                                    await model.transcriptionRuntimeResourcePlan.applyRecordingStartupRuntimeState(
                                        loadLocalWhisperModel: {
                                            if let localWhisperModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                                                forModelName: model.name,
                                                in: self.whisperModelManager.availableModels
                                            ),
                                               self.whisperModelManager.whisperContext == nil {
                                                do {
                                                    try await self.whisperModelManager.loadModel(localWhisperModel)
                                                } catch {
                                                    self.logger.error("❌ Model loading failed: \(error.localizedDescription, privacy: .public)")
                                                }
                                            }
                                        },
                                        loadLocalFluidAudioModel: {
                                            if let fluidAudioModel = model as? FluidAudioModel {
                                                try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidAudioModel)
                                            }
                                        },
                                        loadLocalQwenModel: {
                                            if self.currentSession is FileTranscriptionSession {
                                                await self.prewarmQwenBatchRecording(model: model)
                                            }
                                            // Streaming's prepared session owns its own model load.
                                        }
                                    )
                                }

                                if let enhancementService = self.enhancementService {
                                    enhancementService.captureClipboardContext()
                                    await enhancementService.captureScreenContext()
                                }
                            }

                        } catch {
                            powerModeConfigTask?.cancel()
                            latencyTrace.event("power_mode.resolve.cancelled", details: "reason=start_failed", token: traceToken)
                            latencyTrace.event(
                                "engine.start.failed",
                                details: "error=\(String(describing: type(of: error)))",
                                token: traceToken
                            )
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription, privacy: .public)")
                            self.recordingState = .idle
                            self.recordedFile = nil
                            self.activeRecordingStartID = nil
                            self.stopRequestedDuringStart = false
                            self.currentSession?.cancel()
                            self.currentSession = nil
                            self.recorder.onAudioChunk = nil
                            startupAudioRelay.clear()
                            NotificationManager.shared.showNotification(
                                title: VoiceInkRecordingNotificationPresentation.failedToStart.title,
                                type: .error
                            )
                            self.logger.notice("toggleRecord: calling dismissMiniRecorder from error handler")
                            await self.recorderUIManager?.dismissMiniRecorder()
                            latencyTrace.finish(
                                event: "engine.start.failure_complete",
                                details: "error=\(String(describing: type(of: error)))",
                                token: traceToken
                            )
                        }
            } else {
                latencyTrace.event("engine.permission.denied", token: traceToken)
                logger.error("❌ Recording permission denied.")
                let presentation = VoiceInkRecordingNotificationPresentation.microphonePermissionRequired
                let openMicrophonePermission: () -> Void = {
                    Task { @MainActor in
                        PermissionGrantCoordinator.openPermissionsAndGrantMicrophone()
                    }
                }
                NotificationManager.shared.showNotification(
                    title: presentation.title,
                    type: .error,
                    duration: presentation.duration,
                    onTap: openMicrophonePermission,
                    actionButton: presentation.actionButtonTitle.map { label in
                        (label: label, action: openMicrophonePermission)
                    }
                )
                await self.recorderUIManager?.dismissMiniRecorder()
                latencyTrace.finish(event: "engine.permission.denied_complete", token: traceToken)
            }
            latencyTrace.end(startLifecycleSpan)
        }
    }

    private func prepareRecordingTranscriptionSession(
        for model: any TranscriptionModel,
        audioRelay: RecordingStartupAudioRelay,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async throws {
        if model.provider == .qwen {
            await transcriptionModelManager.awaitQwenRecordingSelection()
            try Task.checkCancellation()
            guard transcriptionModelManager.currentTranscriptionModel?.name == model.name else { throw CancellationError() }
        }
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let session = serviceRegistry.createSession(
            for: model,
            onPartialTranscript: { [weak self] partial in
                Task { @MainActor in
                    self?.partialTranscript = partial
                }
            }
        )
        trackQwenRecordingSession(session, model: model)
        currentSession = session
        latencyTrace.event(
            "streaming_session.created",
            details: "model=\(model.displayName)",
            token: traceToken
        )

        let sessionPrepareSpan = latencyTrace.begin("streaming_session.prepare", token: traceToken)
        let realCallback: ((Data) -> Void)?
        do {
            realCallback = try await session.prepare(
                model: model,
                latencyTraceToken: traceToken
            )
            latencyTrace.end(
                sessionPrepareSpan,
                details: "result=success hasAudioSink=\(realCallback != nil)"
            )
        } catch {
            latencyTrace.end(
                sessionPrepareSpan,
                details: "result=failure error=\(String(describing: type(of: error)))"
            )
            session.cancel()
            currentSession = nil
            throw error
        }

        if let realCallback {
            let relayInstallSpan = latencyTrace.begin("audio_relay.install_sink", token: traceToken)
            audioRelay.installSink(realCallback)
            latencyTrace.end(relayInstallSpan)
            recorder.onAudioChunk = realCallback
        } else {
            recorder.onAudioChunk = nil
            audioRelay.clear()
        }
    }

    private func prepareStartupStopStreamingSession(
        for model: any TranscriptionModel,
        audioRelay: RecordingStartupAudioRelay,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> TranscriptionSession? {
        if model.provider == .qwen {
            await transcriptionModelManager.awaitQwenRecordingSelection()
            guard !Task.isCancelled, transcriptionModelManager.currentTranscriptionModel?.name == model.name else { return nil }
        }
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        latencyTrace.event(
            "startup_stop_session.create",
            details: "model=\(model.displayName)",
            token: traceToken
        )
        let session = serviceRegistry.createSession(
            for: model,
            onPartialTranscript: { [weak self] partial in
                Task { @MainActor in
                    self?.partialTranscript = partial
                }
            }
        )
        trackQwenRecordingSession(session, model: model)

        let prepareSpan = latencyTrace.begin("startup_stop_session.prepare", token: traceToken)
        do {
            guard let callback = try await session.prepare(
                model: model,
                latencyTraceToken: traceToken
            ) else {
                latencyTrace.end(prepareSpan, details: "result=success hasAudioSink=false")
                session.cancel()
                return nil
            }
            latencyTrace.end(prepareSpan, details: "result=success hasAudioSink=true")

            let relaySpan = latencyTrace.begin("startup_stop_audio_relay.install_sink", token: traceToken)
            audioRelay.installSink(callback)
            latencyTrace.end(relaySpan)
            recorder.onAudioChunk = callback
            return session
        } catch {
            latencyTrace.end(
                prepareSpan,
                details: "result=failure error=\(String(describing: type(of: error)))"
            )
            latencyTrace.event(
                "startup_stop_session.failed",
                details: "error=\(String(describing: type(of: error)))",
                token: traceToken
            )
            session.cancel()
            logger.error("Startup-stop streaming setup failed, falling back to batch: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func stopRecordingAndRunPipeline(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        latencyTrace.event(
            "engine.stop_pipeline.enter",
            details: "hasSession=\(currentSession != nil) hasFile=\(recordedFile != nil)",
            token: traceToken
        )
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        partialTranscript = ""
        recordingState = .transcribing
        latencyTrace.event("engine.state.transcribing", token: traceToken)
        let recorderStopSpan = latencyTrace.begin("recorder.stop", token: traceToken)
        await recorder.stopRecording(latencyTraceToken: traceToken)
        latencyTrace.end(recorderStopSpan)

        if let recordedFile {
            if !shouldCancelRecording {
                let recordCreationSpan = latencyTrace.begin("transcription_record.create", token: traceToken)
                let transcription = makePendingRecordingTranscription(
                    for: recordedFile,
                    duration: 0
                )
                modelContext.insert(transcription)
                latencyTrace.end(recordCreationSpan)

                latencyTrace.event("pipeline.dispatch", token: traceToken)
                await runPipeline(
                    on: transcription,
                    audioURL: recordedFile,
                    latencyTraceToken: traceToken
                )
            } else {
                latencyTrace.event("engine.stop_pipeline.cancelled", token: traceToken)
                await finishActiveRecorderCancellation(latencyTraceToken: traceToken)
            }
        } else {
            latencyTrace.event("engine.stop_pipeline.missing_file", token: traceToken)
            cancelCurrentSession()
            if !shouldCancelRecording {
                logger.error("❌ No recorded file found after stopping recording")
            }
            recordingState = .idle
            await cleanupResources()
            latencyTrace.finish(event: "engine.stop_pipeline.missing_file_complete", token: traceToken)
        }
    }

    private func requestRecordPermission(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> Bool {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let span = latencyTrace.begin("permission.authorization_status", token: traceToken)
        let permissionStatus: VoiceInkRecordingPermissionStatus
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionStatus = .granted
        case .notDetermined:
            permissionStatus = .undetermined
        case .denied, .restricted:
            permissionStatus = .denied
        @unknown default:
            permissionStatus = .denied
        }
        latencyTrace.end(
            span,
            details: "status=\(String(describing: permissionStatus))"
        )

        switch permissionStatus {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Pipeline Dispatch

    private func runPipeline(
        on transcription: Transcription,
        audioURL: URL,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            transcription.markAsFailedTranscription(reason: VoiceInkModelManagementPresentation.noModelSelectedText)
            try? modelContext.save()
            recordingState = .idle
            latencyTrace.finish(event: "pipeline.no_model", token: traceToken)
            return
        }

        let session = currentSession
        let transcriptionID = transcription.id
        activePipelineTranscriptionID = transcriptionID

        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            model: model,
            session: session,
            latencyTraceToken: traceToken,
            onStateChange: { [weak self] state in
                guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                self.recordingState = state
            },
            shouldCancel: { [weak self] in
                guard let self else { return false }
                return self.canceledPipelineTranscriptionIDs.contains(transcriptionID)
                    || (self.activePipelineTranscriptionID == transcriptionID && self.shouldCancelRecording)
            },
            onCancel: { [weak self, session] in
                guard let self else { return }
                self.cancelPipelineSession(transcriptionID: transcriptionID, session: session)
            },
            onDismiss: { [weak self] in
                guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                await self.recorderUIManager?.dismissMiniRecorder()
            }
        )
        let didFinishActivePipeline = activePipelineTranscriptionID == transcriptionID
        if didFinishActivePipeline {
            await finishRecorderSession()
            // Keep successful local STT resources warm for the next recording.
            activePipelineTranscriptionID = nil
            currentSession = nil
            recordedFile = nil
            shouldCancelRecording = false
        }
        canceledPipelineTranscriptionIDs.remove(transcriptionID)

        if didFinishActivePipeline,
           recordingState.shouldReturnToIdleWhenActivePipelineFinishes {
            recordingState = .idle
        }
    }

    // MARK: - Cancellation

    func cancelRecording() async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.currentToken()
        latencyTrace.event(
            "engine.cancel_requested",
            details: "state=\(String(describing: recordingState))",
            token: traceToken
        )
        logger.notice("cancelRecording called – state=\(String(describing: self.recordingState), privacy: .public)")
        let cancellationPlan = VoiceInkMacOSRecordingCancellationPolicy.plan(
            recordingState: recordingState
        )

        await cancellationPlan.applyRuntimeState(
            clearDeferredStopRequest: {
                stopRequestedDuringStart = false
            },
            requestRecordingCancellation: {
                requestRecordingCancellation()
            },
            finishActiveRecorderCancellation: {
                await finishActiveRecorderCancellation(latencyTraceToken: traceToken)
            },
            clearPartialTranscript: {
                partialTranscript = ""
            },
            clearCancelFlag: {
                shouldCancelRecording = false
            },
            setRecordingState: {
                recordingState = $0
            },
            finishRecorderSessionImmediately: {
                await finishRecorderSession()
            }
        )
    }

    func resetRecordingSession() async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.currentToken()
        cancelCurrentSession()
        activeRecordingStartID = nil
        activePipelineTranscriptionID = nil
        canceledPipelineTranscriptionIDs.removeAll()
        shouldCancelRecording = false
        stopRequestedDuringStart = false
        partialTranscript = ""
        await recorder.stopRecording(latencyTraceToken: traceToken)
        recordedFile = nil
        recordingState = .idle
        await cleanupResources()
        await finishRecorderSession()
        latencyTrace.finish(event: "engine.session_reset_complete", token: traceToken)
    }

    private func requestRecordingCancellation() {
        shouldCancelRecording = true

        if recordingState.isPostRecordingProcessing,
           let activePipelineTranscriptionID {
            canceledPipelineTranscriptionIDs.insert(activePipelineTranscriptionID)
        }

        cancelCurrentSession()
    }

    private func finishActiveRecorderCancellation(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        await recorder.stopRecording(latencyTraceToken: traceToken)
        await saveCanceledRecording(latencyTraceToken: traceToken)
        recordedFile = nil
        partialTranscript = ""
        recordingState = .idle
        await cleanupResources()
        latencyTrace.finish(event: "engine.recording_cancelled", token: traceToken)
    }

    private func saveCanceledRecording(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async {
        guard let recordedFile,
              FileManager.default.fileExists(atPath: recordedFile.path)
        else { return }

        let durationResult = await AudioFileMetadata.tracedDuration(
            for: recordedFile,
            executorName: "engine.cancel_audio_duration",
            latencyTraceToken: latencyTraceToken
        )
        VoiceInkLatencyTrace.shared.executorResumed(durationResult.executorCheckpoint)
        let transcription = makeCanceledRecordingTranscription(
            for: recordedFile,
            duration: durationResult.seconds
        )

        modelContext.insert(transcription)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
        } catch {
            logger.error("Failed to save canceled recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makePendingRecordingTranscription(
        for audioURL: URL,
        duration: TimeInterval
    ) -> Transcription {
        let powerModeMetadata = VoiceInkPowerModeTranscriptionMetadata.active(
            from: PowerModeManager.shared.activeConfiguration
        )

        let draft = VoiceInkRecordingTranscriptionDraft.pending(
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionModelName: transcriptionModelManager.currentTranscriptionModel?.displayName,
            powerModeName: powerModeMetadata.name,
            powerModeEmoji: powerModeMetadata.emoji
        )
        return Transcription(recordingDraft: draft)
    }

    private func makeCanceledRecordingTranscription(
        for audioURL: URL,
        duration: TimeInterval
    ) -> Transcription {
        let powerModeMetadata = VoiceInkPowerModeTranscriptionMetadata.active(
            from: PowerModeManager.shared.activeConfiguration
        )

        let draft = VoiceInkRecordingTranscriptionDraft.canceled(
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionModelName: transcriptionModelManager.currentTranscriptionModel?.displayName,
            powerModeName: powerModeMetadata.name,
            powerModeEmoji: powerModeMetadata.emoji
        )
        return Transcription(recordingDraft: draft)
    }

    // MARK: - Resource Cleanup

    private func cancelPipelineSession(transcriptionID: UUID, session: TranscriptionSession?) {
        session?.cancel()

        guard activePipelineTranscriptionID == transcriptionID else {
            logger.notice("Skipping stale pipeline cleanup")
            return
        }

        currentSession = nil
    }

    private func cancelCurrentSession() {
        qwenStartupWarmup?.cancel()
        currentSession?.cancel()
        currentSession = nil
    }

    private func finishRecorderSession() async {
        enhancementService?.clearCapturedContexts()
        await restorePowerModeIfNeeded()
    }

    private func restorePowerModeIfNeeded() async {
        await VoiceInkPowerModeRecordingFinishPlan.finishingRecording(
            shouldPersistConfiguredPreferences: VoiceInkPowerModePreference.shouldPersistConfiguredPreferences()
        ).applyRuntimeState(
            endSession: {
                await PowerModeSessionManager.shared.endSession()
            },
            clearActiveConfiguration: {
                PowerModeManager.shared.setActiveConfiguration(nil)
            }
        )
    }

    func cleanupResources() async {
        logger.notice("cleanupResources: releasing model resources")
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        await whisperModelManager.cleanupResources()
        await serviceRegistry.cleanup()
        logger.notice("cleanupResources: completed")
    }

    // MARK: - Notification Handling

    func trackQwenRecordingSession(_ session: TranscriptionSession, model: any TranscriptionModel) {
        qwenRecordingSession = model.provider == .qwen ? session : nil
        qwenRecordingModelName = model.provider == .qwen ? model.name : nil
    }

    private func prewarmQwenBatchRecording(model: any TranscriptionModel) async {
        qwenStartupWarmup?.cancel()
        let warmup = Task { [weak self] in
            guard let self else { return }
            await transcriptionModelManager.awaitQwenRecordingSelection()
            guard !Task.isCancelled, transcriptionModelManager.currentTranscriptionModel?.name == model.name else { return }
            do { try await serviceRegistry.qwenTranscriptionService.loadModel() }
            catch is CancellationError { }
            catch { logger.error("Qwen model loading failed: \(error.localizedDescription, privacy: .public)") }
        }
        qwenStartupWarmup = warmup
        await warmup.value
    }

    @objc private func qwenModelSelectionChanged() {
        qwenStartupWarmup?.cancel()
        guard let name = qwenRecordingModelName,
              name != transcriptionModelManager.currentTranscriptionModel?.name,
              let session = qwenRecordingSession else { return }
        // Stop the queued connect synchronously, before selection cleanup can see an empty runtime.
        session.cancel()
        qwenRecordingSession = nil
        qwenRecordingModelName = nil
        requestRecordingCancellation()
        Task { [weak self] in
            guard let self, shouldCancelRecording else { return }
            await cancelRecording()
        }
    }

    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(qwenModelSelectionChanged), name: .didChangeModel, object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLicenseStatusChanged),
            name: .licenseStatusChanged,
            object: nil
        )
    }

    @objc func handleLicenseStatusChanged() {
        pipeline.licenseViewModel = LicenseViewModel()
    }

}

enum AudioFileMetadata {
    struct DurationResult: Sendable {
        let seconds: TimeInterval
        let executorCheckpoint: VoiceInkLatencyTrace.ExecutorCheckpoint?
    }

    static func tracedDuration(
        for url: URL,
        executorName: String,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> DurationResult {
        let asset = AVURLAsset(url: url)
        let seconds: TimeInterval
        if let duration = try? await asset.load(.duration) {
            let loadedSeconds = CMTimeGetSeconds(duration)
            seconds = loadedSeconds.isFinite ? loadedSeconds : 0
        } else {
            seconds = 0
        }
        let checkpoint = VoiceInkLatencyTrace.shared.executorEnqueued(
            executorName,
            token: latencyTraceToken
        )
        return DurationResult(
            seconds: seconds,
            executorCheckpoint: checkpoint
        )
    }
}
