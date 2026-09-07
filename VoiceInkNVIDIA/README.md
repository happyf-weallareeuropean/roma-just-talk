# NVIDIA cloud backup

Optional `parakeet-ctc-0.6b-zh-tw` through NVIDIA's hosted Riva gRPC service. Audio leaves the device only when this cloud model is explicitly selected. Requires the user's NVIDIA API key and macOS 15+ (iOS 18+ for the reusable client). Other Roma models retain their existing OS support. The local onboarding default is independent.

The initial integration transcribes the complete recording with `Recognize`; it does not advertise streaming. API-key verification calls `GetRivaSpeechRecognitionConfig` and sends no audio. Each request has a deadline and closes its transport afterward. Recorded audio is checked as mono 16 kHz PCM16 WAV by VoiceInkCore, then the header is removed before sending raw PCM. The dedicated function always receives `zh-TW`, including mixed English speech.

Hosted contract: https://build.nvidia.com/nvidia/parakeet-ctc-0_6b-zh-tw/api

NVIDIA documents separate gRPC and HTTP invocation routes: https://docs.nvidia.com/nvcf/g-rpc-function-invocation . Generic NIM REST documentation does not establish REST support for this hosted function. Do not substitute an inferred REST URL.

Bundled third-party notices are retained under `Sources/VoiceInkNVIDIA/Resources/ThirdPartyNotices` for distribution.

## Generated protocol

Unmodified source protos from `nvidia-riva/common` commit `268890b7286031a6d4950e34f7ce13ed0d4ce621`; license retained under `Protos/LICENSE`. Generated with SwiftProtobuf 1.38.1 and grpc-swift-protobuf 2.4.1. Regeneration requires protoc plus these two generators on PATH:

```sh
protoc -I Protos --swift_out=Sources/VoiceInkNVIDIA/Generated Protos/riva/proto/riva_asr.proto Protos/riva/proto/riva_audio.proto Protos/riva/proto/riva_common.proto
protoc -I Protos --grpc-swift-2_opt='Server=false,Client=true,Visibility=Internal,Availability=macOS 15.0,Availability=iOS 18.0' --grpc-swift-2_out=Sources/VoiceInkNVIDIA/Generated Protos/riva/proto/riva_asr.proto
```

Run `swift test --package-path VoiceInkNVIDIA`. Network acceptance additionally requires an NVIDIA key; unit/contract tests are not evidence of a successful hosted transcription or regional availability.
