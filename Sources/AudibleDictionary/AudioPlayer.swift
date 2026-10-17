import AVFoundation
import DictionaryCore
import Foundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published var status = "Ready"
  @Published var isPlaying = false
  @Published var isGenerating = false
  private var player: AVAudioPlayer?
  private var generation: Task<Void, Never>?

  func stop() {
    generation?.cancel()
    generation = nil
    isGenerating = false
    player?.stop()
    player = nil
    isPlaying = false
    status = "Stopped"
  }

  func play(id: String, source: String, accent: Accent? = nil, folder: URL, text: String) {
    stop()
    let label = accent?.label ?? "English"
    if let file = AudioFiles.local(id: id, source: source, accent: accent, folder: folder) {
      play(file: file, label: "\(label) audio")
      return
    }
    guard let uv = Bundle.main.object(forInfoDictionaryKey: "FallbackUV") as? String,
      let project = Bundle.main.object(forInfoDictionaryKey: "FallbackProject") as? String
    else {
      status = "Fallback speech is not configured. Rebuild the app with scripts/build.sh."
      return
    }
    var directory = folder.appendingPathComponent("fallback").appendingPathComponent(source)
    if let accent { directory.appendPathComponent(accent.rawValue) }
    let output = directory.appendingPathComponent(id).appendingPathExtension("caf")
    isGenerating = true
    status = "Generating speech… The first use may download the voice model."
    generation = Task {
      do {
        try await FallbackSpeech.generate(
          text: text, source: source, accent: accent, output: output, uv: URL(fileURLWithPath: uv),
          projectDirectory: URL(fileURLWithPath: project))
        try Task.checkCancellation()
        generation = nil
        isGenerating = false
        let file =
          AudioFiles.local(id: id, source: source, accent: accent, folder: folder) ?? output
        play(file: file, label: "\(label) audio")
      } catch {
        guard !Task.isCancelled else { return }
        generation = nil
        isGenerating = false
        status = "Speech could not be generated: \(error.localizedDescription)"
      }
    }
  }

  private func play(file: URL, label: String) {
    do {
      player = try AVAudioPlayer(contentsOf: file)
      player?.delegate = self
      isPlaying = player?.play() == true
      status = isPlaying ? label : "This audio file could not be played."
    } catch {
      status = "Audio could not be played: \(error.localizedDescription)"
    }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    let finished = ObjectIdentifier(player)
    Task { @MainActor in
      if self.player.map(ObjectIdentifier.init) == finished {
        self.isPlaying = false
        self.status = flag ? "Finished" : "Playback failed"
      }
    }
  }
}
