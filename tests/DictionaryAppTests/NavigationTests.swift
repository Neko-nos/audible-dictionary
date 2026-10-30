import AVFoundation
import DictionaryCore
import GRDB
import SwiftUI
import Testing
import WebKit

@testable import AudibleDictionary

@Suite(.serialized) @MainActor
struct NavigationTests {
  @Test func editingAudioWhileReading() async throws {
    let (model, window) = try makeDictionary()
    defer {
      model.editor.stop()
      window.close()
    }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    let webView = try await loadedWebView(in: window)
    let entry = try #require(model.entry)
    let example = try #require(entry.examples.first)
    let folder = model.audioFolder.appendingPathComponent(entry.summary.source)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let original = folder.appendingPathComponent(example.id).appendingPathExtension("caf")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
    buffer.frameLength = buffer.frameCapacity
    for frame in 0..<48000 {
      buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 0.04)) * 0.2
    }
    do {
      let file = try AVAudioFile(forWriting: original, settings: format.settings)
      try file.write(from: buffer)
    }
    try await webView.evaluateJavaScript(
      "window.scrollTo(0, 1000); document.querySelector('[data-audio-id]').nextElementSibling.click()"
    )
    try await waitUntil { model.audio.isPlaying }
    model.isEditingAudio = true
    try await waitUntil { model.editor.clip != nil }
    #expect(!model.audio.isPlaying)
    #expect(model.editor.recording?.text == example.text)
    try await waitUntil {
      try await webView.evaluateJavaScript(
        "document.querySelector('[data-audio-id]').nextElementSibling.title") as? String
        == "Crop audio"
    }
    #expect(try await webView.evaluateJavaScript("window.scrollY") as? Double == 1000)
    model.editor.start = 0.25
    model.editor.end = 1.25
    model.isEditingAudio = false
    model.isEditingAudio = true
    #expect(model.editor.start == 0.25)
    #expect(model.editor.end == 1.25)
    model.editor.preview()
    #expect(model.editor.isPlaying)
    try await waitUntil { (model.editor.playhead ?? 0) > model.editor.start }
    try await waitUntil { !model.editor.isPlaying }
    #expect(model.editor.save())
    #expect(model.editor.clip?.duration == 1)
    #expect(!model.editor.hasChanges)
    #expect(model.editor.canRestore)
    let saved = try #require(
      AudioFiles.local(id: example.id, source: entry.summary.source, folder: model.audioFolder))
    #expect(try AVAudioPlayer(contentsOf: saved).duration == 1)
    #expect(try AudioCrop(contentsOf: original).duration == 2)
    model.isEditingAudio = false
    try await webView.evaluateJavaScript(
      "document.querySelector('[data-audio-id]').nextElementSibling.click()")
    try await waitUntil { model.audio.isPlaying }
    try await waitUntil { !model.audio.isPlaying }
    model.isEditingAudio = true
    model.editor.restore()
    #expect(model.editor.clip?.duration == 2)
    #expect(!model.editor.canRestore)
    #expect(
      AudioFiles.local(id: example.id, source: entry.summary.source, folder: model.audioFolder)
        == original)
  }

  @Test func bilingualTextLookup() async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    model.source = "WISDOM"
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    let webView = try await loadedWebView(in: window)
    try await sendMouseEvent("mousemove", to: "#japanese_lookup em", in: webView)
    try await waitUntil {
      try await webView.evaluateJavaScript(
        "document.querySelectorAll('.lookup-underline').length > 0")
        as? Bool == true
    }
    #expect(
      try await webView.evaluateJavaScript(
        "getComputedStyle(document.querySelector('#japanese_lookup em')).cursor") as? String
        == "pointer")
    try await sendMouseEvent("click", to: "#japanese_lookup em", in: webView)
    try await waitUntil { model.entry?.summary.entryID == "dummy_japanese" }
    #expect(model.query == "瑠光草")
    #expect(model.source == "WISDOM_JE")
    model.navigate(-1)
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    #expect(model.source == "WISDOM")
    #expect(model.query == "lumi")
    model.navigate(1)
    try await waitUntil { model.entry?.summary.entryID == "dummy_japanese" }
    #expect(model.source == "WISDOM_JE")
    let japanese = try await loadedWebView(in: window, containing: "#dummy_japanese")
    try await sendMouseEvent("click", to: "#english_lookup em", in: japanese)
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    #expect(model.query == "lumifern")
    #expect(model.source == "WISDOM")
  }

  @Test(arguments: [true, false])
  func plainTextPhraseLookup(hoverFirst: Bool) async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    let webView = try await loadedWebView(in: window)
    if hoverFirst {
      try await sendMouseEvent("mousemove", to: "#inline_lookup em", in: webView)
      try await waitUntil {
        try await webView.evaluateJavaScript(
          "document.querySelectorAll('.lookup-underline').length > 0")
          as? Bool == true
      }
      #expect(
        try await webView.evaluateJavaScript(
          "getComputedStyle(document.querySelector('#inline_lookup em')).cursor")
          as? String == "pointer")
    }
    try await sendMouseEvent("click", to: "#inline_lookup em", in: webView)
    try await waitUntil { model.selection?.matchedTerm == "under the pale lumiroot" }
    #expect(model.query == "under the pale lumiroot")
    let target = try await loadedWebView(in: window, containing: ".lookup-match")
    #expect(
      try await target.evaluateJavaScript("document.querySelector('.lookup-match').id")
        as? String == "dummy_idiom")
    try await waitUntil {
      try await target.evaluateJavaScript("window.scrollY > 1000") as? Bool == true
    }
    model.navigate(-1)
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    #expect(model.query == "lumi")
    model.navigate(1)
    try await waitUntil { model.selection?.matchedTerm == "under the pale lumiroot" }
    let restored = try await loadedWebView(in: window, containing: ".lookup-match")
    try await waitUntil {
      try await restored.evaluateJavaScript("window.scrollY > 1000") as? Bool == true
    }
  }

  @Test func switchingLibrariesLoadsTheNewContent() async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    _ = try await loadedWebView(in: window)
    let original = try #require(model.entry).resources
    let replacement = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.copyItem(at: original, to: replacement)
    let database = try DatabaseQueue(
      path: replacement.appendingPathComponent("dictionary.sqlite").path)
    try await database.write { db in
      try db.execute(
        sql:
          "UPDATE entries SET html = '<div class=\"entry\" id=\"revised_entry\">Revised invented plant</div>' WHERE id = 'dummy_plant'"
      )
      try db.execute(
        sql: "UPDATE dictionaries SET resource_path = ?", arguments: [replacement.path])
    }
    model.open(replacement)
    try await waitUntil { model.entry?.html.contains("revised_entry") == true }
    let webView = try await loadedWebView(in: window, containing: "#revised_entry")
    #expect(
      try await webView.evaluateJavaScript("document.getElementById('revised_entry').textContent")
        as? String == "Revised invented plant")
    #expect(!model.canGoBack)
  }

  @Test(arguments: ["", "zzzzzzzzdummy"])
  func historyFromEmptyResults(_ query: String) async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    model.query = "lumiroot"
    try await waitUntil { model.entry?.summary.entryID == "dummy_origin" }
    model.query = query
    try await waitUntil { model.results.isEmpty && model.entry == nil }
    #expect(model.canGoBack)
    model.navigate(-1)
    try await waitUntil { model.entry?.summary.entryID == "dummy_origin" }
    #expect(model.query == "lumiroot")
    #expect(model.canGoForward)
    model.navigate(1)
    try await waitUntil { model.results.isEmpty && model.entry == nil }
    #expect(model.query == query)
  }

  @Test(arguments: [false, true])
  func resizingPreservesKeyboardFocus(searchFocused: Bool) async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    let webView = try await loadedWebView(in: window)
    let frame = try #require(window.contentView?.superview)
    let search = try #require(findSearchField(frame))
    let width = webView.frame.width
    try #require(window.makeFirstResponder(searchFocused ? search : webView))
    let responder = window.firstResponder
    if searchFocused {
      let editor = try #require(search.currentEditor())
      editor.selectedRange = NSRange(location: 1, length: 1)
    }
    window.setContentSize(NSSize(width: 820, height: 620))
    try await waitUntil { webView.frame.width < width }
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
    #expect(window.firstResponder === responder)
    if searchFocused {
      #expect(search.currentEditor()?.selectedRange == NSRange(location: 1, length: 1))
    }
  }

  @Test(arguments: [780.0, 1050.0])
  func searchFitsTheInitialWindow(_ width: Double) async throws {
    let (model, window) = try makeDictionary(width: width)
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    _ = try await loadedWebView(in: window)
    let frame = try #require(window.contentView?.superview)
    let search = try #require(findSearchField(frame))
    #expect(!search.isHiddenOrHasHiddenAncestor)
    #expect(search.frame.width >= 120)
    #expect(frame.bounds.contains(search.convert(search.bounds, to: frame)))
  }

  @Test func sectionLinksAndHistory() async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    let webView = try await loadedWebView(in: window)

    try await webView.evaluateJavaScript("document.getElementById('sense_link').click()")
    try await waitUntil { model.anchor == "dummy_sense" }
    try await waitUntil {
      try await webView.evaluateJavaScript("window.scrollY > 1000") as? Bool == true
    }
    #expect(model.query == "lumi")
    #expect(model.source == "All")
    #expect(model.canGoBack)

    model.navigate(-1)
    try await waitUntil {
      try await webView.evaluateJavaScript("window.scrollY === 0") as? Bool == true
    }
    #expect(model.anchor == nil)
    #expect(model.canGoForward)
    model.navigate(1)
    try await waitUntil {
      try await webView.evaluateJavaScript("window.scrollY > 1000") as? Bool == true
    }
    #expect(model.anchor == "dummy_sense")

    try await webView.evaluateJavaScript("document.getElementById('origin_link').click()")
    try await waitUntil { model.entry?.summary.entryID == "dummy_origin" }
    let originView = try await loadedWebView(in: window)
    try await waitUntil {
      try await originView.evaluateJavaScript("window.scrollY > 1000") as? Bool == true
    }
    #expect(model.anchor == "dummy_origin_section")

    model.navigate(-1)
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    let restoredView = try await loadedWebView(in: window)
    try await waitUntil {
      try await restoredView.evaluateJavaScript("window.scrollY > 1000") as? Bool == true
    }
    #expect(model.anchor == "dummy_sense")
    #expect(model.query == "lumi")

    try await restoredView.evaluateJavaScript(
      "window.scrollTo(0, 0); document.getElementById('sense_link').click()")
    try await waitUntil {
      try await restoredView.evaluateJavaScript("window.scrollY > 1000") as? Bool == true
    }
  }

  @Test func matchedTermAndTextSize() async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    model.query = "lumifern sprig"
    try await waitUntil { model.selection?.matchedTerm == "lumifern sprig" }
    let webView = try await loadedWebView(in: window, containing: ".lookup-match")
    #expect(
      try await webView.evaluateJavaScript("document.querySelector('.lookup-match').textContent")
        as? String == "lumifern sprig")
    try await waitUntil {
      try await webView.evaluateJavaScript("window.scrollY > 1000") as? Bool == true
    }
    model.textSize = 20
    try await waitUntil { webView.pageZoom == 1.25 }
    #expect(model.selection?.matchedTerm == "lumifern sprig")
  }

  @Test func refreshingAudioKeepsReadingPosition() async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    let webView = try await loadedWebView(in: window)
    let entry = try #require(model.entry)
    let example = try #require(entry.examples.first)
    let folder = model.audioFolder.appendingPathComponent(entry.summary.source)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try await webView.evaluateJavaScript("window.scrollTo(0, 1000)")
    try Data().write(to: folder.appendingPathComponent(example.id).appendingPathExtension("caf"))
    model.refreshAudio()
    try await waitUntil {
      try await webView.evaluateJavaScript(
        "document.querySelector('[data-audio-id]').nextElementSibling.title === 'Play audio'")
        as? Bool == true
    }
    #expect(try await webView.evaluateJavaScript("window.scrollY") as? Double == 1000)
  }

  @Test func dictionaryIllustrations() async throws {
    let (model, window) = try makeDictionary()
    defer { window.close() }
    try await waitUntil { model.entry?.summary.entryID == "dummy_plant" }
    let webView = try await loadedWebView(in: window)
    try await waitUntil {
      try await webView.evaluateJavaScript("document.getElementById('dummy_image').complete")
        as? Bool == true
    }
    #expect(
      try await webView.evaluateJavaScript("document.getElementById('dummy_image').naturalWidth")
        as? Double == 8)
  }

  private func makeDictionary(width: Double = 880) throws -> (DictionaryModel, NSWindow) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"8\" height=\"8\"><rect width=\"8\" height=\"8\" fill=\"green\"/></svg>"
      .write(to: folder.appendingPathComponent("dummy.svg"), atomically: true, encoding: .utf8)
    let database = try DatabaseQueue(path: folder.appendingPathComponent("dictionary.sqlite").path)
    try database.write { db in
      try db.execute(
        sql: """
          CREATE TABLE dictionaries(source TEXT, css TEXT, resource_path TEXT);
          INSERT INTO dictionaries VALUES('WISDOM','body { font: 20px Georgia; } .space { height: 1400px; }','/tmp');
          INSERT INTO dictionaries SELECT 'WISDOM_JE',css,resource_path FROM dictionaries;
          CREATE TABLE entries(id TEXT, source TEXT, source_id TEXT, headword TEXT, search_key TEXT, audio_id TEXT, html TEXT);
          CREATE TABLE aliases(term TEXT, entry_id TEXT, PRIMARY KEY(term, entry_id));
          CREATE TABLE examples(id TEXT, entry_id TEXT, text TEXT, needs_review INTEGER);
          """)
      try db.execute(sql: "UPDATE dictionaries SET resource_path = ?", arguments: [folder.path])
      let exampleID = "dummy_example"
      let plant = """
        <div class="entry" id="dummy_plant"><h1 class="hw">lumifern</h1><img id="dummy_image" src="dummy.svg">
        <a id="sense_link" href="x-dictionary:r:dummy_plant:dummy.dictionary#xpointer(//*[@id='dummy_sense'])">2</a>
        <a id="origin_link" href="x-dictionary:r:dummy_origin:dummy.dictionary#xpointer(//*[@id='dummy_origin_section']):lumiroot">Origin</a>
        <p id="inline_lookup">Look under the <em>pale</em> lumiroot.</p>
        <p id="japanese_lookup">🌱架空の<em>瑠光</em>草を眺める。</p>
        <div class="space"></div><section id="dummy_sense"><h2>Luminous sense</h2></section>
        <section class="csec"><span data-search-terms='["lumifern sprig"]'>lumifern sprig</span></section>
        <span data-audio-id="\(exampleID)">The lumifern glows softly.</span><div class="space"></div></div>
        """
      let origin = """
        <div class="entry" id="dummy_origin"><h1 class="hw">lumiroot</h1>
        <div class="space"></div><section id="dummy_origin_section"><h2>Invented origin</h2></section>
        <section class="idmsec" id="dummy_idiom"><span class="idm" data-search-terms='["under the lumiroot", "under the pale lumiroot"]'>under the (pale) lumiroot</span><p>Invented idiom</p></section>
        <div class="space"></div></div>
        """
      for (id, word, html) in [
        ("dummy_plant", "lumifern", plant), ("dummy_origin", "lumiroot", origin),
      ] {
        try db.execute(
          sql: "INSERT INTO entries VALUES (?, 'WISDOM', ?, ?, ?, NULL, ?)",
          arguments: [id, id, word, word, html])
        try db.execute(sql: "INSERT INTO aliases VALUES (?, ?)", arguments: [word, id])
      }
      try db.execute(sql: "INSERT INTO aliases VALUES ('lumifern sprig', 'dummy_plant')")
      try db.execute(
        sql:
          "INSERT INTO entries VALUES ('dummy_japanese', 'WISDOM_JE', 'dummy_japanese', 'るみぐさ【瑠光草】', 'るみぐさ【瑠光草】', NULL, ?)",
        arguments: [
          """
          <div class="entry" id="dummy_japanese"><h1 class="hw">るみぐさ【瑠光草】</h1>
          <p id="english_lookup">An invented <em>lumifern</em> glows.</p></div>
          """
        ])
      try db.execute(sql: "INSERT INTO aliases VALUES ('瑠光草', 'dummy_japanese')")
      try db.execute(
        sql:
          "INSERT INTO aliases VALUES ('under the lumiroot', 'dummy_origin'), ('under the pale lumiroot', 'dummy_origin')"
      )
      try db.execute(
        sql: "INSERT INTO examples VALUES (?, 'dummy_plant', 'The lumifern glows softly.', 0)",
        arguments: [exampleID])
    }
    let model = DictionaryModel(audioFolder: folder.appendingPathComponent("audio"))
    model.query = "lumi"
    model.open(folder)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 620), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: DictionaryView(model: model, audio: model.audio))
    window.makeKeyAndOrderFront(nil)
    return (model, window)
  }

  private func sendMouseEvent(_ name: String, to selector: String, in webView: WKWebView)
    async throws
  {
    try await webView.evaluateJavaScript(
      """
      (() => {
        const target = document.querySelector('\(selector)');
        const rect = target.getBoundingClientRect();
        target.dispatchEvent(new MouseEvent('\(name)', {
          bubbles: true, clientX: rect.x + rect.width / 2, clientY: rect.y + rect.height / 2
        }));
      })();
      """)
  }

  private func loadedWebView(in window: NSWindow, containing selector: String = ".entry")
    async throws -> WKWebView
  {
    let encoded = String(data: try JSONEncoder().encode(selector), encoding: .utf8)!
    try await waitUntil {
      guard let webView = findWebView(window.contentView!), !webView.isLoading else { return false }
      return try await webView.evaluateJavaScript(
        "document.readyState === 'complete' && document.querySelector(\(encoded)) !== null")
        as? Bool
        == true
    }
    return try #require(findWebView(window.contentView!))
  }

  private func findWebView(_ view: NSView) -> WKWebView? {
    if let webView = view as? WKWebView { return webView }
    return view.subviews.lazy.compactMap(findWebView).first
  }

  private func findSearchField(_ view: NSView) -> NSSearchField? {
    if let field = view as? NSSearchField { return field }
    return view.subviews.lazy.compactMap(findSearchField).first
  }

  private func waitUntil(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async throws -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while try await !condition() {
      try #require(
        ContinuousClock.now < deadline, "Timed out waiting for the dictionary view",
        sourceLocation: sourceLocation)
      try await Task.sleep(for: .milliseconds(20))
    }
  }
}
