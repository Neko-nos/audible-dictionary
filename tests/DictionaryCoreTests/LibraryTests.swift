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
        ('c','ODE','dummy_c','100%lumifern','100%lumifern','audio_c',''),
        ('d','WISDOM','dummy_d','lumifernability','lumifernability','audio_d',''),
        ('e','ODE','dummy_e','kumifernability','kumifernability','audio_e',''),
        ('f','ODE','dummy_f','zavu','zavu','audio_f','');
      CREATE TABLE aliases(term TEXT,entry_id TEXT,PRIMARY KEY(term,entry_id));
      INSERT INTO aliases VALUES('lumifern','a'),('lumiferna','b'),('lumiferns','a'),('100%lumifern','c'),
        ('lumifernability','a'),('lumifernability','d'),('aumifernability','a'),
        ('lumifern sprig','a'),('lumifern stone','a'),
        ('kumifernability','e'),('zavu','f');
      CREATE TABLE examples(id TEXT,entry_id TEXT,text TEXT,needs_review INTEGER);
      INSERT INTO examples VALUES('example_a','a','The lumifern glows softly.',0);
      """
    try await database.write { db in try db.execute(sql: sql) }
    let library = try Library(folder: folder)
    let results = try await library.search("LUMIFERN", source: "All")
    #expect(results.map(\.entryID) == ["a", "a", "a", "b", "d", "a", "a"])
    #expect(
      results.map(\.title) == [
        "lumifern", "lumifern sprig", "lumifern stone", "lumiferna",
        "lumifernability", "lumifernability", "lumiferns",
      ])
    #expect(Set(results.map(\.id)).count == results.count)
    let filtered = try await library.search("lumi", source: "WISDOM")
    #expect(filtered.map(\.entryID) == ["b", "d"])
    let derivative = try await library.search("lumifernability", source: "All")
    #expect(derivative.map(\.entryID) == ["d", "a"])
    #expect(derivative.map(\.title) == ["lumifernability", "lumifernability"])
    let derivedPrefix = try await library.search("lumifernabilit", source: "All")
    #expect(derivedPrefix.map(\.entryID) == ["d", "a"])
    let compound = try await library.search("lumifern sprig", source: "ODE")
    #expect(compound.map(\.title) == ["lumifern sprig"])
    let parent = try await library.entry(#require(compound.first).entryID)
    #expect(parent?.summary.headword == "lumifern")
    let compoundTypo = try await library.search("lumifern sprigg", source: "ODE")
    #expect(compoundTypo.map(\.id) == compound.map(\.id))
    for typo in ["lumifren", "lumfern", "lumiffern", "lumixern", "xumifern"] {
      let suggestions = try await library.search(typo, source: "ODE")
      #expect(suggestions.first?.entryID == "a")
      #expect(suggestions.first?.title == "lumifern")
    }
    let trailingTypo = try await library.search("lumiferndd", source: "ODE")
    #expect(trailingTypo.map(\.title) == ["lumifern", "lumiferns"])
    #expect(Set(trailingTypo.map(\.id)).count == 2)
    let derivedTypo = try await library.search("lumifernabilty", source: "ODE")
    #expect(derivedTypo.map(\.entryID) == ["a", "e", "a"])
    #expect(derivedTypo.map(\.title) == ["lumifernability", "kumifernability", "aumifernability"])
    for typo in ["lumifrenabilty", "lumifrnabilty", "lummifernabiility"] {
      let twoEdits = try await library.search(typo, source: "ODE")
      #expect(twoEdits.map(\.entryID) == ["a"])
      #expect(twoEdits.first?.title == "lumifernability")
    }
    let distant = try await library.search("xumifrenabilty", source: "All")
    #expect(distant.isEmpty)
    let shortTypo = try await library.search("zavx", source: "ODE")
    #expect(shortTypo.map(\.entryID) == ["f"])
    let shortDistant = try await library.search("zaxx", source: "ODE")
    #expect(shortDistant.isEmpty)
    let filteredTypo = try await library.search("lumifrena", source: "WISDOM")
    #expect(filteredTypo.map(\.entryID) == ["b"])
    let punctuation = try await library.search("100%", source: "All")
    #expect(punctuation.map(\.entryID) == ["c"])
    let entry = try await library.entry("a")
    #expect(entry?.html == "<p>Invented plant</p>")
    #expect(entry?.examples.first?.id == "example_a")
    #expect(entry?.examples.first?.text == "The lumifern glows softly.")
    #expect(entry?.examples.first?.needsReview == false)
    let reference = try await library.reference("dummy_a", source: "ODE")
    #expect(reference?.entryID == "a")
    #expect(reference?.id == results.first?.id)
    let context = "架空🌱: a lumifern sprig, glowing softly."
    let phraseRange = (context as NSString).range(of: "lumifern sprig")
    for offset in [phraseRange.location, NSMaxRange(phraseRange) - 1] {
      let phrase = try await library.lookup(context, at: offset, source: "ODE")
      #expect(phrase?.term == "lumifern sprig")
      #expect(phrase?.range == phraseRange)
    }
    let wordContext = "A LUMIFERN glows."
    let wordRange = (wordContext as NSString).range(of: "LUMIFERN")
    let word = try await library.lookup(wordContext, at: wordRange.location, source: "All")
    #expect(word?.term == "lumifern")
    #expect(word?.range == wordRange)
    #expect(try await library.lookup(context, at: phraseRange.location, source: "WISDOM") == nil)
    #expect(try await library.lookup(context, at: NSMaxRange(phraseRange), source: "All") == nil)
  }

  @Test func japaneseSearchAndCrossReferences() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let database = try DatabaseQueue(path: folder.appendingPathComponent("dictionary.sqlite").path)
    let sql = """
      CREATE TABLE dictionaries(source TEXT,css TEXT,resource_path TEXT);
      INSERT INTO dictionaries VALUES('WISDOM','','/tmp'),('WISDOM_JE','','/tmp'),('ODE','','/tmp');
      CREATE TABLE entries(id TEXT,source TEXT,source_id TEXT,headword TEXT,search_key TEXT,audio_id TEXT,html TEXT);
      INSERT INTO entries VALUES
        ('en','WISDOM','WDEJ_dummy','lumifern','lumifern','audio_en',''),
        ('ja','WISDOM_JE','WDJE00dummy','るみぐさ【瑠光草】','るみぐさ【瑠光草】',NULL,'<p>lumifern</p>'),
        ('ode','ODE','WDJE00dummy','lumifern','lumifern','audio_ode','');
      CREATE TABLE aliases(term TEXT,entry_id TEXT,PRIMARY KEY(term,entry_id));
      INSERT INTO aliases VALUES('lumifern','en'),('るみぐさ【瑠光草】','ja'),('るみぐさ','ja'),
        ('瑠光草','ja'),('瑠輝草','ja'),('ルミグサ雲','ja');
      CREATE TABLE examples(id TEXT,entry_id TEXT,text TEXT,needs_review INTEGER);
      """
    try await database.write { db in try db.execute(sql: sql) }
    let library = try Library(folder: folder)
    for query in ["るみぐさ", "るみく\u{3099}さ", "瑠光草", "瑠輝草", "ﾙﾐｸﾞｻ"] {
      let matches = try await library.search(query, source: "WISDOM_JE")
      #expect(!matches.isEmpty)
      #expect(matches.allSatisfy { $0.entryID == "ja" })
      #expect(matches.allSatisfy { $0.dictionaryTitle == "Japanese – English" })
    }
    let all = try await library.search("瑠光", source: "All")
    #expect(all.map(\.entryID) == ["ja"])
    let englishOnly = try await library.search("瑠光", source: "WISDOM")
    #expect(englishOnly.isEmpty)
    for source in ["WISDOM", "WISDOM_JE", "All"] {
      for (text, spelling) in [
        ("🌱架空のるみぐさを眺める。", "るみぐさ"),
        ("🌱空想の瑠光草を調べる。", "瑠光草"),
        ("🌱ﾙﾐｸﾞｻ雲が浮かぶ。", "ﾙﾐｸﾞｻ雲"),
        ("🌱るみく\u{3099}さの話。", "るみく\u{3099}さ"),
      ] {
        let range = (text as NSString).range(of: spelling)
        for offset in [range.location, NSMaxRange(range) - 1] {
          let match = try await library.lookup(text, at: offset, source: source)
          #expect(match?.term == Library.normalized(spelling))
          #expect(match?.range == range)
          #expect(match?.source == (source == "All" ? "All" : "WISDOM_JE"))
        }
      }
    }
    let englishLookup = try await library.lookup("The lumifern glows.", at: 5, source: "WISDOM_JE")
    #expect(englishLookup?.term == "lumifern")
    #expect(englishLookup?.source == "WISDOM")
    let entry = try #require(try await library.entry("ja"))
    #expect(entry.summary.audioID == nil)
    #expect(entry.html == "<p>lumifern</p>")
    for source in ["WISDOM", "WISDOM_JE"] {
      let japanese = try await library.reference("WDJE00dummy", source: source)
      #expect(japanese?.entryID == "ja")
      let english = try await library.reference("WDEJ_dummy", source: source)
      #expect(english?.entryID == "en")
    }
    let oxford = try await library.reference("WDJE00dummy", source: "ODE")
    #expect(oxford?.entryID == "ode")
  }

  @Test(arguments: [(nil, "ODE"), (Accent.us, "ODE/us"), (Accent.uk, "ODE/uk")])
  func audioFilesRespectDictionaryAccentAndPriority(accent: Accent?, directory: String) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("fallback/\(directory)"), withIntermediateDirectories: true)
    let fallback = folder.appendingPathComponent("fallback/\(directory)/dummy.caf")
    try Data().write(to: fallback)
    #expect(
      AudioFiles.local(id: "dummy", source: "ODE", accent: accent, folder: folder) == fallback)
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent(directory), withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("\(directory)/dummy.caf")
    try Data().write(to: file)
    #expect(AudioFiles.local(id: "dummy", source: "ODE", accent: accent, folder: folder) == file)
    if let accent {
      #expect(
        AudioFiles.local(
          id: "dummy", source: "ODE", accent: accent == .us ? .uk : .us, folder: folder) == nil)
    }
    #expect(AudioFiles.local(id: "dummy", source: "WISDOM", accent: accent, folder: folder) == nil)
  }
}
