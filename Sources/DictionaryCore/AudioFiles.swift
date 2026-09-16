import Foundation

public enum Accent: String, CaseIterable, Identifiable, Sendable {
  case us, uk
  public var id: String { rawValue }
  public var label: String { rawValue.uppercased() }
}

public enum AudioFiles {
  public static func local(id: String, source: String, accent: Accent? = nil, folder: URL) -> URL? {
    for root in [folder, folder.appendingPathComponent("fallback")] {
      var directory = root.appendingPathComponent(source)
      if let accent { directory.appendPathComponent(accent.rawValue) }
      let url = directory.appendingPathComponent(id).appendingPathExtension("mp4")
      if FileManager.default.fileExists(atPath: url.path) { return url }
    }
    return nil
  }
}
