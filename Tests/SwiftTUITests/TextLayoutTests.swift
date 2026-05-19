import Testing

@testable import SwiftTUICore

@MainActor
@Suite
struct TextLayoutTests {
  @Test("word-boundary wrapping prefers whitespace breaks and consumes separator whitespace")
  func wordBoundaryWrappingConsumesSeparatorWhitespace() {
    let layout = layoutText(
      for: "alpha beta",
      width: 5
    )

    #expect(layout.lines.map(\.text) == ["alpha", "beta"])
    #expect(layout.size == .init(width: 5, height: 2))
  }

  @Test("word-boundary wrapping preserves explicit leading whitespace")
  func wordBoundaryWrappingPreservesLeadingWhitespace() {
    let layout = layoutText(
      for: "  alpha beta",
      width: 7
    )

    #expect(layout.lines.map(\.text) == ["  alpha", "beta"])
  }

  @Test("empty and unbounded text keep their single-line layout shape")
  func guardPathLayoutsKeepSingleLineShape() {
    let unbounded = layoutText(
      for: "alpha beta",
      width: nil
    )
    let zeroWidth = layoutText(
      for: "alpha beta",
      width: 0
    )
    let empty = layoutText(
      for: "",
      width: 5
    )

    #expect(unbounded.lines.map(\.text) == ["alpha beta"])
    #expect(zeroWidth.lines.map(\.text) == [""])
    #expect(empty.lines.map(\.text) == [""])
  }

  @Test("word-boundary wrapping adds continuation markers for oversized word-like tokens")
  func wordBoundaryWrappingAddsContinuationMarkers() {
    let twoLine = layoutText(
      for: "planet",
      width: 5
    )
    let multiLine = layoutText(
      for: "abcdefgh",
      width: 4
    )

    #expect(twoLine.lines.map(\.text) == ["plan–", "–et"])
    #expect(multiLine.lines.map(\.text) == ["abc–", "–de–", "–fgh"])
  }

  @Test("narrow widths fall back to cluster wrapping without continuation markers")
  func narrowWidthsFallBackToClusterWrapping() {
    let layout = layoutText(
      for: "hello",
      width: 2
    )

    #expect(layout.lines.map(\.text) == ["he", "ll", "o"])
  }

  @Test("wide glyph runs keep cluster wrapping without continuation markers")
  func wideGlyphRunsKeepClusterWrapping() {
    let layout = layoutText(
      for: "界界界",
      width: 2
    )

    #expect(layout.lines.map(\.text) == ["界", "界", "界"])
  }

  @Test("wide word-like runs wrap by cell width when continuation markers are used")
  func wideWordLikeRunsWrapByCellWidth() {
    let lines = wrapWordLikeClustersForTesting(
      [
        .init(character: "界", cellWidth: 2),
        .init(character: "界", cellWidth: 2),
        .init(character: "界", cellWidth: 2),
        .init(character: "界", cellWidth: 2),
        .init(character: "界", cellWidth: 2),
      ],
      width: 8
    )

    #expect(lines.map(\.text) == ["界界界–", "–界界"])
    #expect(lines.map(\.cellWidth) == [7, 5])
  }

  @Test("variation selector 16 keeps emoji presentation wide")
  func variationSelector16KeepsEmojiPresentationWide() {
    let layout = layoutText(
      for: "1️⃣2",
      width: 2
    )

    #expect(layout.lines.map(\.text) == ["1️⃣", "2"])
    #expect(layout.size == .init(width: 2, height: 2))
  }

  @Test("line limits truncate after the word-boundary wrap pass")
  func lineLimitTruncatesAfterWordBoundaryWrapping() {
    let layout = layoutText(
      for: "alpha beta gamma",
      width: 5,
      lineLimit: 2
    )

    #expect(layout.lines.map(\.text) == ["alpha", "beta…"])
    #expect(layout.wasTruncated)
  }
}
