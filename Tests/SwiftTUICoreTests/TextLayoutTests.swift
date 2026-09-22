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

  // MARK: - Truncation reads the logical line, not the wrapped fragment

  @Test("head and middle truncation show the source's tail")
  func headAndMiddleTruncationShowTheSourceTail() {
    // docs/reports/2026-07-27-001: truncation used to be applied to the first
    // *wrapped* row, so `.head`/`.middle` sliced their "trailing" segment out of
    // the head of the string and carried the wrap continuation marker with it.
    let source = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    func rendered(_ mode: TextTruncationMode, width: Int) -> String {
      layoutText(for: source, width: width, lineLimit: 1, truncationMode: mode)
        .lines[0].text
    }

    #expect(rendered(.tail, width: 20) == "ABCDEFGHIJKLMNOPQRS…")
    #expect(rendered(.middle, width: 20) == "ABCDEFGHI…0123456789")
    #expect(rendered(.head, width: 20) == "…RSTUVWXYZ0123456789")
  }

  @Test("head and middle truncation end at the source's tail across widths")
  func headAndMiddleTruncationEndAtSourceTailAcrossWidths() {
    // Expressed as a semantic invariant rather than as fixed output: whatever
    // the split, the trailing segment must come from the end of the string and
    // must never contain a wrap continuation marker.
    let source = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    for width in 2...35 {
      let head = layoutText(
        for: source, width: width, lineLimit: 1, truncationMode: .head
      ).lines[0]
      let middle = layoutText(
        for: source, width: width, lineLimit: 1, truncationMode: .middle
      ).lines[0]

      // Every cluster is one cell wide, so the trailing budget is a plain
      // character count: `.head` spends everything but the ellipsis on the
      // tail, `.middle` spends the larger half of what is left.
      let headTail = width - 1
      let middleTail = headTail - headTail / 2

      #expect(head.text.hasSuffix(String(source.suffix(headTail))), "head at width \(width)")
      #expect(middle.text.hasSuffix(String(source.suffix(middleTail))), "middle at width \(width)")
      #expect(!head.text.contains("–"), "head at width \(width)")
      #expect(!middle.text.contains("–"), "middle at width \(width)")
      #expect(head.cellWidth <= width)
      #expect(middle.cellWidth <= width)
    }
  }

  @Test("multi-line truncation stays inside the logical line it is truncating")
  func multiLineTruncationStaysInsideItsOwnLogicalLine() {
    // The last *visible* row is folded back into the remainder of its own
    // source line — not the whole document, or line 2 here would end in
    // "delta".
    let layout = layoutText(
      for: "alpha beta gamma\ndelta",
      width: 5,
      lineLimit: 2,
      truncationMode: .head
    )

    #expect(layout.lines.map(\.text) == ["alpha", "…amma"])
    #expect(layout.wasTruncated)
  }

  @Test("tail truncation fills the width past a word boundary")
  func tailTruncationFillsTheWidthPastAWordBoundary() {
    // The one `.tail` shape the logical-remainder fix changes. Wrapping breaks
    // after "ab" because "cdefghijkl" cannot fit, so the wrapped row was two
    // cells wide and truncating it produced "ab…" — four cells of the pane left
    // blank. Truncation is character-level on the last visible line (as it is
    // in SwiftUI), so the remainder fills the width.
    let layout = layoutText(for: "ab cdefghijkl", width: 6, lineLimit: 1)

    #expect(layout.lines.map(\.text) == ["ab cd…"])
    #expect(layout.lines[0].cellWidth == 6)
  }

  @Test("truncating a continuation row keeps its leading wrap marker")
  func truncatingContinuationRowKeepsLeadingWrapMarker() {
    // A row that begins mid-word owns its leading "–": it says the word started
    // on the row above. The trailing "–" is a promise of a row that truncation
    // is about to remove, so it must not survive.
    let tail = layoutText(for: "ABCDEFG", width: 3, lineLimit: 2)
    let head = layoutText(for: "ABCDEFG", width: 3, lineLimit: 2, truncationMode: .head)

    #expect(tail.lines.map(\.text) == ["AB–", "–C…"])
    #expect(head.lines.map(\.text) == ["AB–", "…FG"])
  }
}
