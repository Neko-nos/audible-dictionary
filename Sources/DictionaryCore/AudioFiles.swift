import Foundation

public enum Accent: String, CaseIterable, Identifiable, Sendable {
  case us, uk
  public var id: String { rawValue }
  public var label: String { rawValue.uppercased() }
}

public enum AudioFiles {
  public static func local(id: String, source: String, accent: Accent, folder: URL) -> URL? {
    for root in [folder, folder.appendingPathComponent("fallback")] {
      let url = root.appendingPathComponent(source).appendingPathComponent(accent.rawValue)
        .appendingPathComponent(id).appendingPathExtension("mp4")
      if FileManager.default.fileExists(atPath: url.path) { return url }
    }
    return nil
  }
}
