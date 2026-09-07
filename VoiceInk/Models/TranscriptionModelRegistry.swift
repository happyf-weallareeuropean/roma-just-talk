import Foundation
import VoiceInkCore

enum TranscriptionModelRegistry {

    static var models: [any TranscriptionModel] {
        return predefinedModels + CustomCloudModelManager.shared.customModels
    }

    static var defaultMacOSFluidAudioModel: FluidAudioModel {
        FluidAudioModel(spec: VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModel)
    }
    
    private static let predefinedModels: [any TranscriptionModel] = {
        let platformModels: [any TranscriptionModel] = [
            NativeAppleModel(spec: VoiceInkTranscriptionModelCatalog.nativeAppleModel),
            QwenModel()
        ] + VoiceInkTranscriptionModelCatalog.fluidAudioModels.map(FluidAudioModel.init(spec:))
        let localModels = VoiceInkWhisperModelFiles.downloadableModels.map(WhisperModel.init(spec:))
        let nonCloudModels = platformModels + localModels

        let cloudModels: [any TranscriptionModel] = VoiceInkMacOSTranscriptionModelProvider.allCases.flatMap { modelProvider in
            return modelProvider.cloudModelSpecs.map { spec -> any TranscriptionModel in
                CloudModel(spec: spec, provider: modelProvider)
            }
        }
        return nonCloudModels + cloudModels
    }()
}
