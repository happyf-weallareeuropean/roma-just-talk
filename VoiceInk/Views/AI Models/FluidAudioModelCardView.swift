import SwiftUI
import Combine
import AppKit
import VoiceInkCore

struct FluidAudioModelCardView: View {
    let model: FluidAudioModel
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager
    @State private var streamingEnabled: Bool
    private let confirmSelection: () -> Void

    init(model: FluidAudioModel, fluidAudioModelManager: FluidAudioModelManager, transcriptionModelManager: TranscriptionModelManager, confirmSelection: @escaping () -> Void = {}) {
        self.model = model
        self.confirmSelection = confirmSelection
        _fluidAudioModelManager = ObservedObject(wrappedValue: fluidAudioModelManager)
        _transcriptionModelManager = ObservedObject(wrappedValue: transcriptionModelManager)
        _streamingEnabled = State(initialValue: VoiceInkTranscriptionStreamingPreference.isEnabled(forModelName: model.name))
    }

    var isCurrent: Bool {
        transcriptionModelManager.currentTranscriptionModel?.name == model.name
    }

    var isDownloaded: Bool {
        fluidAudioModelManager.isFluidAudioModelDownloaded(model)
    }

    var isDownloading: Bool {
        fluidAudioModelManager.isFluidAudioModelDownloading(model)
    }

    var downloadIssue: FluidAudioModelDownloadIssue? {
        fluidAudioModelManager.downloadIssue(for: model)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                headerSection
                metadataSection
                descriptionSection
                progressSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionSection
        }
        .padding(16)
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            if model.supportsStreaming && isDownloaded {
                streamingModeBadge
            }

            Spacer()
        }
    }

    private var streamingModeBadge: some View {
        let streamingModePresentation = VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: streamingEnabled,
            isStreamingOnly: model.streamingPreferenceSnapshot.isStreamingOnly
        )

        return HStack(spacing: 8) {
            Toggle(
                streamingModePresentation.streamingToggleTitle,
                isOn: streamingModePresentation.isStreamingToggleForcedOn ? .constant(true) : $streamingEnabled
            )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))
                .disabled(streamingModePresentation.isStreamingToggleDisabled)
                .onChange(of: streamingEnabled) { _, newValue in
                    if !streamingModePresentation.isStreamingToggleForcedOn {
                        VoiceInkTranscriptionStreamingPreference.saveIsEnabled(newValue, forModelName: model.name)
                    }
                }
                .help(streamingModePresentation.streamingToggleHelp)
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label(model.language, systemImage: "globe")
            Label(model.size, systemImage: "internaldrive")
            HStack(spacing: 3) {
                Text(VoiceInkModelManagementPresentation.speedLabel)
                progressDotsWithNumber(value: model.speed * 10)
            }
            .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 3) {
                Text(VoiceInkModelManagementPresentation.accuracyLabel)
                progressDotsWithNumber(value: model.accuracy * 10)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 11))
        .foregroundColor(Color(.secondaryLabelColor))
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = fluidAudioModelManager.downloadStatus(for: model) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(status.message)
                            .lineLimit(1)

                        Spacer()

                        if status.fractionCompleted > 0 {
                            Text(status.percentText)
                                .fontDesign(.monospaced)
                        } else {
                            Text("Active")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.secondaryLabelColor))

                    if status.fractionCompleted > 0 {
                        ProgressView(value: status.fractionCompleted)
                            .progressViewStyle(LinearProgressViewStyle())
                    } else {
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .animation(.smooth, value: status.fractionCompleted)
            }

            if let downloadIssue {
                Label(downloadIssue.message, systemImage: downloadIssue.systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(downloadIssue == .stalled ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if isDownloading {
                if downloadIssue == .stalled {
                    Button {
                        Task {
                            await fluidAudioModelManager.retryFluidAudioModelDownload(model)
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Text(VoiceInkFluidAudioDownloadStatus.compactDownloadingStatusText)
                        .font(.system(size: 12))
                        .foregroundColor(Color(.secondaryLabelColor))
                }

                Button {
                    fluidAudioModelManager.cancelFluidAudioModelDownload(model)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Cancel download")
            } else if downloadIssue != nil {
                Button {
                    Task {
                        await fluidAudioModelManager.retryFluidAudioModelDownload(model)
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if isCurrent && isDownloaded {
                Text(VoiceInkModelManagementPresentation.defaultModelTitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabelColor))
            } else if isDownloaded {
                Button(action: {
                    confirmSelection()
                    Task {
                        transcriptionModelManager.setDefaultTranscriptionModel(model)
                    }
                }) {
                    Text(VoiceInkModelManagementPresentation.setAsDefaultButtonTitle)
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: {
                    confirmSelection()
                    Task {
                        await fluidAudioModelManager.downloadFluidAudioModel(model)
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(
                            VoiceInkModelManagementPresentation.downloadButtonTitle
                        )
                        Image(systemName: "arrow.down.circle")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }

            if isDownloaded && !isDownloading {
                Menu {
                    Button(action: {
                        fluidAudioModelManager.deleteFluidAudioModel(model)
                    }) {
                        Label(VoiceInkModelManagementPresentation.deleteModelButtonTitle, systemImage: "trash")
                    }

                    Button {
                        fluidAudioModelManager.showFluidAudioModelInFinder(model)
                    } label: {
                        Label(VoiceInkModelManagementPresentation.showInFinderButtonTitle, systemImage: "folder")
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }
}
