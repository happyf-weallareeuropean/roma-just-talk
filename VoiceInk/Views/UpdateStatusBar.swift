import SwiftUI
import VoiceInkCore

struct UpdateStatusBar: View {
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel

    var body: some View {
        if updaterViewModel.status.isVisible {
            HStack(spacing: 10) {
                statusIndicator

                VStack(alignment: .leading, spacing: 1) {
                    Text(updaterViewModel.status.title)
                        .font(.callout.weight(.medium))

                    if let detail = updaterViewModel.status.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let releaseNotesURL = updaterViewModel.releaseNotesURL {
                    Link(VoiceInkUpdatePresentation.releaseNotesTitle, destination: releaseNotesURL)
                        .buttonStyle(.link)
                }

                if updaterViewModel.status.canCancel {
                    Button(VoiceInkUpdatePresentation.cancelTitle) {
                        updaterViewModel.cancelUpdate()
                    }
                    .accessibilityIdentifier("update-cancel")
                }

                if updaterViewModel.status.canRelaunch {
                    Button(VoiceInkUpdatePresentation.relaunchTitle) {
                        updaterViewModel.relaunchToUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("update-relaunch")
                } else if updaterViewModel.status.phase == .upToDate || updaterViewModel.status.phase == .failed {
                    Button {
                        updaterViewModel.dismissStatus()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(VoiceInkUpdatePresentation.dismissAccessibilityLabel)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("update-status")
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch updaterViewModel.status.phase {
        case .checking, .preparing, .installing:
            ProgressView()
                .controlSize(.small)
        case .downloading:
            if let progress = updaterViewModel.status.progress {
                ProgressView(value: progress)
                    .frame(width: 46)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        case .ready:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }
}
