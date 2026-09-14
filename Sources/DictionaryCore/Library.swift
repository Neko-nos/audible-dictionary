import Foundation
import GRDB

public struct EntrySummary: Decodable, FetchableRecord, Identifiable, Hashable, Sendable {
  public let id: String
  public let source: String
  public let headword: String
  public let audioID: String
}

public struct Example: Decodable, FetchableRecord, Identifiable, Sendable {
  public let id: String
  public let needsReview: Bool
}

public struct Entry: Sendable {
  public let summary: EntrySummary
  public let html: String
  public let css: String
  public let resources: URL
  public let examples: [Example]
}

public actor Library {
  private let database: DatabaseQueue

  public init(folder: URL) throws {
    var configuration = Configuration()
    configuration.readonly = true
    database = try DatabaseQueue(
      path: folder.appendingPathComponent("dictionary.sqlite").path, configuration: configuration)
    _ = try database.read { db in
      try String.fetchOne(db, sql: "SELECT source FROM dictionaries LIMIT 1")
    }
  }

  public static func normalized(_ text: String) -> String {
    text.precomposedStringWithCompatibilityMapping.lowercased()
      .replacingOccurrences(of: "’", with: "'")
      .replacingOccurrences(of: "‘", with: "'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func search(_ query: String, source: String) throws -> [EntrySummary] {
    let term = Self.normalized(query)
    if term.isEmpty { return [] }
    // Range matching uses the index and treats punctuation literally, including % and _.
    return try database.read { db in
      try EntrySummary.fetchAll(
        db,
        sql:
          """
          SELECT DISTINCT e.id, e.source, e.headword, e.audio_id AS audioID, e.search_key
          FROM aliases a JOIN entries e ON e.id = a.entry_id
          WHERE a.term >= ? AND a.term < ? AND (? = 'All' OR e.source = ?)
          ORDER BY CASE WHEN e.search_key = ? THEN 0 WHEN a.term = ? THEN 1 ELSE 2 END,
              e.search_key, e.source, e.id LIMIT 100
          """, arguments: [term, term + "\u{10FFFF}", source, source, term, term])
    }
  }

  public func entry(_ id: String) throws -> Entry? {
    try database.read { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql:
            """
            SELECT e.id,e.source,e.headword,e.audio_id AS audioID,e.html,d.css,d.resource_path
            FROM entries e JOIN dictionaries d ON d.source=e.source WHERE e.id=?
            """, arguments: [id])
      else { return nil }
      let examples = try Example.fetchAll(
        db, sql: "SELECT id,needs_review AS needsReview FROM examples WHERE entry_id=?",
        arguments: [id])
      return Entry(
        summary: try EntrySummary(row: row), html: row["html"], css: row["css"],
        resources: URL(fileURLWithPath: row["resource_path"]), examples: examples)
    }
  }

  public func reference(_ sourceID: String, source: String) throws -> EntrySummary? {
    try database.read { db in
      try EntrySummary.fetchOne(
        db,
        sql:
          "SELECT id,source,headword,audio_id AS audioID FROM entries WHERE source_id=? AND source=?",
        arguments: [sourceID, source])
    }
  }
}
