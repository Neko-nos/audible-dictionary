import DictionaryCore
import SwiftUI
import WebKit

struct EntryWebView: NSViewRepresentable {
  let entry: Entry
  let audioFolder: URL
  let textSize: Double
  let matchedTerm: String?
  let play: (String) -> Void
  let playHeadword: (Accent) -> Void
  let follow: (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(play: play, playHeadword: playHeadword, follow: follow)
  }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(context.coordinator, name: "play")
    configuration.userContentController.add(context.coordinator, name: "headword")
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    view.setValue(false, forKey: "drawsBackground")
    return view
  }

  func updateNSView(_ view: WKWebView, context: Context) {
    context.coordinator.play = play
    context.coordinator.playHeadword = playHeadword
    context.coordinator.follow = follow
    // The dictionaries' 12pt body size is 16 CSS pixels at their original scale.
    view.pageZoom = textSize / 16
    let localIDs = entry.examples.filter {
      AudioFiles.local(id: $0.id, source: entry.summary.source, folder: audioFolder)
        != nil
    }.map(\.id)
    let key = entry.summary.entryID + audioFolder.path + localIDs.joined() + (matchedTerm ?? "")
    if context.coordinator.key == key { return }
    context.coordinator.key = key
    let imported = String(data: try! JSONEncoder().encode(localIDs), encoding: .utf8)!
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
      .lookup-match { background: light-dark(#bed8fc, #294f7c); }
      [data-audio-id] { cursor: pointer; }
      .headword-audio { display: inline-flex; gap: 4px; margin-left: 12px; vertical-align: middle; }
      .audio-button { font: 11px -apple-system; cursor: pointer; margin: 0 3px; padding: 3px 5px;
        color: light-dark(#666, #bbb); border: 0; border-radius: 4px;
        background: transparent; vertical-align: 1px; }
      .audio-button:focus-visible { outline: 2px solid Highlight; }
      .audio-button:hover { background: light-dark(#eee, #333); }
      [data-d-pr="US"] { display: none; }
      </style></head><body>\(entry.html)
      <script>
      const imported = new Set(\(imported));
      const review = new Set(\(reviewIDs));
      const match = \(match);
      if (match && match !== \(headword)) {
        const word = Array.from(document.querySelectorAll('[data-search-term]'))
          .find(node => node.dataset.searchTerm === match);
        if (word) {
          const section = word.closest('.drvsec, .csec') || word;
          section.classList.add('lookup-match');
          requestAnimationFrame(() => section.scrollIntoView({block: 'nearest'}));
        }
      }
      const heading = document.querySelector('.entry > .hwg, .entry > .hg, .entry > .hw');
      if (heading) {
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
        button.title = (imported.has(id) ? 'Play audio' : 'Generate and play speech') +
          (review.has(id) ? ' · Example contains editorial alternatives' : '');
        button.setAttribute('aria-label', button.title + ': ' + example.textContent);
        const play = () => window.webkit.messageHandlers.play.postMessage(id);
        button.onclick = play;
        example.onclick = event => {
          if (!event.target.closest('a') && event.target.closest('[data-audio-id]') === example) play();
        };
        example.after(button);
      });
      </script></body></html>
      """
    view.loadHTMLString(html, baseURL: entry.resources)
  }

  static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    view.configuration.userContentController.removeScriptMessageHandler(forName: "play")
    view.configuration.userContentController.removeScriptMessageHandler(forName: "headword")
    view.navigationDelegate = nil
  }

  @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var key = ""
    var play: (String) -> Void
    var playHeadword: (Accent) -> Void
    var follow: (String) -> Void

    init(
      play: @escaping (String) -> Void, playHeadword: @escaping (Accent) -> Void,
      follow: @escaping (String) -> Void
    ) {
      self.play = play
      self.playHeadword = playHeadword
      self.follow = follow
    }

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      if let value = message.body as? String {
        if message.name == "headword", let accent = Accent(rawValue: value) {
          playHeadword(accent)
        } else if message.name == "play" {
          play(value)
        }
      }
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
      if navigationAction.navigationType == .linkActivated {
        if let url = navigationAction.request.url, url.scheme == "x-dictionary" {
          follow(url.absoluteString)
        }
        decisionHandler(.cancel)
      } else {
        decisionHandler(.allow)
      }
    }
  }
}
