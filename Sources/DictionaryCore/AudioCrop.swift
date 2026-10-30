import AVFoundation
import Foundation

public struct AudioCrop {
  private let audio: AVAudioPCMBuffer
  public let peaks: [Float]

  public var duration: Double { Double(audio.frameLength) / audio.format.sampleRate }
  public var sampleRate: Double { audio.format.sampleRate }

  public init(contentsOf url: URL) throws {
    let file = try AVAudioFile(forReading: url)
    let audio = AVAudioPCMBuffer(
      pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    // Decoders can return a short read before EOF, even for PCM files.
    let chunk = AVAudioPCMBuffer(
      pcmFormat: file.processingFormat, frameCapacity: min(16384, audio.frameCapacity))!
    while audio.frameLength < audio.frameCapacity {
      try file.read(
        into: chunk, frameCount: min(chunk.frameCapacity, audio.frameCapacity - audio.frameLength))
      if chunk.frameLength == 0 { break }
      for channel in 0..<Int(audio.format.channelCount) {
        (audio.floatChannelData![channel] + Int(audio.frameLength)).update(
          from: chunk.floatChannelData![channel], count: Int(chunk.frameLength))
      }
      audio.frameLength += chunk.frameLength
    }
    self.audio = audio
    let count = Int(audio.frameLength)
    guard count > 0 else {
      throw NSError(
        domain: "AudioCrop", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "This recording is empty."])
    }
    // A fixed number of peaks keeps waveform drawing independent of recording length.
    let bins = min(600, count)
    peaks = (0..<bins).map { bin in
      var peak: Float = 0
      for channel in 0..<Int(audio.format.channelCount) {
        let samples = audio.floatChannelData![channel]
        for frame in (bin * count / bins)..<((bin + 1) * count / bins) {
          peak = max(peak, abs(samples[frame]))
        }
      }
      return peak
    }
  }

  public func buffer(from start: Double, to end: Double) -> AVAudioPCMBuffer {
    let first = max(0, min(Int(audio.frameLength) - 1, Int((start * sampleRate).rounded())))
    let last = max(first + 1, min(Int(audio.frameLength), Int((end * sampleRate).rounded())))
    let buffer = AVAudioPCMBuffer(
      pcmFormat: audio.format, frameCapacity: AVAudioFrameCount(last - first))!
    buffer.frameLength = buffer.frameCapacity
    for channel in 0..<Int(audio.format.channelCount) {
      buffer.floatChannelData![channel].update(
        from: audio.floatChannelData![channel] + first, count: last - first)
    }
    return buffer
  }

  public func save(from start: Double, to end: Double, at url: URL) throws {
    let buffer = buffer(from: start, to: end)
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(
      "caf")
    defer { try? FileManager.default.removeItem(at: temporary) }
    // Close the CAF before publishing it, so playback always sees a complete recording.
    do {
      var settings = buffer.format.settings
      settings[AVLinearPCMIsNonInterleaved] = nil
      let file = try AVAudioFile(forWriting: temporary, settings: settings)
      try file.write(from: buffer)
    }
    if FileManager.default.fileExists(atPath: url.path) {
      _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: url)
    }
  }
}
