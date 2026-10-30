import AVFoundation
import DictionaryCore
import SwiftUI

struct AudioRecording: Equatable {
  let id: String
  let source: String
  let accent: Accent?
  let text: String
}

@MainActor
final class AudioEditor: ObservableObject {
  @Published private(set) var recording: AudioRecording?
  @Published private(set) var clip: AudioCrop?
  @Published var start = 0.0 { didSet { stop() } }
  @Published var end = 0.0 { didSet { stop() } }
  @Published private(set) var isPlaying = false
  @Published private(set) var canRestore = false
  @Published var error: String?
  private var folder: URL?
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?

  var hasChanges: Bool {
    guard let clip else { return false }
    return start >= 0.5 / clip.sampleRate || end < clip.duration - 0.5 / clip.sampleRate
  }

  var playhead: Double? {
    guard let player, let time = player.lastRenderTime,
      let position = player.playerTime(forNodeTime: time)
    else { return nil }
    return min(end, start + Double(position.sampleTime) / position.sampleRate)
  }

  func load(_ recording: AudioRecording, folder: URL) {
    if self.recording == recording && self.folder == folder && clip != nil { return }
    self.recording = recording
    self.folder = folder
    reload()
  }

  private var editedURL: URL? {
    guard let recording, let folder else { return nil }
    return AudioFiles.edited(
      id: recording.id, source: recording.source, accent: recording.accent, folder: folder)
  }

  private func reload() {
    stop()
    clip = nil
    error = nil
    start = 0
    end = 0
    canRestore = editedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    guard let recording, let folder else { return }
    guard
      let file = AudioFiles.local(
        id: recording.id, source: recording.source, accent: recording.accent, folder: folder)
    else {
      error = "Play this recording in Dictionary mode to generate it first."
      return
    }
    do {
      let loaded = try AudioCrop(contentsOf: file)
      clip = loaded
      end = loaded.duration
    } catch { self.error = error.localizedDescription }
  }

  func reset() {
    start = 0
    end = clip?.duration ?? 0
  }

  func stop() {
    player?.stop()
    engine?.stop()
    player = nil
    engine = nil
    isPlaying = false
  }

  func preview() {
    if isPlaying {
      stop()
      return
    }
    guard let clip else { return }
    error = nil
    let buffer = clip.buffer(from: start, to: end)
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
    do {
      try engine.start()
      self.engine = engine
      self.player = player
      let playback = ObjectIdentifier(player)
      player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        Task { @MainActor in
          if self?.player.map(ObjectIdentifier.init) == playback { self?.stop() }
        }
      }
      player.play()
      isPlaying = true
    } catch { self.error = error.localizedDescription }
  }

  @discardableResult func save() -> Bool {
    guard let clip, let editedURL else { return false }
    stop()
    do {
      try clip.save(from: start, to: end, at: editedURL)
      reload()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  func restore() {
    guard let editedURL else { return }
    stop()
    do {
      try FileManager.default.removeItem(at: editedURL)
      reload()
    } catch { self.error = error.localizedDescription }
  }
}
