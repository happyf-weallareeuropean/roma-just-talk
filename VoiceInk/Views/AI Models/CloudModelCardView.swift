import SwiftUI
import AppKit
import LLMkit
import VoiceInkCore

// MARK: - Cloud Model Card View
struct CloudModelCardView: View {
    let model: CloudModel
    let isCurrent: Bool
    var setDefaultAction: () -> Void

    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var isExpanded = false
    @State private var apiKeyFormState = VoiceInkProviderAPIKeyFormState()
    @State private var streamingEnabled: Bool

    init(model: CloudModel, isCurrent: Bool, setDefaultAction: @escaping () -> Void) {
        self.model = model
        self.isCurrent = isCurrent
        self.setDefaultAction = setDefaultAction
        _streamingEnabled = State(initialValue: VoiceInkTranscriptionStreamingPreference.isEnabled(forModelName: model.name))
    }
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()

    private var isConfigured: Bool {
        return APIKeyManager.shared.hasAPIKey(forProvider: model.provider.apiKeyProviderName)
    }

    var body: some View {
        let apiKeyCardPresentation = VoiceInkProviderAPIKeyCardPresentation(providerDisplayName: model.provider.apiKeyProviderName)

        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                actionSection(apiKeyCardPresentation: apiKeyCardPresentation)
            }
            .padding(16)
            
            // Expandable configuration section
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                configurationSection(apiKeyCardPresentation: apiKeyCardPresentation)
                    .padding(16)
            }
        }
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
        .onAppear {
            loadSavedAPIKey()
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            if model.supportsStreaming && isConfigured {
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
                        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
                    }
                }
                .help(streamingModePresentation.streamingToggleHelp)
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Provider
            Label(model.provider.apiKeyProviderName, systemImage: "cloud")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // Language
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

            if model.speed > 0 && model.accuracy > 0 {
                // Speed
                HStack(spacing: 3) {
                    Text(VoiceInkModelManagementPresentation.speedLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(.secondaryLabelColor))
                    progressDotsWithNumber(value: model.speed * 10)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                // Accuracy
                HStack(spacing: 3) {
                    Text(VoiceInkModelManagementPresentation.accuracyLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(.secondaryLabelColor))
                    progressDotsWithNumber(value: model.accuracy * 10)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Text("Not benchmarked")
                    .font(.system(size: 11))
                    .foregroundColor(Color(.secondaryLabelColor))
            }
        }
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
    
    private func actionSection(
        apiKeyCardPresentation: VoiceInkProviderAPIKeyCardPresentation
    ) -> some View {
        HStack(spacing: 8) {
            if !transcriptionModelManager.isAvailableOnCurrentOS(model) {
                Text("macOS 15+")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabelColor))
            } else if isCurrent {
                Text(VoiceInkModelManagementPresentation.defaultModelTitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabelColor))
            } else if isConfigured {
                Button(action: setDefaultAction) {
                    Text(VoiceInkModelManagementPresentation.setAsDefaultButtonTitle)
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(apiKeyCardPresentation.configureButtonTitle)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: apiKeyCardPresentation.configureButtonSystemImageName)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.controlAccentColor))
                            .shadow(color: Color(.controlAccentColor).opacity(0.2), radius: 2, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            if isConfigured {
                Menu {
                    Button {
                        clearAPIKey()
                    } label: {
                        Label(
                            apiKeyCardPresentation.removeAPIKeyButtonTitle,
                            systemImage: apiKeyCardPresentation.removeAPIKeyButtonSystemImageName
                        )
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
    
    private func configurationSection(
        apiKeyCardPresentation: VoiceInkProviderAPIKeyCardPresentation
    ) -> some View {
        let controlPresentation = apiKeyFormState.macOSCardControlPresentation(
            storedRuntimeKey: APIKeyManager.shared.getAPIKey(forProvider: model.provider.apiKeyProviderName)
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text(apiKeyCardPresentation.configurationSectionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))
            
            HStack(spacing: 8) {
                SecureField(apiKeyCardPresentation.apiKeyFieldPlaceholder, text: $apiKeyFormState.enteredKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(controlPresentation.isAPIKeyFieldDisabled)
                
                Button(action: verifyAPIKey) {
                    HStack(spacing: 4) {
                        if controlPresentation.isVerifyProgressVisible {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: controlPresentation.verifyButtonSystemImageName)
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(controlPresentation.verifyButtonTitle)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(controlPresentation.isVerifyButtonSuccess ? Color(.systemGreen) : Color(.controlAccentColor))
                    )
                }
                .buttonStyle(.plain)
                .disabled(controlPresentation.isVerifyButtonDisabled)
            }
            
            if let feedback = controlPresentation.inlineFeedback {
                Text(feedback.text)
                    .font(.caption)
                    .foregroundColor(feedback.tone.macOSStatusColor)
            }
        }
    }
    
    private func loadSavedAPIKey() {
        apiKeyFormState = .loaded(
            storedKey: APIKeyManager.shared.getStoredAPIKey(forProvider: model.provider.apiKeyProviderName) ?? "",
            isVerified: APIKeyManager.shared.hasAPIKey(forProvider: model.provider.apiKeyProviderName)
        )
    }
    
    private func verifyAPIKey() {
        let startPlan = apiKeyFormState.verificationStartPlan(
            storedRuntimeKey: APIKeyManager.shared.getAPIKey(forProvider: model.provider.apiKeyProviderName),
            missingCandidatePolicy: .keepCurrentState
        )
        guard let keyToVerify = startPlan.applyRuntimeState(
            setFormState: { apiKeyFormState = $0 },
            verifyCandidate: { $0 }
        ) else { return }

        Task {
            let result = await apiKeyVerifier.verifyStoredAPIKeyDetailed(keyToVerify, for: model.provider)

            await MainActor.run {
                let didSaveKey = apiKeyFormState
                    .verificationCompletionPlan(startPlan: startPlan, result: result)
                    .applyRuntimeState(
                        setFormState: { apiKeyFormState = $0 },
                        applyVerificationPlan: {
                            APIKeyManager.shared.applyProviderVerificationPlan(
                                $0,
                                forProvider: model.provider.apiKeyProviderName
                            )
                        }
                    )

                if didSaveKey {
                    transcriptionModelManager.refreshAllAvailableModels()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded = false
                    }
                }
            }
        }
    }
    
    private func clearAPIKey() {
        APIKeyManager.shared.deleteAPIKey(forProvider: model.provider.apiKeyProviderName)
        apiKeyFormState = VoiceInkProviderAPIKeyFormState()

        if isCurrent {
            transcriptionModelManager.clearCurrentTranscriptionModel()
        }

        transcriptionModelManager.refreshAllAvailableModels()

        withAnimation(.easeInOut(duration: 0.3)) {
            isExpanded = false
        }
    }

}
