import Foundation
import SwiftData

class LastTranscriptionService: ObservableObject {
    
    static func getLastTranscription(from modelContext: ModelContext) -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        
        do {
            let transcriptions = try modelContext.fetch(descriptor)
            return transcriptions.first { transcription in
                isPasteable(transcription)
            }
        } catch {
            print("Error fetching last transcription: \(error)")
            return nil
        }
    }

    private static func isPasteable(_ transcription: Transcription) -> Bool {
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = transcription.transcriptionStatus
        return !text.isEmpty &&
            text != Transcription.canceledTranscriptionText &&
            (status == nil || status == TranscriptionStatus.completed.rawValue)
    }
    
    static func copyLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "No transcription available",
                    type: .error
                )
            }
            return
        }
        
        // Prefer enhanced text; fallback to original text
        let textToCopy: String = {
            if let enhancedText = lastTranscription.enhancedText, !enhancedText.isEmpty {
                return enhancedText
            } else {
                return lastTranscription.text
            }
        }()
        
        let success = ClipboardManager.copyToClipboard(textToCopy)
        
        Task { @MainActor in
            if success {
                NotificationManager.shared.showNotification(
                    title: "Last transcription copied",
                    type: .success
                )
            } else {
                NotificationManager.shared.showNotification(
                    title: "Failed to copy transcription",
                    type: .error
                )
            }
        }
    }

    static func pasteLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "No transcription available",
                    type: .error
                )
            }
            return
        }
        
        let textToPaste = lastTranscription.text

        CursorPaster.pasteAtCursor(textToPaste)
    }
    
    static func pasteLastEnhancement(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "No transcription available",
                    type: .error
                )
            }
            return
        }
        
        // Prefer enhanced text; if unavailable, fallback to original text (which may contain an error message)
        let textToPaste: String = {
            if let enhancedText = lastTranscription.enhancedText, !enhancedText.isEmpty {
                return enhancedText
            } else {
                return lastTranscription.text
            }
        }()

        CursorPaster.pasteAtCursor(textToPaste)
    }
    
    static func retryLastTranscription(from modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager, serviceRegistry: TranscriptionServiceRegistry, enhancementService: AIEnhancementService?) {
        Task { @MainActor in
            guard let lastTranscription = getLastTranscription(from: modelContext),
                  let audioURLString = lastTranscription.audioFileURL,
                  let audioURL = URL(string: audioURLString),
                  FileManager.default.fileExists(atPath: audioURL.path) else {
                NotificationManager.shared.showNotification(
                    title: "Cannot retry: Audio file not found",
                    type: .error
                )
                return
            }

            guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
                NotificationManager.shared.showNotification(
                    title: "No transcription model selected",
                    type: .error
                )
                return
            }

            let transcriptionService = AudioTranscriptionService(
                modelContext: modelContext,
                serviceRegistry: serviceRegistry,
                enhancementService: enhancementService
            )
            do {
                let newTranscription = try await transcriptionService.retranscribeAudio(from: audioURL, using: currentModel)

                let textToCopy = newTranscription.enhancedText?.isEmpty == false ? newTranscription.enhancedText! : newTranscription.text
                ClipboardManager.copyToClipboard(textToCopy)

                NotificationManager.shared.showNotification(
                    title: "Copied to clipboard",
                    type: .success
                )
            } catch {
                NotificationManager.shared.showNotification(
                    title: "Retry failed: \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }
}
