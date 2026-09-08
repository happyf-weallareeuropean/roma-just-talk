import AppKit
import AVFoundation
import SwiftUI
import os
import VoiceInkCore

struct OnboardingTutorialView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var transcribedText: String = ""
    @State private var isTextFieldFocused: Bool = false
    @State private var showingShortcutHint: Bool = true
    @FocusState private var isFocused: Bool
    private let presentation = VoiceInkMacOSOnboardingPresentation.tutorial
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "OnboardingTutorial")
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Reusable background
                OnboardingBackgroundView()
                
                HStack(spacing: 0) {
                    // Left side - Tutorial instructions
                    VStack(alignment: .leading, spacing: 24) {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 40) {
                                // Title and description
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(presentation.title)
                                        .font(.system(size: 44, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                            
                                    Text(presentation.subtitle)
                                        .font(.system(size: 24, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineSpacing(4)
                                }
                        
                                // Keyboard shortcut display
                                VStack(alignment: .leading, spacing: 20) {
                                    HStack {
                                        Text(presentation.shortcutTitle)
                                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                
                                
                                    }
                            
                                    ShortcutPreviewView(shortcut: ShortcutStore.shortcut(for: .primaryRecording))
                                        .padding(4)
                                }

                                // Instructions
                                VStack(alignment: .leading, spacing: 24) {
                                    ForEach(Array(presentation.instructionSteps.enumerated()), id: \.offset) { offset, text in
                                        instructionStep(number: offset + 1, text: text)
                                    }
                                }
                        
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Continue button
                        Button(action: {
                            completeOnboarding()
                        }) {
                            Text(presentation.completeButtonTitle)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(Color.accentColor)
                                .cornerRadius(25)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .opacity(transcribedText.isEmpty ? 0.5 : 1)
                        .disabled(transcribedText.isEmpty)

                        SkipButton(text: presentation.skipButtonTitle) {
                            completeOnboarding()
                        }
                    }
                    .padding(60)
                    .frame(width: geometry.size.width * 0.5)
                    
                    // Right side - Interactive area
                    VStack {
                        // Magical text editor area
                        ZStack {
                            // Glowing background
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .overlay(
                                    // Subtle gradient overlay
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.05),
                                            Color.black.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.accentColor.opacity(0.1), radius: 15, x: 0, y: 0)
                            
                            // Text editor with custom styling
                            TextEditor(text: $transcribedText)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .focused($isFocused)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .foregroundColor(.white)
                                .padding(20)
                            
                            // Placeholder text with magical appearance
                            if transcribedText.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: presentation.placeholderIconSystemName)
                                        .font(.system(size: 36))
                                        .foregroundColor(.white.opacity(0.3))
                                    
                                    Text(presentation.placeholderText)
                                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.5))
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .allowsHitTesting(false)
                            }
                            
                            // Subtle animated border
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(isFocused ? 0.4 : 0.1),
                                            Color.accentColor.opacity(isFocused ? 0.2 : 0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                                .animation(.easeInOut(duration: 0.3), value: isFocused)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(60)
                    .frame(width: geometry.size.width * 0.5)
                }
            }
        }
        .onAppear {
            VoiceInkMacOSOnboardingProgressStore.saveStage(.tutorial)
            animateIn()
            isFocused = true
            recordingShortcutManager.updateShortcutStatus()
            logTryItOutState(reason: "appear")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recordingShortcutManager.updateShortcutStatus()
            logTryItOutState(reason: "appActive")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appPermissionsDidChange)) { _ in
            recordingShortcutManager.updateShortcutStatus()
            logTryItOutState(reason: "permissionsChanged")
        }
        .onChange(of: transcribedText) { _, newValue in
            logger.notice("Onboarding try-it-out text changed: characterCount=\(newValue.count, privacy: .public)")
        }
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(spacing: 20) {
            Text("\(number)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            
            Text(text)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(4)
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }

    private func completeOnboarding() {
        VoiceInkMacOSOnboardingProgressStore.reset()
        hasCompletedOnboarding = true
    }

    private func logTryItOutState(reason: String) {
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let shortcut = ShortcutStore.shortcut(for: .primaryRecording)?.displayString ?? "none"
        let modelName = transcriptionModelManager.currentTranscriptionModel?.name ?? "none"
        let recordingState = String(describing: engine.recordingState)

        logger.notice(
            """
            Onboarding try-it-out state: reason=\(reason, privacy: .public), microphone=\(String(describing: microphoneStatus), privacy: .public), inputMonitoring=\(ShortcutMonitor.preflightListenEventAccess(), privacy: .public), accessibility=\(AXIsProcessTrusted(), privacy: .public), shortcutConfigured=\(recordingShortcutManager.isShortcutConfigured, privacy: .public), shortcut=\(shortcut, privacy: .public), model=\(modelName, privacy: .public), recordingState=\(recordingState, privacy: .public), textCount=\(transcribedText.count, privacy: .public)
            """
        )
    }
}
