import Testing

@testable import Core

@Suite
struct DroppedPathParsingTests {
  @Test("Backslash-escaped spaces are unescaped")
  func backslashEscape() {
    let paths = parseDroppedPaths(#"/Users/me/my\ file.png"#)
    #expect(paths == [DroppedPath("/Users/me/my file.png")])
  }

  @Test("Single-quoted segments preserve spaces and are unwrapped")
  func singleQuoted() {
    let paths = parseDroppedPaths("'/Users/me/my file.png'")
    #expect(paths == [DroppedPath("/Users/me/my file.png")])
  }

  @Test("Multiple unquoted paths separated by whitespace parse in order")
  func multiUnquoted() {
    let paths = parseDroppedPaths("/a /b/c /d")
    #expect(
      paths == [
        DroppedPath("/a"),
        DroppedPath("/b/c"),
        DroppedPath("/d"),
      ]
    )
  }

  @Test("Mixed quoted and backslash-escaped paths keep relative order")
  func mixed() {
    let paths = parseDroppedPaths(#"'/one file' /two\ file"#)
    #expect(
      paths == [
        DroppedPath("/one file"),
        DroppedPath("/two file"),
      ]
    )
  }

  @Test("file:// URLs are decoded to POSIX paths")
  func fileURL() {
    let paths = parseDroppedPaths("file:///Users/me/my%20photo.png")
    #expect(paths == [DroppedPath("/Users/me/my photo.png")])
  }

  @Test("Empty input returns no paths")
  func empty() {
    #expect(parseDroppedPaths("").isEmpty)
    #expect(parseDroppedPaths("   ").isEmpty)
  }
}
