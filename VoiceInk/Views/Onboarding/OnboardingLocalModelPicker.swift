import SwiftUI
import VoiceInkCore

struct OnboardingLocalModelPicker<ModelCard: View>: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var selection: VoiceInkLocalOnboardingModelSelection
    @State private var didLookUpRegion = false
    @State private var preserveLanguagePreference: Bool
    @State private var hasUserInteracted = false
    @Binding private var displayedModelName: String

    private let lookupCountry: @Sendable () async -> String?
    private let onRegionLookupFinished: (() -> Void)?
    private let bilingualModel: any TranscriptionModel
    private let englishModel: any TranscriptionModel
    private let isShowingAdvancedModels: Bool
    private let modelCard: (any TranscriptionModel, @escaping () -> Void) -> ModelCard

    init(
        bilingualModel: any TranscriptionModel,
        englishModel: any TranscriptionModel,
        isShowingAdvancedModels: Bool,
        displayedModelName: Binding<String>,
        lookupCountry: @escaping @Sendable () async -> String? = { await VoiceInkOnboardingRegionLookup.countryCode() },
        onRegionLookupFinished: (() -> Void)? = nil,
        @ViewBuilder modelCard: @escaping (any TranscriptionModel, @escaping () -> Void) -> ModelCard
    ) {
        self.lookupCountry = lookupCountry
        self.onRegionLookupFinished = onRegionLookupFinished
        self.bilingualModel = bilingualModel
        self.englishModel = englishModel
        self.isShowingAdvancedModels = isShowingAdvancedModels
        _displayedModelName = displayedModelName
        self.modelCard = modelCard
        let existingName = VoiceInkLocalOnboardingModelPreference.persistedModelName()
        _hasUserInteracted = State(initialValue: isShowingAdvancedModels || existingName != nil
            || VoiceInkLocalOnboardingModelPreference.choice() != nil)
        let explicitLanguage = VoiceInkLocalOnboardingModelPreference.persistedLanguage()
        _preserveLanguagePreference = State(initialValue: explicitLanguage != nil || isShowingAdvancedModels)
        let existingChoice: VoiceInkLocalOnboardingModelChoice? = switch existingName {
        case bilingualModel.name: .chineseAndEnglish
        case englishModel.name: .englishOnly
        default: nil
        }
        var initialSelection = VoiceInkLocalOnboardingModelSelection(
            explicitChoice: VoiceInkLocalOnboardingModelPreference.choice(),
            existingModelChoice: existingChoice,
            hasExistingModel: existingName != nil
        )
        if isShowingAdvancedModels {
            initialSelection.preserveCurrentChoice()
        }
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your local model")
                .font(.headline)

            Picker("Languages you speak", selection: Binding(
                get: { selection.choice },
                set: choose
            )) {
                ForEach(VoiceInkLocalOnboardingModelChoice.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .simultaneousGesture(TapGesture().onEnded { confirmSelection() })
            .onKeyPress(keys: [.space, .return]) { _ in
                confirmSelection()
                return .ignored
            }
            .accessibilityIdentifier("onboarding-local-model-languages")

            Text(selection.choice == .chineseAndEnglish
                 ? "Speak Chinese, English, or mix both. Transcription runs on your Mac."
                 : "For people who dictate in English. Transcription runs on your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // The card confirms the selection before beginning a download or using the model.
            modelCard(selectedModel, confirmSelection)
                .id(selectedModel.name)

            Text("Roma’s website, hosted by Vercel, uses your IP address for an approximate country suggestion. No audio is sent in this lookup. Your choice always wins.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            displayedModelName = isShowingAdvancedModels
                ? (transcriptionModelManager.currentTranscriptionModel?.name ?? selectedModel.name)
                : selectedModel.name
        }
        .task {
            defer { onRegionLookupFinished?() }
            guard !didLookUpRegion, selection.acceptsRegionSuggestion else { return }
            didLookUpRegion = true
            let country = await lookupCountry()
            guard !Task.isCancelled, !isShowingAdvancedModels, selection.acceptsRegionSuggestion else { return }
            selection.applyRegionSuggestion(countryCode: country)
            displayedModelName = selectedModel.name
        }
        .onChange(of: isShowingAdvancedModels) { _, isShowing in
            if isShowing {
                selection.preserveCurrentChoice()
                preserveLanguagePreference = true
                hasUserInteracted = true
                if let name = transcriptionModelManager.currentTranscriptionModel?.name { displayedModelName = name }
            }
        }
        .onChange(of: transcriptionModelManager.currentTranscriptionModel?.name) { _, modelName in
            // Metadata refreshes are not user choices; only explicit UI interaction closes the suggestion.
            guard hasUserInteracted, let modelName else { return }
            displayedModelName = modelName
            if modelName == bilingualModel.name {
                selection.choose(.chineseAndEnglish)
                VoiceInkLocalOnboardingModelPreference.save(.chineseAndEnglish)
            } else if modelName == englishModel.name {
                selection.choose(.englishOnly)
                VoiceInkLocalOnboardingModelPreference.save(.englishOnly)
            }
        }
    }

    private var selectedModel: any TranscriptionModel {
        selection.choice == .chineseAndEnglish ? bilingualModel : englishModel
    }

    private func choose(_ choice: VoiceInkLocalOnboardingModelChoice) {
        selection.choose(choice)
        confirmSelection()
    }

    private func confirmSelection() {
        selection.preserveCurrentChoice()
        hasUserInteracted = true
        displayedModelName = selectedModel.name
        VoiceInkLocalOnboardingModelPreference.save(selection.choice)
        applySelectedModel()
    }

    private func applySelectedModel() {
        if selection.choice == .chineseAndEnglish && !preserveLanguagePreference {
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(VoiceInkLanguageCatalog.autoDetectCode)
        }
        transcriptionModelManager.setDefaultTranscriptionModel(selectedModel)
    }
}
