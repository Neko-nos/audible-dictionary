import Foundation

public enum Accent: String, Sendable {
  case us, uk
  public var label: String { rawValue.uppercased() }
}

public enum AudioFiles {
  public static func local(id: String, source: String, accent: Accent? = nil, folder: URL) -> URL? {
    for root in [
      folder.appendingPathComponent("edited"), folder, folder.appendingPathComponent("fallback"),
    ] {
      var directory = root.appendingPathComponent(source)
      if let accent { directory.appendPathComponent(accent.rawValue) }
      let url = directory.appendingPathComponent(id).appendingPathExtension("caf")
      if FileManager.default.fileExists(atPath: url.path) { return url }
    }
    return nil
  }

  public static func edited(id: String, source: String, accent: Accent? = nil, folder: URL) -> URL {
    var directory = folder.appendingPathComponent("edited").appendingPathComponent(source)
    if let accent { directory.appendPathComponent(accent.rawValue) }
    return directory.appendingPathComponent(id).appendingPathExtension("caf")
  }
}
