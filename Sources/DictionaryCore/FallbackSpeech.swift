import Foundation

public enum FallbackSpeech {
  public static func generate(
    text: String, source: String, accent: Accent? = nil, output: URL, uv: URL,
    projectDirectory: URL
  )
    async throws
  {
    try Task.checkCancellation()
    if FileManager.default.fileExists(atPath: output.path) { return }

    let process = Process()
    let input = Pipe()
    let errors = Pipe()
    process.executableURL = uv
    process.currentDirectoryURL = projectDirectory
    process.arguments = [
      "run", "audibledict/tts/fallback/kokoro_speech.py", "--source", source, "--output",
      output.path,
    ]
    if let accent { process.arguments! += ["--accent", accent.rawValue] }
    var environment = ProcessInfo.processInfo.environment
    // spaCy needs uv on PATH to install its English model on first use.
    environment["PATH"] = uv.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
    environment["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
    process.environment = environment
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    try process.run()

    do {
      try await withTaskCancellationHandler {
        try await Task.detached {
          defer {
            if process.isRunning { process.terminate() }
          }
          try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
          try input.fileHandleForWriting.close()
          let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
          process.waitUntilExit()
          if process.terminationStatus != 0 {
            let message = String(decoding: diagnostics, as: UTF8.self)
              .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
              domain: "FallbackSpeech", code: Int(process.terminationStatus),
              userInfo: [
                NSLocalizedDescriptionKey: message.isEmpty ? "Speech generation failed." : message
              ])
          }
        }.value
      } onCancel: {
        if process.isRunning { process.terminate() }
      }
    } catch {
      try Task.checkCancellation()
      throw error
    }
    try Task.checkCancellation()
  }
}
