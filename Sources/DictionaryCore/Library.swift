import Foundation
import GRDB

public struct EntrySummary: Decodable, FetchableRecord, Identifiable, Sendable {
  public let entryID: String
  public let source: String
  public let headword: String
  public let audioID: String
  public let matchedTerm: String

  public struct ID: Hashable, Sendable {
    public let entryID: String
    public let matchedTerm: String
  }

  public var id: ID { ID(entryID: entryID, matchedTerm: matchedTerm) }

  public var title: String {
    matchedTerm == Library.normalized(headword) ? headword : matchedTerm
  }
}

public struct Example: Decodable, FetchableRecord, Sendable {
  public let id: String
  public let text: String
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
      let matches = try EntrySummary.fetchAll(
        db,
        sql:
          """
          SELECT e.id AS entryID, e.source, e.headword, e.audio_id AS audioID, a.term AS matchedTerm
          FROM aliases a JOIN entries e ON e.id = a.entry_id
          WHERE a.term >= ? AND a.term < ? AND (? = 'All' OR e.source = ?)
          ORDER BY a.term, a.term != e.search_key, e.source, e.id LIMIT 100
          """, arguments: [term, term + "\u{10FFFF}", source, source])
      // Short fragments have too many plausible corrections to suggest a useful word.
      if !matches.isEmpty || term.count < 4 { return matches }
      let letters = Array(term)
      // Allow one edit for 4–7 characters and at most two for longer queries.
      let limit = min(2, letters.count / 4)
      db.add(
        function: DatabaseFunction("spellingDistance", argumentCount: 1, pure: true) { values in
          Self.spellingDistance(String.fromDatabaseValue(values[0])!, from: letters, limit: limit)
        })
      return try EntrySummary.fetchAll(
        db,
        sql:
          """
          SELECT e.id AS entryID, e.source, e.headword, e.audio_id AS audioID,
              a.term AS matchedTerm, spellingDistance(a.term) AS distance
          FROM aliases a JOIN entries e ON e.id = a.entry_id
          WHERE length(a.term) BETWEEN ? AND ? AND distance <= ? AND (? = 'All' OR e.source = ?)
          ORDER BY distance, a.term != e.search_key, a.term, e.source, e.id LIMIT 100
          """, arguments: [letters.count - limit, letters.count + limit, limit, source, source])
    }
  }

  private static func spellingDistance(_ term: String, from query: [Character], limit: Int) -> Int {
    let letters = Array(term)
    var previous = Array(0...query.count)
    var older = Array(repeating: limit + 1, count: query.count + 1)
    var current = older
    for row in 1...letters.count {
      current[0] = row
      // Cells beyond this diagonal band cannot lead to a match within the edit limit.
      let start = max(1, row - limit)
      let end = min(query.count, row + limit)
      if start > 1 { current[start - 1] = limit + 1 }
      if end < query.count { current[end + 1] = limit + 1 }
      var best = current[0]
      for column in start...end {
        current[column] = min(
          previous[column] + 1, current[column - 1] + 1,
          previous[column - 1] + (letters[row - 1] == query[column - 1] ? 0 : 1))
        if row > 1 && column > 1 && letters[row - 1] == query[column - 2]
          && letters[row - 2] == query[column - 1]
        {
          current[column] = min(current[column], older[column - 2] + 1)
        }
        best = min(best, current[column])
      }
      if best > limit { return limit + 1 }
      swap(&older, &previous)
      swap(&previous, &current)
    }
    return previous[query.count]
  }

  public func entry(_ id: String) throws -> Entry? {
    try database.read { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql:
            """
            SELECT e.id AS entryID,e.source,e.headword,e.audio_id AS audioID,e.search_key AS matchedTerm,
                e.html,d.css,d.resource_path
            FROM entries e JOIN dictionaries d ON d.source=e.source WHERE e.id=?
            """, arguments: [id])
      else { return nil }
      let examples = try Example.fetchAll(
        db, sql: "SELECT id,text,needs_review AS needsReview FROM examples WHERE entry_id=?",
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
          """
          SELECT id AS entryID,source,headword,audio_id AS audioID,search_key AS matchedTerm
          FROM entries WHERE source_id=? AND source=?
          """,
        arguments: [sourceID, source])
    }
  }
}
