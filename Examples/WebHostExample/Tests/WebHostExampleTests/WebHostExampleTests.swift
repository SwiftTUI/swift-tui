import Foundation
import Testing

struct WebHostExampleTests {
  @Test("example uses the SwiftTUI convenience import")
  func exampleUsesSwiftTUIConvenienceImport() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/WebHostExample/main.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("import SwiftTUI\n"))
    #expect(!source.contains("WebHostCLIRunner.run"))
    #expect(!source.contains("import SwiftTUIWebHostCLI"))
    #expect(!source.contains("import SwiftTUICLI"))
  }
}
