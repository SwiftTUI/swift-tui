import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Suite("Typed environment reuse classification")
struct EnvironmentKeyClassificationTests {
  @Test("classification follows explicit ownership and certification, not names")
  func typedOwnership() {
    #expect(!EnvironmentKeyReuseClassification.isReaderAttributedOnly(Uncertified.self))
    #expect(EnvironmentKeyReuseClassification.isReaderAttributedOnly(Certified.self))
    #expect(EnvironmentKeyReuseClassification.isReaderAttributedOnly(ButtonStyleKey.self))
    #expect(EnvironmentKeyReuseClassification.isReaderAttributedOnly(UserKey.self))
    // Repeat to cover the cached verdict as well as initial classification.
    #expect(!EnvironmentKeyReuseClassification.isReaderAttributedOnly(Uncertified.self))
  }

  @Test("every production environment key declares its framework ownership")
  func productionKeyOwnershipIsTotal() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let enumerator = try #require(
      FileManager.default.enumerator(
        at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil))
    let declaration = try NSRegularExpression(
      pattern: #"\b(?:enum|struct|class)\s+\w+\s*:\s*([^{}]+)\{"#)
    var count = 0
    for case let file as URL in enumerator where file.pathExtension == "swift" {
      let source = try String(contentsOf: file, encoding: .utf8)
      for match in declaration.matches(in: source, range: NSRange(source.startIndex..., in: source))
      {
        let range = try #require(Range(match.range(at: 1), in: source))
        let inherited = String(source[range])
        guard inherited.range(of: #"\bEnvironmentKey\b"#, options: .regularExpression) != nil else {
          continue
        }
        count += 1
        #expect(
          inherited.contains("FrameworkEnvironmentKey"),
          "Unclassified key in \(file.path): \(inherited)")
      }
    }
    #expect(count >= 73)
  }
}

private enum Uncertified: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = 0
}
private enum Certified: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = 0
}
private enum ButtonStyleKey: EnvironmentKey {
  static let defaultValue = 0
}
private enum UserKey: EnvironmentKey {
  static let defaultValue = 0
}
