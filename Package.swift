// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "AudibleDictionary",
  platforms: [.macOS(.v14)],
  dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")],
  targets: [
    .target(name: "DictionaryCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
    .executableTarget(name: "AudibleDictionary", dependencies: ["DictionaryCore"]),
    .testTarget(
      name: "DictionaryCoreTests",
      dependencies: ["DictionaryCore", .product(name: "GRDB", package: "GRDB.swift")],
      path: "tests/DictionaryCoreTests"),
    .testTarget(
      name: "DictionaryAppTests",
      dependencies: ["AudibleDictionary", .product(name: "GRDB", package: "GRDB.swift")],
      path: "tests/DictionaryAppTests"),
  ]
)
