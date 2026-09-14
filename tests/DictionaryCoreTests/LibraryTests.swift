import DictionaryCore
import Foundation
import GRDB
import Testing

struct LibraryTests {
  @Test func searchRankingFilteringAndContext() async throws {
    #expect(Library.normalized(" Lumifern’s ") == "lumifern's")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let database = try DatabaseQueue(path: folder.appendingPathComponent("dictionary.sqlite").path)
    let sql = """
      CREATE TABLE dictionaries(source TEXT,css TEXT,resource_path TEXT);
      INSERT INTO dictionaries VALUES('ODE','','/tmp'),('WISDOM','','/tmp');
      CREATE TABLE entries(id TEXT,source TEXT,source_id TEXT,headword TEXT,search_key TEXT,audio_id TEXT,html TEXT);
      INSERT INTO entries VALUES('a','ODE','dummy_a','lumifern','lumifern','audio_a','<p>Invented plant</p>'),
        ('b','WISDOM','dummy_b','lumiferna','lumiferna','audio_b','<p>架空の植物</p>'),
        ('c','ODE','dummy_c','100%lumifern','100%lumifern','audio_c','');
      CREATE TABLE aliases(term TEXT,entry_id TEXT);
      INSERT INTO aliases VALUES('lumifern','a'),('lumiferna','b'),('lumiferns','a'),('100%lumifern','c');
      CREATE TABLE examples(id TEXT,entry_id TEXT,text TEXT,needs_review INTEGER);
      INSERT INTO examples VALUES('example_a','a','The lumifern glows softly.',0);
      """
    try await database.write { db in try db.execute(sql: sql) }
    let library = try Library(folder: folder)
    let results = try await library.search("LUMIFERN", source: "All")
    #expect(results.map(\.id) == ["a", "b"])
    let filtered = try await library.search("lumi", source: "WISDOM")
    #expect(filtered.map(\.id) == ["b"])
    let punctuation = try await library.search("100%", source: "All")
    #expect(punctuation.map(\.id) == ["c"])
    let entry = try await library.entry("a")
    #expect(entry?.html == "<p>Invented plant</p>")
    #expect(entry?.examples.first?.id == "example_a")
    #expect(entry?.examples.first?.needsReview == false)
    let reference = try await library.reference("dummy_a", source: "ODE")
    #expect(reference?.id == "a")
  }

  @Test func audioFilesRespectDictionaryAccentAndPriority() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("fallback/ODE/uk"), withIntermediateDirectories: true)
    let fallback = folder.appendingPathComponent("fallback/ODE/uk/dummy.mp4")
    try Data().write(to: fallback)
    #expect(AudioFiles.local(id: "dummy", source: "ODE", accent: .uk, folder: folder) == fallback)
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("ODE/uk"), withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("ODE/uk/dummy.mp4")
    try Data().write(to: file)
    #expect(AudioFiles.local(id: "dummy", source: "ODE", accent: .uk, folder: folder) == file)
    #expect(AudioFiles.local(id: "dummy", source: "ODE", accent: .us, folder: folder) == nil)
    #expect(AudioFiles.local(id: "dummy", source: "WISDOM", accent: .uk, folder: folder) == nil)
  }
}
