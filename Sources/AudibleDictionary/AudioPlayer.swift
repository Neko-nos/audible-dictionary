import AVFoundation
import DictionaryCore
import Foundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published var status = "Ready"
  @Published var isPlaying = false
  private var player: AVAudioPlayer?

  func stop() {
    player?.stop()
    player = nil
    isPlaying = false
    status = "Stopped"
  }

  func play(id: String, source: String, accent: Accent? = nil, folder: URL) {
    stop()
    let label = accent?.label ?? "English"
    guard let file = AudioFiles.local(id: id, source: source, accent: accent, folder: folder) else {
      status = "No imported \(label) audio."
      return
    }
    do {
      player = try AVAudioPlayer(contentsOf: file)
      player?.delegate = self
      isPlaying = player?.play() == true
      status = isPlaying ? "Imported \(label) audio" : "This audio file could not be played."
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
