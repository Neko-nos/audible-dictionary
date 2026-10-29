import DictionaryCore
import SwiftUI
import WebKit

struct EntryWebView: NSViewRepresentable {
  let entry: Entry
  let audioFolder: URL
  let textSize: Double
  let selection: EntrySummary.ID?
  let anchor: String?
  let play: (String) -> Void
  let playHeadword: (Accent) -> Void
  let follow: (DictionaryLink) -> Void
  let lookup: (String, Int) async throws -> LookupTerm?

  func makeCoordinator() -> Coordinator {
    Coordinator(play: play, playHeadword: playHeadword, follow: follow, lookup: lookup)
  }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(context.coordinator, name: "play")
    configuration.userContentController.add(context.coordinator, name: "headword")
    configuration.userContentController.add(context.coordinator, name: "follow")
    configuration.userContentController.addScriptMessageHandler(
      context.coordinator, contentWorld: .page, name: "lookup")
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    view.setValue(false, forKey: "drawsBackground")
    return view
  }

  func updateNSView(_ view: WKWebView, context: Context) {
    // Keep the current page intact until the newly selected entry has loaded.
    guard let selection, selection.entryID == entry.summary.entryID else { return }
    let matchedTerm = selection.matchedTerm
    context.coordinator.play = play
    context.coordinator.playHeadword = playHeadword
    context.coordinator.follow = follow
    context.coordinator.lookup = lookup
    // The dictionaries' 12pt body size is 16 CSS pixels at their original scale.
    view.pageZoom = textSize / 16
    let localIDs = entry.examples.filter {
      AudioFiles.local(id: $0.id, source: entry.summary.source, folder: audioFolder)
        != nil
    }.map(\.id)
    let imported = String(data: try! JSONEncoder().encode(localIDs), encoding: .utf8)!
    if context.coordinator.selection == selection {
      if context.coordinator.localIDs != localIDs {
        context.coordinator.localIDs = localIDs
        view.evaluateJavaScript("updateAudioAvailability(\(imported))")
      }
      if context.coordinator.anchor != anchor {
        context.coordinator.anchor = anchor
        context.coordinator.scrollToAnchor(in: view)
      }
      return
    }
    context.coordinator.selection = selection
    context.coordinator.anchor = anchor
    context.coordinator.localIDs = localIDs
    let reviewIDs = String(
      data: try! JSONEncoder().encode(entry.examples.filter(\.needsReview).map(\.id)),
      encoding: .utf8)!
    let match = String(data: try! JSONEncoder().encode(matchedTerm), encoding: .utf8)!
    let headword = String(
      data: try! JSONEncoder().encode(Library.normalized(entry.summary.headword)), encoding: .utf8)!
    let html = """
      <!doctype html><html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src file: data:">
      <style>\(entry.css)
      :root { color-scheme: light dark; }
      body { cursor: default; }
      .lookup-match { background: light-dark(#bed8fc, #294f7c); }
      .lookup-underline { position: fixed; pointer-events: none; border-bottom: 1px solid;
        z-index: 1; }
      .headword-audio { display: inline-flex; gap: 4px; margin-left: 12px; vertical-align: middle; }
      .audio-button { font: 11px -apple-system; cursor: pointer; margin: 0 3px; padding: 3px 5px;
        color: light-dark(#666, #bbb); border: 0; border-radius: 4px;
        background: transparent; vertical-align: 1px; }
      .audio-button:focus-visible { outline: 2px solid Highlight; }
      .audio-button:hover { background: light-dark(#eee, #333); }
      [data-d-pr="US"] { display: none; }
      </style></head><body>\(entry.html)
      <script>
      const review = new Set(\(reviewIDs));
      const match = \(match);
      if (match && match !== \(headword)) {
        const word = Array.from(document.querySelectorAll('[data-search-terms]'))
          .find(node => JSON.parse(node.dataset.searchTerms).includes(match));
        if (word) {
          const section = word.closest('.drvsec, .csec, .idmsec') || word;
          section.classList.add('lookup-match');
        }
      }
      const heading = document.querySelector('.entry > .hwg, .entry > .hg, .entry > .hw');
      if (heading && \(entry.summary.audioID != nil)) {
        const controls = document.createElement('span');
        controls.className = 'headword-audio';
        ['us', 'uk'].forEach(accent => {
          const button = document.createElement('button');
          button.className = 'audio-button';
          button.textContent = '▶ ' + accent.toUpperCase();
          button.title = 'Play ' + accent.toUpperCase() + ' headword pronunciation';
          button.setAttribute('aria-label', button.title);
          button.onclick = () => window.webkit.messageHandlers.headword.postMessage(accent);
          controls.append(button);
        });
        heading.append(controls);
      }
      document.querySelectorAll('[data-audio-id]').forEach(example => {
        const id = example.dataset.audioId;
        const button = document.createElement('button');
        button.className = 'audio-button';
        button.textContent = '▶';
        button.onclick = () => window.webkit.messageHandlers.play.postMessage(id);
        example.after(button);
      });
      function updateAudioAvailability(ids) {
        const imported = new Set(ids);
        document.querySelectorAll('[data-audio-id]').forEach(example => {
          const button = example.nextElementSibling;
          button.title = (imported.has(example.dataset.audioId) ? 'Play audio' : 'Generate and play speech') +
            (review.has(example.dataset.audioId) ? ' · Example contains editorial alternatives' : '');
          button.setAttribute('aria-label', button.title + ': ' + example.textContent);
        });
      }
      updateAudioAvailability(\(imported));
      (() => {
        let hover = null;
        let version = 0;
        const underlines = document.createElement('div');
        underlines.setAttribute('aria-hidden', 'true');
        document.body.append(underlines);
        const contains = (rect, x, y) =>
          x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
        function clear() {
          version++;
          hover = null;
          underlines.replaceChildren();
          document.body.style.cursor = '';
        }
        async function termAt(event) {
          if (event.target.closest('a, button, input, textarea')) return null;
          const caret = document.caretRangeFromPoint(event.clientX, event.clientY);
          if (!caret || caret.startContainer.nodeType !== Node.TEXT_NODE) return null;
          const node = caret.startContainer;
          let offset = null;
          for (const position of [caret.startOffset, caret.startOffset - 1]) {
            if (position < 0 || position >= node.length) continue;
            const character = document.createRange();
            character.setStart(node, position);
            character.setEnd(node, position + 1);
            if (Array.from(character.getClientRects()).some(rect =>
              contains(rect, event.clientX, event.clientY))) {
              offset = position;
              break;
            }
          }
          if (offset === null) return null;
          // A definition or example can split a phrase across emphasis spans.
          const paragraph = node.parentElement.closest('p, li, td, .x_xdt, .ex, .trans, .df, .note') ||
            node.parentElement;
          const walker = document.createTreeWalker(paragraph, NodeFilter.SHOW_TEXT);
          const nodes = [];
          let text = '';
          let targetOffset = 0;
          while (walker.nextNode()) {
            const current = walker.currentNode;
            nodes.push({node: current, start: text.length});
            if (current === node) targetOffset = text.length + offset;
            text += current.textContent;
          }
          const result = await window.webkit.messageHandlers.lookup.postMessage({text, offset: targetOffset});
          if (!result || !node.isConnected) return null;
          const range = document.createRange();
          const start = nodes.find(item => item.start + item.node.length > result.location);
          const end = nodes.find(item => item.start + item.node.length >= result.location + result.length);
          range.setStart(start.node, result.location - start.start);
          range.setEnd(end.node, result.location + result.length - end.start);
          return {term: result.term, source: result.source, range};
        }
        document.addEventListener('mousemove', async event => {
          if (hover && Array.from(hover.range.getClientRects()).some(rect =>
            contains(rect, event.clientX, event.clientY))) return;
          clear();
          if (event.buttons || !window.getSelection().isCollapsed) return;
          const request = version;
          const result = await termAt(event).catch(() => null);
          if (request !== version || !result) return;
          hover = result;
          for (const rect of result.range.getClientRects()) {
            const line = document.createElement('span');
            line.className = 'lookup-underline';
            Object.assign(line.style, {
              left: rect.left + 'px', top: rect.bottom - 1 + 'px', width: rect.width + 'px'
            });
            underlines.append(line);
          }
          document.body.style.cursor = 'pointer';
        });
        document.addEventListener('click', async event => {
          if (event.button || event.target.closest('a, button, input, textarea') ||
            !window.getSelection().isCollapsed) return;
          const result = hover && Array.from(hover.range.getClientRects()).some(rect =>
            contains(rect, event.clientX, event.clientY)) ? hover : await termAt(event).catch(() => null);
          if (!result) return;
          clear();
          window.webkit.messageHandlers.follow.postMessage({
            term: result.term, source: result.source
          });
        });
        document.addEventListener('mouseleave', clear);
        document.addEventListener('selectionchange', () => {
          if (!window.getSelection().isCollapsed) clear();
        });
        window.addEventListener('scroll', clear);
        window.addEventListener('resize', clear);
      })();
      </script></body></html>
      """
    view.loadHTMLString(html, baseURL: entry.resources)
  }

  static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    view.configuration.userContentController.removeScriptMessageHandler(forName: "play")
    view.configuration.userContentController.removeScriptMessageHandler(forName: "headword")
    view.configuration.userContentController.removeScriptMessageHandler(forName: "follow")
    view.configuration.userContentController.removeScriptMessageHandler(forName: "lookup")
    view.navigationDelegate = nil
  }

  @MainActor
  final class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply,
    WKNavigationDelegate
  {
    var selection: EntrySummary.ID?
    var anchor: String?
    var localIDs: [String] = []
    var play: (String) -> Void
    var playHeadword: (Accent) -> Void
    var follow: (DictionaryLink) -> Void
    var lookup: (String, Int) async throws -> LookupTerm?

    init(
      play: @escaping (String) -> Void, playHeadword: @escaping (Accent) -> Void,
      follow: @escaping (DictionaryLink) -> Void,
      lookup: @escaping (String, Int) async throws -> LookupTerm?
    ) {
      self.play = play
      self.playHeadword = playHeadword
      self.follow = follow
      self.lookup = lookup
    }

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      if message.name == "follow", let values = message.body as? [String: String],
        let term = values["term"], let source = values["source"]
      {
        if term == selection?.matchedTerm, let webView = message.webView {
          scrollToMatch(in: webView)
        }
        follow(.lookup(term, source: source))
      } else if let value = message.body as? String {
        if message.name == "headword", let accent = Accent(rawValue: value) {
          playHeadword(accent)
        } else if message.name == "play" {
          play(value)
        }
      }
    }

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
      replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
      guard let body = message.body as? [String: Any], let text = body["text"] as? String,
        let offset = body["offset"] as? Int
      else {
        replyHandler(nil, "Invalid lookup")
        return
      }
      Task {
        do {
          let result = try await lookup(text, offset)
          replyHandler(
            result.map {
              [
                "term": $0.term, "source": $0.source,
                "location": $0.range.location, "length": $0.range.length,
              ]
            },
            nil)
        } catch { replyHandler(nil, error.localizedDescription) }
      }
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
      if navigationAction.navigationType == .linkActivated {
        if let address = navigationAction.request.url?.absoluteString,
          let link = DictionaryLink(address)
        {
          if case .reference(_, let target) = link, target == anchor {
            // Repeated clicks must still scroll after the reader moves away from the target.
            scrollToAnchor(in: webView)
          }
          follow(link)
        }
        decisionHandler(.cancel)
      } else {
        decisionHandler(.allow)
      }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      if anchor != nil {
        scrollToAnchor(in: webView)
      } else {
        scrollToMatch(in: webView)
      }
    }

    func scrollToMatch(in webView: WKWebView) {
      webView.evaluateJavaScript(
        "(() => { const target = document.querySelector('.lookup-match'); if (target) target.scrollIntoView({block: 'nearest'}); else window.scrollTo(0, 0); })()"
      )
    }

    func scrollToAnchor(in webView: WKWebView) {
      if let anchor {
        let encoded = String(data: try! JSONEncoder().encode(anchor), encoding: .utf8)!
        webView.evaluateJavaScript("document.getElementById(\(encoded))?.scrollIntoView()")
      } else {
        webView.evaluateJavaScript("window.scrollTo(0, 0)")
      }
    }
  }
}
