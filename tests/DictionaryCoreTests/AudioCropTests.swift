import AVFoundation
import DictionaryCore
import Foundation
import Testing

struct AudioCropTests {
  @Test(arguments: [kAudioFormatLinearPCM, kAudioFormatOpus], [1, 2])
  func cropPreservesDecodedSamples(codec: AudioFormatID, channels: Int) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let original = folder.appendingPathComponent("dummy.caf")
    let format = try #require(
      AVAudioFormat(standardFormatWithSampleRate: 24000, channels: UInt32(channels)))
    let audio = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
    audio.frameLength = audio.frameCapacity
    for channel in 0..<channels {
      for frame in 0..<Int(audio.frameLength) {
        audio.floatChannelData![channel][frame] =
          Float(sin(Double(frame) * Double(channel + 1) * 0.04)) * 0.3
      }
    }
    do {
      let settings: [String: Any] =
        codec == kAudioFormatLinearPCM
        ? format.settings
        : [
          AVFormatIDKey: codec, AVSampleRateKey: 24000, AVNumberOfChannelsKey: channels,
          AVEncoderBitRateKey: 32000,
        ]
      let file = try AVAudioFile(forWriting: original, settings: settings)
      try file.write(from: audio)
    }
    let originalData = try Data(contentsOf: original)
    let crop = try AudioCrop(contentsOf: original)
    let decoded = crop.buffer(from: 0, to: crop.duration)
    let output = folder.appendingPathComponent("edited/dummy.caf")
    try crop.save(from: 0.25, to: 1.75, at: output)
    let saved = try AudioCrop(contentsOf: output)
    #expect(saved.duration == 1.5)
    #expect(saved.sampleRate == 24000)
    #expect(saved.peaks.count == 600)
    let buffer = saved.buffer(from: 0, to: saved.duration)
    try #require(buffer.frameLength == 36000)
    #expect(buffer.format.channelCount == channels)
    for channel in 0..<channels {
      let expected = Array(
        UnsafeBufferPointer(start: decoded.floatChannelData![channel] + 6000, count: 36000))
      let actual = Array(
        UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: 36000))
      #expect(actual == expected)
    }
    // A second save exercises replacement of an existing edit.
    try saved.save(from: 0.5, to: 1, at: output)
    #expect(try AudioCrop(contentsOf: output).duration == 0.5)
    #expect(try Data(contentsOf: original) == originalData)
  }

  @Test(arguments: [nil, Accent.us, Accent.uk], [false, true])
  func editedAudioTakesPrecedence(accent: Accent?, fallback: Bool) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var directory = (fallback ? folder.appendingPathComponent("fallback") : folder)
      .appendingPathComponent("ODE")
    if let accent { directory.appendPathComponent(accent.rawValue) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let original = directory.appendingPathComponent("dummy.caf")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000))
    buffer.frameLength = buffer.frameCapacity
    buffer.floatChannelData![0].update(repeating: 0.25, count: 24000)
    do {
      let file = try AVAudioFile(forWriting: original, settings: format.settings)
      try file.write(from: buffer)
    }
    let output = AudioFiles.edited(id: "dummy", source: "ODE", accent: accent, folder: folder)
    let crop = try AudioCrop(contentsOf: original)
    try crop.save(from: 0.1, to: 0.9, at: output)
    #expect(AudioFiles.local(id: "dummy", source: "ODE", accent: accent, folder: folder) == output)
    #expect(try AudioCrop(contentsOf: output).duration == 0.8)
    #expect(try AudioCrop(contentsOf: original).duration == 1)
  }
}
