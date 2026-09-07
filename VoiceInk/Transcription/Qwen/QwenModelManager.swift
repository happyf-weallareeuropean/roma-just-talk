import Foundation
import Combine
import VoiceInkCore
import VoiceInkQwen

@MainActor
final class QwenModelManager: ObservableObject {
    let runtimeResult: Result<QwenRuntime, Error>
    @Published private(set) var isDownloaded = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isDeleting = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status = ""
    @Published private(set) var errorMessage: String?
    var onModelsChanged: (() -> Void)?
    var onModelDeleted: ((String) -> Void)?
    private var downloadTask: Task<Void, Never>?
    private var downloadID: UUID?
    private var selectionTransition: Task<Void, Never>?
    private var selectionRevision: UInt64 = 0
    private let finishRecordingSelection: @MainActor () async throws -> Void

    convenience init(cacheDirectory: URL) {
        let result: Result<QwenRuntime, Error> = Result {
            guard #available(macOS 15, *), !VoiceInkSystemArchitecture.isIntelMac else {
                throw NSError(domain: "Roma.Qwen", code: 1, userInfo: [NSLocalizedDescriptionKey: "The bilingual model requires Apple silicon and macOS 15 or later."])
            }
            return try QwenRuntime(cacheDirectory: cacheDirectory)
        }
        self.init(runtimeResult: result, finishRecordingSelection: {
            try await result.get().endRecordingSelection()
        })
    }

    init(runtimeResult: Result<QwenRuntime, Error>, finishRecordingSelection: @escaping @MainActor () async throws -> Void) {
        self.runtimeResult = runtimeResult
        self.finishRecordingSelection = finishRecordingSelection
        if case .failure(let error) = runtimeResult { errorMessage = error.localizedDescription }
    }

    func runtime() throws -> QwenRuntime { try runtimeResult.get() }

    func recordingSelectionChanged(isSelected: Bool) {
        selectionRevision &+= 1
        let previous = selectionTransition
        selectionTransition = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if !isSelected {
                do { try await finishRecordingSelection() }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    /// A new recording waits for the preceding selection's actual model drain.
    func awaitRecordingSelection() async {
        var observed: UInt64
        repeat {
            observed = selectionRevision
            await selectionTransition?.value
        } while observed != selectionRevision
    }

    func refresh() async {
        isDownloaded = (try? await runtime().isInstalled()) ?? false
        onModelsChanged?()
    }

    func download() {
        guard !isDownloading, !isDeleting else { return }
        isDownloading = true
        let id = UUID()
        downloadID = id
        errorMessage = nil
        progress = 0
        status = "Downloading model…"
        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer { isDownloading = false; downloadTask = nil; downloadID = nil }
            do {
                let runtime = try runtime()
                try await runtime.install { [weak self] update in
                    Task { @MainActor in
                        guard let self, self.downloadID == id else { return }
                        self.progress = update.fractionCompleted
                        switch update.phase {
                        case .downloading: self.status = "Downloading model…"
                        case .verifying: self.status = "Verifying download…"
                        case .ready: self.status = "Ready for offline use"
                        }
                    }
                }
                try Task.checkCancellation()
                await refresh()
            } catch is CancellationError {
                status = "Download cancelled"
            } catch {
                if Task.isCancelled { status = "Download cancelled" }
                else { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelDownload() async {
        downloadTask?.cancel()
        if let runtime = try? runtime() { await runtime.cancelDownload() }
        await downloadTask?.value
        await refresh()
    }

    func delete() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        errorMessage = nil
        await cancelDownload()
        do {
            try await runtime().delete()
            isDownloaded = false
            onModelDeleted?(VoiceInkTranscriptionModelCatalog.localQwenModelName)
            onModelsChanged?()
        } catch { errorMessage = error.localizedDescription }
    }
}
