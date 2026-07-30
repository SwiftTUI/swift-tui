import Testing

@testable import SwiftTUICore

/// D71/D78: wrapping is bounded by `lineLimit`, and truncation reads the one
/// wrap that produced the visible rows.
///
/// The budget is only sound because the wrap is append-only — a row is final
/// once flushed and never revised by later content — so "stop after n rows"
/// equals "take the first n rows of the full wrap". These tests pin that
/// property directly across every regime the algorithm has: word-boundary
/// breaks, the marker-splitting path for oversized word-like tokens, and the
/// degenerate-width cluster fallback.
@Suite("Text layout row budget")
struct TextLayoutRowBudgetTests {

  private func clusters(_ text: String) -> [TextCluster] {
    text.map { TextCluster(character: $0, cellWidth: cellWidth(of: $0)) }
  }

  private func rows(
    _ text: String,
    width: Int,
    budget: Int?
  ) -> [String] {
    wrapTextLineClusters(
      clusters(text),
      width: width,
      wrappingStrategy: .wordBoundary,
      rowBudget: budget
    ).map { String($0.map(\.character)) }
  }

  // MARK: - The prefix property, across every wrap regime

  @Test(
    "a budgeted wrap equals the prefix of the unbudgeted wrap",
    arguments: [
      // Word-boundary breaks with separator whitespace dropped at wrap points.
      ("alpha beta gamma delta epsilon zeta", 7),
      // A single oversized word-like token: the marker-splitting path.
      ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", 5),
      // Mixed: short words then an oversized token, exercising the
      // flush-then-adopt handoff in `adoptWrappedLines`.
      ("ab cd ABCDEFGHIJKLMNOPQRSTUVWXYZ ef", 6),
      // Non-word-like oversized token (punctuation) takes the plain
      // cluster-append path rather than marker splitting.
      ("!!!!!!!!!!!!!!!!!!!!!!!! xy", 5),
      // Degenerate width: below 3 the marker path bails to cluster wrapping.
      ("ABCDEFGHIJ", 2),
      ("ABCDEFGHIJ", 1),
      // Leading whitespace is preserved rather than treated as a separator.
      ("    indented content here", 6),
      // A trailing separator with nothing after it (the `pendingSeparator` tail).
      ("alpha beta ", 5),
      // Wide (2-cell) clusters.
      ("漢字漢字漢字漢字漢字", 5),
    ]
  )
  func budgetedWrapIsAPrefix(text: String, width: Int) {
    let full = rows(text, width: width, budget: nil)

    for budget in 1...(full.count + 2) {
      let budgeted = rows(text, width: width, budget: budget)
      #expect(
        budgeted == Array(full.prefix(budget)),
        "width \(width) budget \(budget) over \(text.debugDescription)"
      )
    }
  }

  @Test("a budget below one still yields a row, preserving the non-empty postcondition")
  func budgetIsClampedToOneRow() {
    #expect(rows("alpha beta", width: 5, budget: 0) == ["alpha"])
    #expect(rows("alpha beta", width: 5, budget: -3) == ["alpha"])
  }

  @Test("an unbudgeted wrap is byte-identical to the pre-budget behaviour")
  func unbudgetedWrapIsUnchanged() {
    #expect(rows("alpha beta gamma", width: 5, budget: nil) == ["alpha", "beta", "gamma"])
    // Width 3 leaves 2 content cells on the first row and 1 on middle rows,
    // since each marker costs a cell.
    #expect(rows("ABCDEFG", width: 3, budget: nil) == ["AB–", "–C–", "–D–", "–E–", "–FG"])
    #expect(rows("", width: 5, budget: nil) == [""])
  }

  // MARK: - The budget actually bounds the work

  @Test("a giant unbroken token under lineLimit(1) stops after two rows")
  func giantTokenIsNotFullySplit() {
    // Before the budget this wrapped the whole token into ~5000 marker rows and
    // then threw all but the first away.
    let giant = String(repeating: "A", count: 20_000)
    let wrapped = wrapTextLineClusters(
      clusters(giant),
      width: 5,
      wrappingStrategy: .wordBoundary,
      rowBudget: 2
    )
    #expect(wrapped.count == 2)
    // And the rows are the real ones, not a degenerate stop.
    #expect(String(wrapped[0].map(\.character)) == "AAAA–")
  }

  @Test("a long document under lineLimit(1) is not wrapped past the limit")
  func longDocumentStopsAtTheLimit() {
    let document = (0..<5_000).map { "line \($0) with some content" }
      .joined(separator: "\n")
    let layout = layoutText(for: document, width: 12, lineLimit: 1)

    #expect(layout.lines.count == 1)
    #expect(layout.wasTruncated)
    #expect(layout.lines[0].text == "line 0 with…")
  }

  @Test("wasTruncated still distinguishes exactly-fitting content from overflow")
  func truncationFlagMatchesContent() {
    // Exactly `lineLimit` rows: not truncated.
    let exact = layoutText(for: "alpha\nbeta", width: 10, lineLimit: 2)
    #expect(exact.lines.map(\.text) == ["alpha", "beta"])
    #expect(!exact.wasTruncated)

    // One row past: truncated.
    let over = layoutText(for: "alpha\nbeta\ngamma", width: 10, lineLimit: 2)
    #expect(over.wasTruncated)

    // Fewer rows than the limit: not truncated, and the budget is never hit.
    let under = layoutText(for: "alpha", width: 10, lineLimit: 4)
    #expect(under.lines.map(\.text) == ["alpha"])
    #expect(!under.wasTruncated)

    // A trailing empty source line still counts as a row.
    let trailingNewline = layoutText(for: "alpha\n", width: 10, lineLimit: 1)
    #expect(trailingNewline.wasTruncated)
  }

  // MARK: - D78: the source mapping is structural

  @Test("truncating a row past the first folds back into its own logical line")
  func continuationRowFoldsIntoItsLogicalLine() {
    // This is the hazard case D78 named: `rowIndex > 0`, where the old code
    // re-wrapped the logical line through a *second* generic instantiation and
    // silently returned the known-bad wrapped fragment if the two disagreed.
    // The row now comes from the same wrap that produced the visible output.
    #expect(
      layoutText(for: "ABCDEFG", width: 3, lineLimit: 2, truncationMode: .head)
        .lines.map(\.text) == ["AB–", "…FG"]
    )
    // `.middle` keeps the row's own leading marker (it genuinely says "this
    // word started above") and then splits the logical-line remainder.
    #expect(
      layoutText(for: "ABCDEFG", width: 3, lineLimit: 2, truncationMode: .middle)
        .lines.map(\.text) == ["AB–", "–…G"]
    )
    #expect(
      layoutText(for: "alpha beta gamma", width: 5, lineLimit: 2, truncationMode: .head)
        .lines.map(\.text) == ["alpha", "…amma"]
    )
  }

  @Test(
    "head truncation of a deep continuation row still ends at the logical line's tail",
    arguments: 2...6
  )
  func deepContinuationRowsEndAtTheSourceTail(lineLimit: Int) {
    let source = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let layout = layoutText(
      for: source,
      width: 5,
      lineLimit: lineLimit,
      truncationMode: .head
    )

    guard let last = layout.lines.last, layout.wasTruncated else {
      return
    }
    // `.head` spends everything but the ellipsis on the tail of the *logical
    // line*, so the row must end with the string's own suffix and must never
    // carry a wrap continuation marker into that tail.
    #expect(last.text.hasSuffix(String(source.suffix(4))), "lineLimit \(lineLimit)")
    #expect(!last.text.dropFirst().contains("–"), "lineLimit \(lineLimit)")
  }
}
