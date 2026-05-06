import Foundation
import Testing

struct WebHostExampleTests {
  @Test("example imports the combined WebHost CLI runner")
  func exampleImportsCombinedWebHostCLIRunner() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/WebHostExample/main.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("import SwiftTUI"))
    #expect(source.contains("import SwiftTUIWebHostCLI"))
    #expect(!source.contains("import SwiftTUICLI"))
  }
}
