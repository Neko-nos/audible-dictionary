import AppKit
import DictionaryCore
import SwiftUI

@MainActor
final class DictionaryModel: ObservableObject {
  @Published var query = ""
  @Published var source = "All"
  @Published private(set) var dictionaryOrder = ["All", "WISDOM", "WISDOM_JE", "ODE"]
  @Published var selection: EntrySummary.ID?
  @Published var results: [EntrySummary] = []
  @Published private(set) var isSpellingSuggestion = false
  @Published var entry: Entry?
  @Published var error: String?
  @Published private(set) var library: Library?
  @Published var textSize = 16.0
  @Published private var history: [Visit] = []
  @Published private var historyIndex = -1
  let audio = AudioPlayer()
  let audioFolder = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(
    "audio")

  private struct Visit: Equatable {
    let query: String
    let source: String
    let selection: EntrySummary.ID
  }

  var canGoBack: Bool { historyIndex > 0 }
  var canGoForward: Bool { historyIndex + 1 < history.count }

  func navigate(_ offset: Int) {
    let index = historyIndex + offset
    guard history.indices.contains(index) else { return }
    historyIndex = index
    let visit = history[index]
    query = visit.query
    source = visit.source
    selection = visit.selection
  }

  init() {
    if let saved = UserDefaults.standard.stringArray(forKey: "dictionaryOrder") {
      dictionaryOrder.sort {
        (saved.firstIndex(of: $0) ?? saved.count) < (saved.firstIndex(of: $1) ?? saved.count)
      }
    }
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

  func moveDictionary(_ source: String, to target: String) -> Bool {
    guard let from = dictionaryOrder.firstIndex(of: source),
      let to = dictionaryOrder.firstIndex(of: target), from != to
    else { return false }
    dictionaryOrder.move(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
    UserDefaults.standard.set(dictionaryOrder, forKey: "dictionaryOrder")
    return true
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
      isSpellingSuggestion = false
      history = []
      historyIndex = -1
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
      let term = Library.normalized(currentQuery)
      isSpellingSuggestion =
        !matches.isEmpty && !matches.contains { $0.matchedTerm.hasPrefix(term) }
      if !matches.contains(where: { $0.id == selection }) { selection = matches.first?.id }
      if entry?.summary.entryID == selection?.entryID { recordVisit() }
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  func select() async {
    audio.stop()
    entry = nil
    guard let selection, let library else { return }
    do {
      let loaded = try await library.entry(selection.entryID)
      if Task.isCancelled || selection != self.selection { return }
      entry = loaded
      if loaded != nil { recordVisit() }
    } catch { self.error = error.localizedDescription }
  }

  private func recordVisit() {
    guard let selection else { return }
    let visit = Visit(query: query, source: source, selection: selection)
    if !history.indices.contains(historyIndex) || history[historyIndex] != visit {
      history = Array(history.prefix(historyIndex + 1)) + [visit]
      historyIndex = history.count - 1
    }
  }

  func follow(_ address: String) {
    guard let entry else { return }
    let parts = address.components(separatedBy: ":")
    if parts.count >= 3 && parts[0] == "x-dictionary" && parts[1] == "r" {
      let sourceID = parts[2].components(separatedBy: "#")[0]
      Task {
        do {
          if let match = try await library?.reference(sourceID, source: entry.summary.source) {
            // Keep the linked entry selectable while the new query refreshes.
            if !results.contains(where: { $0.id == match.id }) { results.insert(match, at: 0) }
            query = match.headword
            source = match.source
            selection = match.id
          } else {
            error = "That cross-reference is not available in the imported entries."
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

  func playHeadword(_ accent: Accent) {
    guard let entry, let audioID = entry.summary.audioID else { return }
    audio.play(
      id: audioID, source: entry.summary.source, accent: accent,
      folder: audioFolder, text: entry.summary.headword)
  }
}
