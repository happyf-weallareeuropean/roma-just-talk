import SwiftUI
import SwiftData
import OSLog
import VoiceInkCore

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct ContentView: View {
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "ContentView")
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @AppStorage(VoiceInkUserDefaultsKey.powerModeUIFlag) private var powerModeUIFlag = VoiceInkPreferenceDefault.powerModeUIEnabled
    @State private var selectedView: VoiceInkMacOSMainViewItem? = VoiceInkMacOSMainViewItem.defaultSelection
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    @StateObject private var licenseViewModel = LicenseViewModel()

    private var visibleViewTypes: [VoiceInkMacOSMainViewItem] {
        VoiceInkMacOSMainViewItem.visibleItems(powerModeEnabled: powerModeUIFlag)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedView) {
                Section {
                    HStack(spacing: 10) {
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(VoiceInkAppIdentity.compactDisplayName)
                                .font(.system(size: 14, weight: .semibold))

                            Text(VoiceInkAppIdentity.sidebarSubtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        if case .licensed = licenseViewModel.licenseState {
                            ProBadge()
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 8, trailing: 8))
                    .listRowSeparator(.hidden)
                }

                ForEach(visibleViewTypes) { viewType in
                    Section {
                        NavigationLink(value: viewType) {
                            SidebarItemView(viewType: viewType)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationTitle(VoiceInkAppIdentity.compactDisplayName)
            .navigationSplitViewColumnWidth(210)
        } detail: {
            if let selectedView = selectedView {
                detailView(for: selectedView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selectedView.title)
            } else {
                Text(VoiceInkMacOSMainViewItem.emptySelectionTitle)
                    .foregroundColor(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 950)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            UpdateStatusBar()
        }
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = VoiceInkMacOSNavigationRequest.destination(from: notification) {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                if let viewItem = VoiceInkMacOSMainViewItem.item(forNavigationDestination: destination) {
                    selectedView = viewItem
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailView(for viewType: VoiceInkMacOSMainViewItem) -> some View {
        switch viewType {
        case .metrics:
            MetricsView()
        case .models:
            ModelManagementView()
        case .enhancement:
            EnhancementSettingsView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            InlineHistoryView()
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView()
        case .powerMode:
            PowerModeView()
        case .settings:
            SettingsView()
        case .license:
            LicenseManagementView()
        case .permissions:
            PermissionsView()
        }
    }
}

private struct SidebarItemView: View {
    let viewType: VoiceInkMacOSMainViewItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: viewType.systemImageName)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24, height: 24)

            Text(viewType.title)
                .font(.system(size: 14, weight: .medium))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }
}
