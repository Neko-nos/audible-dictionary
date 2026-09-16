import AppKit
import DictionaryCore
import SwiftUI

@MainActor
final class DictionaryModel: ObservableObject {
  @Published var query = ""
  @Published var source = "All"
  @Published var selection: String?
  @Published var results: [EntrySummary] = []
  @Published var entry: Entry?
  @Published var error: String?
  @Published private(set) var library: Library?
  let audio = AudioPlayer()
  let audioFolder = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(
    "audio")

  init() {
    if let saved = UserDefaults.standard.string(forKey: "libraryFolder") {
      open(URL(fileURLWithPath: saved))
    } else {
      let adjacent = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(
        "Library")
      if FileManager.default.fileExists(
        atPath: adjacent.appendingPathComponent("dictionary.sqlite").path)
      {
        open(adjacent)
      }
    }
  }

  func chooseLibrary() {
    let panel = NSOpenPanel()
    panel.title = "Choose your dictionary Library folder"
    panel.message = "Select the folder containing dictionary.sqlite."
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    if panel.runModal() == .OK, let url = panel.url { open(url) }
  }

  func refreshAudio() {
    objectWillChange.send()
  }

  func open(_ url: URL) {
    do {
      let opened = try Library(folder: url)
      audio.stop()
      library = opened
      entry = nil
      selection = nil
      results = []
      error = nil
      UserDefaults.standard.set(url.path, forKey: "libraryFolder")
      Task { await search() }
    } catch { self.error = "Could not open this library: \(error.localizedDescription)" }
  }

  func search() async {
    guard let library else { return }
    let currentQuery = query
    let currentSource = source
    do {
      let matches = try await library.search(currentQuery, source: currentSource)
      if Task.isCancelled || currentQuery != query || currentSource != source { return }
      results = matches
      if !matches.contains(where: { $0.id == selection }) { selection = matches.first?.id }
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  func select() async {
    audio.stop()
    entry = nil
    guard let selection, let library else { return }
    do {
      let loaded = try await library.entry(selection)
      if Task.isCancelled || selection != self.selection { return }
      entry = loaded
    } catch { self.error = error.localizedDescription }
  }

  func follow(_ address: String) {
    guard let entry else { return }
    let parts = address.components(separatedBy: ":")
    if parts.count >= 3 && parts[0] == "x-dictionary" && parts[1] == "r" {
      let sourceID = parts[2].components(separatedBy: "#")[0]
      Task {
        do {
          if let match = try await library?.reference(sourceID, source: entry.summary.source) {
            if !results.contains(match) { results.insert(match, at: 0) }
            selection = match.id
          } else {
            error = "That cross-reference is not available in the imported English entries."
          }
        } catch { self.error = error.localizedDescription }
      }
    } else if parts.count >= 3 && parts[0] == "x-dictionary" && parts[1] == "d" {
      query = parts[2].removingPercentEncoding ?? parts[2]
    }
  }

  func playExample(_ id: String) {
    guard let entry, let example = entry.examples.first(where: { $0.id == id }) else {
      return
    }
    audio.play(
      id: example.id, source: entry.summary.source, folder: audioFolder, text: example.text)
  }
}
