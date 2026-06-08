import SwiftUI

struct OnboardingModelDownloadView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var isDownloading = false
    @State private var isModelSet = false
    @State private var showTutorial = false
    
    private let defaultModel = TranscriptionModelRegistry.models.first { $0.name == "parakeet-tdt-0.6b-v2" } as! FluidAudioModel
    
    var body: some View {
        ZStack {
            if showTutorial {
                OnboardingTutorialView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                GeometryReader { geometry in
                    // Reusable background
                    OnboardingBackgroundView()
                    
                    VStack(spacing: 40) {
                        // Model icon and title
                        VStack(spacing: 30) {
                            // Model icon
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 100, height: 100)
                                
                                if isModelSet {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.accentColor)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Image(systemName: "brain")
                                        .font(.system(size: 40))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .scaleEffect(scale)
                            .opacity(opacity)
                            
                            // Title and description
                            VStack(spacing: 12) {
                                Text("Download AI Model")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("We'll download the optimized model to get you started.")
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .scaleEffect(scale)
                            .opacity(opacity)
                        }
                        
                        // Model card - Centered and compact
                        VStack(alignment: .leading, spacing: 16) {
                            // Model name and details
                            VStack(alignment: .center, spacing: 8) {
                                Text(defaultModel.displayName)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("\(defaultModel.size) • \(defaultModel.language)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            // Performance indicators in a more compact layout
                            HStack(spacing: 20) {
                                performanceIndicator(label: "Speed", value: defaultModel.speed)
                                performanceIndicator(label: "Accuracy", value: defaultModel.accuracy)
                                ramUsageLabel(gb: defaultModel.ramUsage)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            
                            // Download progress
                            if let status = fluidAudioModelManager.downloadStatus(for: defaultModel) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(status.message)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text("\(Int(status.fractionCompleted * 100))%")
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.white.opacity(0.7))
                                    }

                                    ProgressView(value: status.fractionCompleted)
                                        .progressViewStyle(.linear)
                                }
                                .transition(.opacity)
                            }
                        }
                        .padding(24)
                        .frame(width: min(geometry.size.width * 0.6, 400))
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .scaleEffect(scale)
                        .opacity(opacity)
                        
                        // Action buttons
                        VStack(spacing: 16) {
                            Button(action: handleAction) {
                                Text(getButtonTitle())
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 200, height: 50)
                                    .background(Color.accentColor)
                                    .cornerRadius(25)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(isDownloading)
                            
                            if !isModelSet {
                                SkipButton(text: "Skip for now") {
                                    withAnimation {
                                        showTutorial = true
                                    }
                                }
                            }
                        }
                        .opacity(opacity)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(width: min(geometry.size.width * 0.8, 600))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear {
            animateIn()
            checkModelStatus()
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }
    
    private func checkModelStatus() {
        if fluidAudioModelManager.isFluidAudioModelDownloaded(defaultModel) {
            isModelSet = transcriptionModelManager.currentTranscriptionModel?.name == defaultModel.name
        }
    }

    private func handleAction() {
        if isModelSet {
            withAnimation {
                showTutorial = true
            }
        } else if fluidAudioModelManager.isFluidAudioModelDownloaded(defaultModel) {
            Task {
                transcriptionModelManager.setDefaultTranscriptionModel(defaultModel)
                withAnimation {
                    isModelSet = true
                }
            }
        } else {
            withAnimation {
                isDownloading = true
            }
            Task {
                await fluidAudioModelManager.downloadFluidAudioModel(defaultModel)
                let isDownloaded = fluidAudioModelManager.isFluidAudioModelDownloaded(defaultModel)
                if isDownloaded {
                    transcriptionModelManager.setDefaultTranscriptionModel(defaultModel)
                }
                withAnimation {
                    isModelSet = isDownloaded
                    isDownloading = false
                }
            }
        }
    }

    private func getButtonTitle() -> String {
        if isModelSet {
            return "Continue"
        } else if isDownloading {
            return "Downloading..."
        } else if fluidAudioModelManager.isFluidAudioModelDownloaded(defaultModel) {
            return "Set as Default"
        } else {
            return "Download Model"
        }
    }
    
    private func performanceIndicator(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(Double(index) / 5.0 <= value ? Color.accentColor : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
    
    private func ramUsageLabel(gb: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RAM")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            Text(String(format: "%.1f GB", gb))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
