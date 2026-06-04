import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after option: String) -> String? {
    guard let index = arguments.firstIndex(of: option),
          arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

guard let outputBasePath = value(after: "-of") else {
    FileHandle.standardError.write(Data("missing -of\n".utf8))
    exit(2)
}

let language = value(after: "-l") ?? "en"
let outputURL = URL(fileURLWithPath: outputBasePath).appendingPathExtension("json")
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let output = [
    "result": [
        "language": language,
        "duration": 1.25 as Double
    ],
    "transcription": [
        ["text": " roma "],
        ["text": "just talk local proof"]
    ]
] as [String: Any]
let data = try JSONSerialization.data(
    withJSONObject: output,
    options: [.prettyPrinted, .sortedKeys]
)
try data.write(to: outputURL)

print("mock_whisper_json=\(outputURL.path)")
