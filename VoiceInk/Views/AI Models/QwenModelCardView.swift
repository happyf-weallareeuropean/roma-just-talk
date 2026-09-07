import SwiftUI
import VoiceInkCore

struct QwenModelCardView: View {
    let model: any TranscriptionModel
    @ObservedObject var modelManager: QwenModelManager
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager
    var confirmSelection: () -> Void = {}
    @State private var confirmDeletion = false

    private var isCurrent: Bool { transcriptionModelManager.currentTranscriptionModel?.name == model.name }
    private var isSupported: Bool { transcriptionModelManager.isAvailableOnCurrentOS(model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.displayName).font(.headline)
            Text("Chinese and English, including mixed speech. Chinese text is written in Traditional Chinese.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("About 1 GB download. Uses more memory than the English-only model; allow several GB of free memory while dictating. Audio stays on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if !isSupported {
                Text("Requires Apple silicon and macOS 15 or later.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = modelManager.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if modelManager.isDownloading {
                ProgressView(value: modelManager.progress)
                HStack {
                    Text(modelManager.status).font(.caption)
                    Spacer()
                    Button("Cancel") { Task { await modelManager.cancelDownload() } }
                }
            } else {
                HStack {
                    if modelManager.isDownloaded {
                        if isCurrent {
                            Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                        } else {
                            Button("Use this model") { select() }.buttonStyle(.borderedProminent)
                        }
                        Spacer()
                        Button("Delete", role: .destructive) { confirmDeletion = true }
                    } else {
                        Button(modelManager.errorMessage == nil ? "Download model" : "Retry download") {
                            select()
                            modelManager.download()
                        }.buttonStyle(.borderedProminent)
                    }
                }.disabled(!isSupported || modelManager.isDeleting)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
        .confirmationDialog("Delete the bilingual model?", isPresented: $confirmDeletion) {
            Button("Delete model", role: .destructive) { Task { await modelManager.delete() } }
        } message: { Text("You will need to download it again before using it offline.") }
    }

    private func select() {
        confirmSelection()
        transcriptionModelManager.setDefaultTranscriptionModel(model)
    }
}
