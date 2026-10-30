import AppKit
import DictionaryCore
import SwiftUI

@MainActor
final class DictionaryModel: ObservableObject {
  @Published var query = ""
  @Published var source = "All"
  @Published private(set) var dictionaryOrder = ["All", "WISDOM", "WISDOM_JE", "ODE"]
  @Published var selection: EntrySummary.ID? {
    didSet {
      if selection != oldValue { anchor = nil }
    }
  }
  @Published private(set) var anchor: String?
  @Published var results: [EntrySummary] = []
  @Published private(set) var isSpellingSuggestion = false
  @Published var entry: Entry?
  @Published var error: String?
  @Published private(set) var library: Library?
  @Published var textSize = 16.0
  @Published private var history: [Visit] = []
  @Published private var historyIndex = -1
  let audio = AudioPlayer()
  let editor = AudioEditor()
  @Published var isEditingAudio = false {
    didSet {
      audio.stop()
      editor.stop()
      if isEditingAudio, let selectedAudio {
        edit(selectedAudio)
      }
    }
  }
  @Published var pendingAudio: AudioRecording?
  private var selectedAudio: AudioRecording?
  let audioFolder: URL

  private struct Visit: Equatable {
    let query: String
    let source: String
    let selection: EntrySummary.ID?
    let anchor: String?
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
    anchor = visit.anchor
  }

  init(
    audioFolder: URL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(
      "audio")
  ) {
    self.audioFolder = audioFolder
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
      editor.stop()
      library = opened
      entry = nil
      selection = nil
      anchor = nil
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
      if selection == nil || entry?.summary.entryID == selection?.entryID { recordVisit() }
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  func select() async {
    audio.stop()
    editor.stop()
    guard let selection, let library else {
      entry = nil
      return
    }
    do {
      let loaded = try await library.entry(selection.entryID)
      if Task.isCancelled || selection != self.selection { return }
      entry = loaded
      if loaded != nil { recordVisit() }
    } catch {
      entry = nil
      self.error = error.localizedDescription
    }
  }

  private func recordVisit() {
    // Keep empty searches navigable without adding a blank visit at launch.
    if query.isEmpty && history.isEmpty { return }
    let visit = Visit(query: query, source: source, selection: selection, anchor: anchor)
    if !history.indices.contains(historyIndex) || history[historyIndex] != visit {
      history = Array(history.prefix(historyIndex + 1)) + [visit]
      historyIndex = history.count - 1
    }
  }

  func follow(_ link: DictionaryLink) async {
    guard let entry else { return }
    switch link {
    case .reference(let sourceID, let anchor):
      do {
        if let match = try await library?.reference(sourceID, source: entry.summary.source) {
          if match.entryID == self.entry?.summary.entryID {
            self.anchor = anchor
            recordVisit()
            return
          }
          // Keep the linked entry selectable while the new query refreshes.
          if !results.contains(where: { $0.id == match.id }) { results.insert(match, at: 0) }
          query = match.headword
          source = match.source
          selection = match.id
          self.anchor = anchor
        } else {
          error = "That cross-reference is not available in the imported entries."
        }
      } catch { self.error = error.localizedDescription }
    case .lookup(let word, let source):
      anchor = nil
      self.source = source
      query = word
      // A clicked word is a complete query and needs no typing delay.
      await search()
    }
  }

  func playExample(_ id: String) {
    guard let entry, let example = entry.examples.first(where: { $0.id == id }) else {
      return
    }
    play(
      AudioRecording(
        id: example.id, source: entry.summary.source, accent: nil, text: example.text))
  }

  func playHeadword(_ accent: Accent) {
    guard let entry, let audioID = entry.summary.audioID else { return }
    play(
      AudioRecording(
        id: audioID, source: entry.summary.source, accent: accent,
        text: entry.summary.headword))
  }

  private func play(_ recording: AudioRecording) {
    selectedAudio = recording
    if isEditingAudio {
      edit(recording)
    } else {
      audio.play(
        id: recording.id, source: recording.source, accent: recording.accent,
        folder: audioFolder, text: recording.text)
    }
  }

  private func edit(_ recording: AudioRecording) {
    editor.stop()
    if editor.hasChanges && editor.recording != recording {
      pendingAudio = recording
    } else {
      editor.load(recording, folder: audioFolder)
    }
  }

  func confirmAudioChange(save: Bool) {
    guard let pendingAudio else { return }
    if save && !editor.save() { return }
    editor.load(pendingAudio, folder: audioFolder)
    self.pendingAudio = nil
  }

  func cancelAudioChange() {
    pendingAudio = nil
    selectedAudio = editor.recording
  }
}
