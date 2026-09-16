import DictionaryCore
import SwiftUI
import WebKit

struct EntryWebView: NSViewRepresentable {
  let entry: Entry
  let audioFolder: URL
  let play: (String) -> Void
  let follow: (String) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(play: play, follow: follow) }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(context.coordinator, name: "play")
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    view.setValue(false, forKey: "drawsBackground")
    return view
  }

  func updateNSView(_ view: WKWebView, context: Context) {
    context.coordinator.play = play
    context.coordinator.follow = follow
    let localIDs = entry.examples.filter {
      AudioFiles.local(id: $0.id, source: entry.summary.source, folder: audioFolder)
        != nil
    }.map(\.id)
    let key = entry.summary.id + audioFolder.path + localIDs.joined()
    if context.coordinator.key == key { return }
    context.coordinator.key = key
    let imported = String(data: try! JSONEncoder().encode(localIDs), encoding: .utf8)!
    let reviewIDs = String(
      data: try! JSONEncoder().encode(entry.examples.filter(\.needsReview).map(\.id)),
      encoding: .utf8)!
    let html = """
      <!doctype html><html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src file: data:">
      <style>\(entry.css)
      :root { color-scheme: light dark; }
      body { padding: 12px 24px 48px; margin: 0; font-size: 17px; line-height: 1.6; }
      .entry > .hg, .entry > .hwg { padding-bottom: 16px; }
      .ex { background: light-dark(#f0f5f3, #263730); border-radius: 3px; }
      [data-audio-id] { cursor: pointer; }
      .audio-button { font: 11px -apple-system; cursor: pointer; margin: 0 5px; padding: 3px 7px;
        color: light-dark(#17694d, #8bdfb3); border: 1px solid light-dark(#b9d5c6,#426653);
        border-radius: 5px; background: light-dark(#f3faf6,#23392e); vertical-align: 1px; }
      .audio-button:focus-visible { outline: 2px solid #258b68; }
      .audio-button:hover:enabled { background: light-dark(#dcefe3,#365344); }
      .audio-button:disabled { opacity: 0.5; cursor: default; }
      [data-d-pr="US"] { display: none; }
      </style></head><body>\(entry.html)
      <script>
      const imported = new Set(\(imported));
      const review = new Set(\(reviewIDs));
      document.querySelectorAll('[data-audio-id]').forEach(example => {
        const id = example.dataset.audioId;
        const button = document.createElement('button');
        button.className = 'audio-button';
        button.textContent = '▶ Audio';
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
    view.navigationDelegate = nil
  }

  @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var key = ""
    var play: (String) -> Void
    var follow: (String) -> Void

    init(play: @escaping (String) -> Void, follow: @escaping (String) -> Void) {
      self.play = play
      self.follow = follow
    }

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      if let id = message.body as? String { play(id) }
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
