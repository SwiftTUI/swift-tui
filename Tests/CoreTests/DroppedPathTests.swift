import Testing

@testable import Core

@Suite
struct DroppedPathTests {
  @Test("DroppedPath preserves its raw string and compares by value")
  func rawValueAndEquality() {
    let a = DroppedPath("/Users/me/file.txt")
    let b = DroppedPath("/Users/me/file.txt")
    let c = DroppedPath("/Users/me/other.txt")
    #expect(a.rawValue == "/Users/me/file.txt")
    #expect(a == b)
    #expect(a != c)
  }

  @Test("DroppedPath is string-literal expressible for ergonomics in tests")
  func stringLiteral() {
    let path: DroppedPath = "/tmp/x"
    #expect(path.rawValue == "/tmp/x")
  }
}
