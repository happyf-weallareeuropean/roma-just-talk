import SwiftUI
import VoiceInkCore

struct OnboardingModelDownloadView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var qwenModelManager: QwenModelManager
    @State private var showAdvancedModels: Bool
    @State private var displayedLocalModelName: String
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var showTutorial: Bool

    private let lookupCountry: @Sendable () async -> String?
    private let onRegionLookupFinished: (() -> Void)?
    private let onAdvance: (() -> Void)?
    private let presentation = VoiceInkMacOSOnboardingPresentation.modelDownload

    init(
        hasCompletedOnboarding: Binding<Bool>,
        lookupCountry: @escaping @Sendable () async -> String? = { await VoiceInkOnboardingRegionLookup.countryCode() },
        onRegionLookupFinished: (() -> Void)? = nil,
        onAdvance: (() -> Void)? = nil
    ) {
        self.lookupCountry = lookupCountry
        self.onRegionLookupFinished = onRegionLookupFinished
        self.onAdvance = onAdvance
        self._hasCompletedOnboarding = hasCompletedOnboarding
        let existing = VoiceInkLocalOnboardingModelPreference.persistedModelName()
        _displayedLocalModelName = State(initialValue: existing ?? TranscriptionModelRegistry.defaultMacOSFluidAudioModel.name)
        _showAdvancedModels = State(initialValue: existing != nil
            && existing != QwenModel().name
            && existing != TranscriptionModelRegistry.defaultMacOSFluidAudioModel.name)
        self._showTutorial = State(
            initialValue: VoiceInkMacOSOnboardingProgressStore.stage().resumesTutorial
        )
    }

    private var canContinue: Bool {
        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
            return false
        }
        if transcriptionModelManager.isAvailableOnCurrentOS(QwenModel()),
           !showAdvancedModels, currentModel.name != displayedLocalModelName { return false }
        return transcriptionModelManager.usableModels.contains { $0.name == currentModel.name }
    }

    var body: some View {
        ZStack {
            if showTutorial {
                OnboardingTutorialView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                GeometryReader { geometry in
                    OnboardingBackgroundView()

                    VStack(spacing: 24) {
                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 76, height: 76)

                                Image(systemName: canContinue ? "checkmark.seal.fill" : "brain")
                                    .font(.system(size: canContinue ? 38 : 34))
                                    .foregroundColor(.accentColor)
                                    .transition(.scale.combined(with: .opacity))
                            }

                            VStack(spacing: 12) {
                                Text(presentation.title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text(presentation.subtitle)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 620)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)

                        modelChoices
                            .frame(width: min(max(geometry.size.width * 0.86, 620), 800))
                            .frame(maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)

                        VStack(spacing: 16) {
                            Button {
                                continueWithCurrentModel()
                            } label: {
                                Text(presentation.nextButtonTitle)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 200, height: 50)
                                    .background(Color.accentColor.opacity(canContinue ? 1 : 0.35))
                                    .cornerRadius(25)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(!canContinue)
                            .accessibilityIdentifier("onboarding-model-continue")

                            SkipButton(text: presentation.skipButtonTitle) {
                                advance()
                            }
                            .accessibilityIdentifier("onboarding-model-skip")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear {
            animateIn()
        }
    }

    private var modelChoices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if transcriptionModelManager.isAvailableOnCurrentOS(QwenModel()) {
                    OnboardingLocalModelPicker(
                        bilingualModel: QwenModel(),
                        englishModel: TranscriptionModelRegistry.defaultMacOSFluidAudioModel,
                        isShowingAdvancedModels: showAdvancedModels,
                        displayedModelName: $displayedLocalModelName,
                        lookupCountry: lookupCountry,
                        onRegionLookupFinished: onRegionLookupFinished
                    ) { model, confirm in
                        if model.provider == .qwen {
                            QwenModelCardView(model: model, modelManager: qwenModelManager,
                                              transcriptionModelManager: transcriptionModelManager,
                                              confirmSelection: confirm)
                        } else if let english = model as? FluidAudioModel {
                            FluidAudioModelCardView(model: english, fluidAudioModelManager: fluidAudioModelManager,
                                                    transcriptionModelManager: transcriptionModelManager,
                                                    confirmSelection: confirm)
                        }
                    }
                    DisclosureGroup("Other models and language settings", isExpanded: $showAdvancedModels) {
                        ModelManagementView(contentPadding: 12, minimumHeight: 420)
                    }
                    .accessibilityIdentifier("onboarding-model-advanced")
                } else {
                    ModelManagementView(contentPadding: 12, minimumHeight: 420)
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func continueWithCurrentModel() {
        guard canContinue, let model = transcriptionModelManager.currentTranscriptionModel else { return }
        // Continue confirms the ready model; Skip only defers setup.
        transcriptionModelManager.setDefaultTranscriptionModel(model)
        if model.name == QwenModel().name {
            VoiceInkLocalOnboardingModelPreference.save(.chineseAndEnglish)
        } else if model.name == TranscriptionModelRegistry.defaultMacOSFluidAudioModel.name {
            VoiceInkLocalOnboardingModelPreference.save(.englishOnly)
        }
        advance()
    }

    private func advance() {
        VoiceInkMacOSOnboardingProgressStore.saveStage(.tutorial)
        if let onAdvance { onAdvance() }
        else { withAnimation { showTutorial = true } }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }
}
