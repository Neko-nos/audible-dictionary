import AVFoundation
import DictionaryCore
import Foundation
import Metal
import Testing

struct FallbackSpeechTests {
  @Test(.serialized, arguments: ["WISDOM", "ODE"], [nil, Accent.us, Accent.uk])
  func synthesizeCacheAndCancelHelloOnMetal(source: String, accent: Accent?) async throws {
    _ = try #require(MTLCreateSystemDefaultDevice())
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var directory = folder.appendingPathComponent("fallback/\(source)")
    if let accent { directory.appendPathComponent(accent.rawValue) }
    let output = directory.appendingPathComponent("dummy_hello.caf")
    let text = accent == nil ? "Hello! Welcome to the little lantern shop." : "Hello"
    let searchPath = try #require(ProcessInfo.processInfo.environment["PATH"])
    let uv = try #require(
      searchPath.split(separator: ":").map {
        URL(fileURLWithPath: String($0)).appendingPathComponent("uv")
      }.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    try await FallbackSpeech.generate(
      text: text, source: source, accent: accent, output: output,
      uv: uv, projectDirectory: repository)

    let file = try AVAudioFile(forReading: output)
    #expect(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatOpus)
    #expect(file.fileFormat.sampleRate == 24000)
    #expect(file.length > 0)
    let buffer = try #require(
      AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let samples = try #require(buffer.floatChannelData)[0]
    let peak = (0..<Int(buffer.frameLength)).map { abs(samples[$0]) }.max()!
    #expect(peak > 0.01)
    let player = try AVAudioPlayer(contentsOf: output)
    player.volume = 0
    #expect(player.play())
    #expect(player.isPlaying)
    player.stop()
    #expect(
      AudioFiles.local(id: "dummy_hello", source: source, accent: accent, folder: folder) == output)

    let modified = try output.resourceValues(forKeys: [.contentModificationDateKey])
      .contentModificationDate
    try await FallbackSpeech.generate(
      text: text, source: source, accent: accent, output: output,
      uv: uv, projectDirectory: repository)
    #expect(
      try output.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        == modified)

    let cancelledOutput = directory.appendingPathComponent("dummy_hello_cancelled.caf")
    let generation = Task {
      try await FallbackSpeech.generate(
        text: text, source: source, accent: accent, output: cancelledOutput,
        uv: uv, projectDirectory: repository)
    }
    try await Task.sleep(for: .milliseconds(200))
    generation.cancel()
    await #expect(throws: CancellationError.self) { try await generation.value }
    #expect(!FileManager.default.fileExists(atPath: cancelledOutput.path))
  }
}
