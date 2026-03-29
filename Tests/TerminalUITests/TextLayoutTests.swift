import Testing

@testable import Core

@MainActor
@Suite
struct TextLayoutTests {
  @Test("word-boundary wrapping prefers whitespace breaks and consumes separator whitespace")
  func wordBoundaryWrappingConsumesSeparatorWhitespace() {
    let layout = parallelTextLayout(
      for: "alpha beta",
      width: 5
    )

    #expect(layout.lines.map(\.text) == ["alpha", "beta"])
    #expect(layout.size == .init(width: 5, height: 2))
  }

  @Test("word-boundary wrapping preserves explicit leading whitespace")
  func wordBoundaryWrappingPreservesLeadingWhitespace() {
    let layout = parallelTextLayout(
      for: "  alpha beta",
      width: 7
    )

    #expect(layout.lines.map(\.text) == ["  alpha", "beta"])
  }

  @Test("word-boundary wrapping adds continuation markers for oversized word-like tokens")
  func wordBoundaryWrappingAddsContinuationMarkers() {
    let twoLine = parallelTextLayout(
      for: "planet",
      width: 5
    )
    let multiLine = parallelTextLayout(
      for: "abcdefgh",
      width: 4
    )

    #expect(twoLine.lines.map(\.text) == ["plan–", "–et"])
    #expect(multiLine.lines.map(\.text) == ["abc–", "–de–", "–fgh"])
  }

  @Test("narrow widths fall back to cluster wrapping without continuation markers")
  func narrowWidthsFallBackToClusterWrapping() {
    let layout = parallelTextLayout(
      for: "hello",
      width: 2
    )

    #expect(layout.lines.map(\.text) == ["he", "ll", "o"])
  }

  @Test("wide glyph runs keep cluster wrapping without continuation markers")
  func wideGlyphRunsKeepClusterWrapping() {
    let layout = parallelTextLayout(
      for: "界界界",
      width: 2
    )

    #expect(layout.lines.map(\.text) == ["界", "界", "界"])
  }

  @Test("line limits truncate after the word-boundary wrap pass")
  func lineLimitTruncatesAfterWordBoundaryWrapping() {
    let layout = parallelTextLayout(
      for: "alpha beta gamma",
      width: 5,
      lineLimit: 2
    )

    #expect(layout.lines.map(\.text) == ["alpha", "beta…"])
    #expect(layout.wasTruncated)
  }
}
