import Foundation

public enum DictionaryLink: Equatable, Sendable {
  case reference(String, anchor: String?)
  case lookup(String, source: String)

  public init?(_ address: String) {
    let parts = address.split(separator: ":", maxSplits: 2)
    guard parts.count == 3, parts[0] == "x-dictionary", parts[1] == "r" else {
      return nil
    }
    // WebKit percent-encodes the fragment separator in these opaque dictionary URLs.
    let destination = String(parts[2]).removingPercentEncoding ?? String(parts[2])
    let sourceID = destination.prefix { $0 != ":" && $0 != "#" }
    // Oxford can append a display word after the XPointer expression.
    let anchor = destination.range(of: "#xpointer(//*[@id='").map {
      String(destination[$0.upperBound...].prefix { $0 != "'" })
    }
    self = .reference(String(sourceID), anchor: anchor)
  }
}
