import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

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

  @Test("Multibyte UTF-8 percent-encoded paths decode correctly")
  func multibyteUTF8() {
    // U+5199 U+771F .jpg  →  %E5%86%99%E7%9C%9F.jpg
    let paths = parseDroppedPaths("file:///Users/me/%E5%86%99%E7%9C%9F.jpg")
    #expect(paths == [DroppedPath("/Users/me/写真.jpg")])
  }

  @Test("Truncated percent sequence at end of input preserves consumed characters")
  func truncatedPercent() {
    // Bare %
    #expect(parseDroppedPaths("file:///path%") == [DroppedPath("/path%")])
    // Single hex digit after %
    #expect(parseDroppedPaths("file:///path%4") == [DroppedPath("/path%4")])
  }

  @Test("Non-hex character after percent preserves both characters literally")
  func nonHexPercent() {
    #expect(parseDroppedPaths("file:///path%2Z/foo") == [DroppedPath("/path%2Z/foo")])
  }

  @Test("Unterminated single quote accumulates remainder as one path")
  func unterminatedSingleQuote() {
    // Current behavior — lock it in so we don't regress silently.
    #expect(parseDroppedPaths("'/not/closed") == [DroppedPath("/not/closed")])
  }
}
