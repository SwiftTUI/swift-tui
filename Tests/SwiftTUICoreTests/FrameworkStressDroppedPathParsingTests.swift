import Testing

@testable import SwiftTUIGraph

@Suite("Dropped-path parser stress behavior", .serialized)
struct FrameworkStressDroppedPathParsingTests {
  @Test("stress dropped path parsing 001 tilde-rooted paths survive intake")
  func droppedPathParsing001TildeRootedPathsSurviveIntake() {
    #expect(parseDroppedPaths("~/Desktop/report.txt") == [DroppedPath("~/Desktop/report.txt")])
  }

  @Test("stress dropped path parsing 002 escaped leading tilde remains path-shaped")
  func droppedPathParsing002EscapedLeadingTildeRemainsPathShaped() {
    #expect(parseDroppedPaths(#"\~/Desktop/report.txt"#) == [DroppedPath("~/Desktop/report.txt")])
  }

  @Test("stress dropped path parsing 003 tabs delimit adjacent absolute paths")
  func droppedPathParsing003TabsDelimitAdjacentAbsolutePaths() {
    #expect(parseDroppedPaths("/tmp/first\t/tmp/second") == ["/tmp/first", "/tmp/second"])
  }

  @Test("stress dropped path parsing 004 newlines preserve path ordering")
  func droppedPathParsing004NewlinesPreservePathOrdering() {
    #expect(parseDroppedPaths("/tmp/first\n/tmp/second") == ["/tmp/first", "/tmp/second"])
  }

  @Test("stress dropped path parsing 005 carriage returns preserve path ordering")
  func droppedPathParsing005CarriageReturnsPreservePathOrdering() {
    #expect(parseDroppedPaths("/tmp/first\r/tmp/second") == ["/tmp/first", "/tmp/second"])
  }

  @Test("stress dropped path parsing 006 repeated separators never synthesize empty paths")
  func droppedPathParsing006RepeatedSeparatorsNeverSynthesizeEmptyPaths() {
    #expect(parseDroppedPaths("  \t/tmp/only\n\r  ") == [DroppedPath("/tmp/only")])
  }

  @Test("stress dropped path parsing 007 prose surrounding a path is filtered independently")
  func droppedPathParsing007ProseSurroundingPathIsFilteredIndependently() {
    #expect(parseDroppedPaths("before /tmp/kept after") == [DroppedPath("/tmp/kept")])
  }

  @Test("stress dropped path parsing 008 quoted relative content retains terminal intent")
  func droppedPathParsing008QuotedRelativeContentRetainsTerminalIntent() {
    #expect(parseDroppedPaths("'relative file.txt'") == [DroppedPath("relative file.txt")])
  }

  @Test("stress dropped path parsing 009 empty quotes do not create an empty drop")
  func droppedPathParsing009EmptyQuotesDoNotCreateAnEmptyDrop() {
    #expect(parseDroppedPaths("''") == [])
  }

  @Test("stress dropped path parsing 010 quoted path component can adjoin an absolute prefix")
  func droppedPathParsing010QuotedPathComponentCanAdjoinAnAbsolutePrefix() {
    #expect(parseDroppedPaths("/tmp/'two words'.txt") == [DroppedPath("/tmp/two words.txt")])
  }

  @Test("stress dropped path parsing 011 quoted prefix can adjoin an unquoted suffix")
  func droppedPathParsing011QuotedPrefixCanAdjoinAnUnquotedSuffix() {
    #expect(parseDroppedPaths("'/tmp/two words'.txt") == [DroppedPath("/tmp/two words.txt")])
  }

  @Test("stress dropped path parsing 012 escaped tab remains inside one path")
  func droppedPathParsing012EscapedTabRemainsInsideOnePath() {
    #expect(parseDroppedPaths("/tmp/left\\\tright") == [DroppedPath("/tmp/left\tright")])
  }

  @Test("stress dropped path parsing 013 terminal backslash cannot erase the path token")
  func droppedPathParsing013TerminalBackslashCannotEraseThePathToken() {
    #expect(parseDroppedPaths("/tmp/trailing\\") == [DroppedPath("/tmp/trailing")])
  }

  @Test("stress dropped path parsing 014 escaped apostrophe does not open quote mode")
  func droppedPathParsing014EscapedApostropheDoesNotOpenQuoteMode() {
    #expect(parseDroppedPaths(#"/tmp/it\'s.txt"#) == [DroppedPath("/tmp/it's.txt")])
  }

  @Test("stress dropped path parsing 015 encoded slash becomes a path separator")
  func droppedPathParsing015EncodedSlashBecomesPathSeparator() {
    #expect(parseDroppedPaths("file:///tmp/one%2Ftwo") == [DroppedPath("/tmp/one/two")])
  }

  @Test("stress dropped path parsing 016 encoded whitespace stays inside its URL token")
  func droppedPathParsing016EncodedWhitespaceStaysInsideItsURLToken() {
    #expect(parseDroppedPaths("file:///tmp/one%20two") == [DroppedPath("/tmp/one two")])
  }

  @Test("stress dropped path parsing 017 encoded percent does not begin a second decode")
  func droppedPathParsing017EncodedPercentDoesNotBeginASecondDecode() {
    #expect(parseDroppedPaths("file:///tmp/100%2520real") == [DroppedPath("/tmp/100%20real")])
  }

  @Test("stress dropped path parsing 018 lowercase UTF-8 escapes decode losslessly")
  func droppedPathParsing018LowercaseUTF8EscapesDecodeLosslessly() {
    #expect(parseDroppedPaths("file:///tmp/%e2%82%ac.txt") == [DroppedPath("/tmp/€.txt")])
  }

  @Test("stress dropped path parsing 019 literal and encoded Unicode can share a token")
  func droppedPathParsing019LiteralAndEncodedUnicodeCanShareAToken() {
    #expect(parseDroppedPaths("file:///tmp/雪-%E2%98%83.txt") == [DroppedPath("/tmp/雪-☃.txt")])
  }

  @Test("stress dropped path parsing 020 encoded NUL remains data instead of truncating")
  func droppedPathParsing020EncodedNULRemainsDataInsteadOfTruncating() {
    #expect(parseDroppedPaths("file:///tmp/a%00b") == [DroppedPath("/tmp/a\0b")])
  }

  @Test("stress dropped path parsing 021 invalid byte after valid UTF-8 preserves valid prefix")
  func droppedPathParsing021InvalidByteAfterValidUTF8PreservesValidPrefix() {
    withKnownIssue(
      "Percent decoding falls back to Latin-1 for the whole byte run after one invalid byte"
    ) {
      #expect(parseDroppedPaths("file:///tmp/%E2%82%AC%FF") == [DroppedPath("/tmp/€ÿ")])
    }
  }

  @Test("stress dropped path parsing 022 invalid byte before valid UTF-8 preserves valid suffix")
  func droppedPathParsing022InvalidByteBeforeValidUTF8PreservesValidSuffix() {
    withKnownIssue(
      "Percent decoding falls back to Latin-1 for the whole byte run before valid UTF-8"
    ) {
      #expect(parseDroppedPaths("file:///tmp/%FF%E2%82%AC") == [DroppedPath("/tmp/ÿ€")])
    }
  }

  @Test("stress dropped path parsing 023 malformed escape does not poison a later valid escape")
  func droppedPathParsing023MalformedEscapeDoesNotPoisonALaterValidEscape() {
    #expect(parseDroppedPaths("file:///tmp/%2Z%20tail") == [DroppedPath("/tmp/%2Z tail")])
  }

  @Test("stress dropped path parsing 024 encoded leading slash still qualifies as a path")
  func droppedPathParsing024EncodedLeadingSlashStillQualifiesAsAPath() {
    #expect(parseDroppedPaths("file://%2Ftmp%2Fencoded") == [DroppedPath("/tmp/encoded")])
  }

  @Test("stress dropped path parsing 025 multiple file URLs retain source order")
  func droppedPathParsing025MultipleFileURLsRetainSourceOrder() {
    #expect(
      parseDroppedPaths("file:///tmp/one%201 file:///tmp/two%202")
        == [DroppedPath("/tmp/one 1"), DroppedPath("/tmp/two 2")]
    )
  }
}
