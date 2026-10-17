// Adversarial set B, pass 2: text layout (111–120).
//
// Wrapping, truncation and cell-width decisions are made per cluster in
// `TextLayout.swift`, `TextLayoutWrapping.swift`, `TextLayoutTruncation.swift`
// and `TextCellWidth.swift`, and the raster paints what layout produced. These
// probes sit on the seams between those stages: line separators that are not
// `\n`, whitespace and zero-width clusters at an exact width, truncation of a
// line that already fits, break opportunities the wrapper does not see, and
// measurement versus paint of rich text whose runs split a grapheme.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: text layout")
struct AdversarialSetBTextLayoutTests {
  private func render<V: View>(_ view: V, _ name: String, width: Int, height: Int)
    -> RenderSnapshot
  {
    DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("SetBTextLayout", name)),
      proposal: .init(width: width, height: height))
  }

  // Every Unicode line terminator breaks a line: CRLF is one grapheme, CR,
  // NEL, LS and PS are newlines by `Character.isNewline`, and none of them is
  // a glyph a terminal cell can hold.
  @Test func setB111EveryUnicodeLineTerminatorBreaksALine() {
    let separators: [(name: String, text: String)] = [
      ("CRLF", "a\r\nb"), ("CR", "a\rb"), ("NEL", "a\u{0085}b"), ("LS", "a\u{2028}b"),
      ("PS", "a\u{2029}b"),
    ]
    for separator in separators {
      do {
        let layout = layoutText(for: separator.text, width: 10)
        #expect(layout.lines.map(\.text) == ["a", "b"], "\(separator.name): \(layout.lines)")
        #expect(layout.size == CellSize(width: 1, height: 2), "\(separator.name): \(layout.size)")

        let snapshot = render(
          Text(separator.text), "setB111-\(separator.name)", width: 10, height: 3)
        #expect(
          snapshot.measuredTree.measuredSize == CellSize(width: 1, height: 2),
          "\(separator.name): \(snapshot.measuredTree.measuredSize)")
        let painted = snapshot.rasterSurface.lines.prefix(2)
        #expect(Array(painted) == ["a", "b"], "\(separator.name): \(snapshot.rasterSurface.lines)")
        let controls = snapshot.rasterSurface.cells.flatMap { $0 }.filter { cell in
          cell.character.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x85 }
        }
        #expect(controls.isEmpty, "\(separator.name) painted a control scalar: \(controls)")
      }
    }
  }

  // Trailing whitespace hangs off the end of a line: "alpha " at width 5 is
  // one row, and with `lineLimit(1)` it is not truncated.
  @Test func setB112TrailingWhitespaceAtExactWidthDoesNotSpawnARow() {
    let wrapped = layoutText(for: "alpha ", width: 5)
    #expect(wrapped.lines.first?.text.trimmingTrailingSpaces == "alpha", "\(wrapped.lines)")
    do {
      #expect(wrapped.lines.count == 1, "\(wrapped.lines.map(\.text))")

      let limited = layoutText(for: "alpha ", width: 5, lineLimit: 1)
      #expect(limited.lines.first?.text == "alpha", "\(limited.lines.map(\.text))")
      #expect(!limited.wasTruncated)

      let snapshot = render(Text("alpha "), "setB112", width: 5, height: 3)
      #expect(
        snapshot.measuredTree.measuredSize.height == 1, "\(snapshot.measuredTree.measuredSize)")
      #expect(snapshot.rasterSurface.lines.first == "alpha", "\(snapshot.rasterSurface.lines)")
      #expect(snapshot.rasterSurface.lines.dropFirst().allSatisfy { $0.isEmpty })
    }

    let twoWords = layoutText(for: "alpha beta ", width: 5)
    #expect(twoWords.lines.count == 2, "\(twoWords.lines.map(\.text))")
  }

  // An ellipsis replaces content. Middle truncation of a two-line string under
  // `lineLimit(1)` never repeats the leading clusters on both sides of it.
  @Test func setB113MiddleTruncationNeverDuplicatesAFittingLine() {
    let layout = layoutText(for: "ab\ncd", width: 10, lineLimit: 1, truncationMode: .middle)
    let text = layout.lines.first?.text ?? ""
    #expect(layout.lines.count == 1, "\(layout.lines.map(\.text))")
    #expect(text.hasPrefix("ab"), "\(text)")
    #expect(text.count <= 5, "\(text)")
    let snapshot = render(
      Text("ab\ncd").lineLimit(1).truncationMode(.middle), "setB113", width: 10, height: 1)
    let line = snapshot.rasterSurface.lines.first ?? ""
    do {
      #expect(text.filter { $0 == "a" }.count == 1, "\(text)")
      #expect(text.filter { $0 == "b" }.count <= 1, "\(text)")
      #expect(!line.contains("ab…ab"), "\(snapshot.rasterSurface.lines)")
      #expect(line.filter { $0 == "a" }.count == 1, "\(line)")
    }

    // The same line under tail and head truncation keeps its characters once.
    for mode in [TextTruncationMode.tail, .head] {
      let other = layoutText(for: "ab\ncd", width: 10, lineLimit: 1, truncationMode: mode)
      let otherText = other.lines.first?.text ?? ""
      #expect(otherText.filter { $0 == "a" }.count <= 1, "\(mode): \(otherText)")
      #expect(otherText.filter { $0 == "d" }.count <= 1, "\(mode): \(otherText)")
    }
  }

  // No-break spaces are glue: the wrapper may not break at them and may never
  // drop them as separators.
  @Test func setB114NoBreakSpacesAreNeitherBreakOpportunitiesNorDroppable() {
    for (name, glue) in [("NBSP", "\u{00A0}"), ("NNBSP", "\u{202F}"), ("FIGURE", "\u{2007}")] {
      let text = "a\(glue)b"
      let narrow = layoutText(for: text, width: 2)
      let joined = narrow.lines.map(\.text).joined()
      let snapshot = render(Text(text), "setB114-\(name)", width: 2, height: 3)
      let cells = snapshot.rasterSurface.cells.flatMap { $0 }.map(\.character)
      #expect(
        cells.contains("a") && cells.contains("b"), "\(name): \(snapshot.rasterSurface.lines)")
      do {
        #expect(
          joined.unicodeScalars.contains(glue.unicodeScalars.first!),
          "\(name) was dropped: \(narrow.lines.map(\.text))")
        #expect(
          narrow.lines.first?.text != "a", "\(name) was a break opportunity: \(narrow.lines)")
        #expect(cells.contains(Character(glue)), "\(name) never reached the raster: \(cells)")
      }

      // Inside a line that fits, the glue survives and the ordinary space still breaks.
      let wide = layoutText(for: "aa\(glue)bb cc", width: 5)
      #expect(wide.lines.first?.text == "aa\(glue)bb", "\(name): \(wide.lines.map(\.text))")
      #expect(wide.lines.count == 2, "\(name): \(wide.lines.map(\.text))")
    }
  }

  // A hyphen or dash is a break opportunity: "well-known" breaks after the
  // hyphen, never inside "known".
  @Test func setB115HyphensAndDashesAreBreakOpportunities() {
    do {
      let hyphen = layoutText(for: "well-known", width: 7)
      #expect(hyphen.lines.map(\.text) == ["well-", "known"], "\(hyphen.lines.map(\.text))")

      let emDash = layoutText(for: "foo\u{2014}bar", width: 5)
      #expect(
        emDash.lines.map(\.text) == ["foo\u{2014}", "bar"], "\(emDash.lines.map(\.text))")

      let sentence = layoutText(for: "a well-known fact", width: 9)
      #expect(
        sentence.lines.map(\.text) == ["a well-", "known", "fact"]
          || sentence.lines.map(\.text) == ["a well-", "known fact"],
        "\(sentence.lines.map(\.text))")

      let snapshot = render(Text("well-known"), "setB115", width: 7, height: 3)
      #expect(
        snapshot.rasterSurface.lines.prefix(2) == ["well-", "known"],
        "\(snapshot.rasterSurface.lines)")
    }
  }

  // A zero-width character never occupies a cell and never opens a row, even
  // when it is the last cluster of a line that exactly fills the width.
  @Test func setB116TrailingZeroWidthCharactersTakeNoCellAndNoRow() {
    // (A ZWNJ or ZWJ attaches to the preceding grapheme and is not a cluster
    // of its own, so only the standalone format characters are probed.)
    for (name, invisible) in [("ZWSP", "\u{200B}"), ("SHY", "\u{00AD}"), ("WJ", "\u{2060}")] {
      let exact = layoutText(for: "ab\(invisible)", width: 2)
      #expect(exact.lines.count == 1, "\(name): \(exact.lines.map(\.text))")
      #expect(exact.size.height == 1, "\(name): \(exact.size)")

      let snapshot = render(Text("a\(invisible)"), "setB116-\(name)", width: 3, height: 1)
      #expect(
        snapshot.measuredTree.measuredSize.width == 1,
        "\(name): \(snapshot.measuredTree.measuredSize)")
      #expect(snapshot.rasterSurface.lines == ["a"], "\(name): \(snapshot.rasterSurface.lines)")
      let second = snapshot.rasterSurface.cells[0][1]
      #expect(second.character == " " || second.character == "\0", "\(name): \(second)")
      let occupied = snapshot.rasterSurface.cells[0].filter {
        $0.character.unicodeScalars.contains(invisible.unicodeScalars.first!)
      }
      #expect(occupied.isEmpty, "\(name) occupies a cell: \(occupied)")
    }
  }

  // A digit, `#`, `*` or `©` with a combining mark is one narrow glyph. The
  // emoji property of the base scalar does not make the cluster wide.
  @Test func setB117CombiningMarksOnEmojiPropertyASCIIStayNarrow() {
    let narrow: [(name: String, cluster: Character)] = [
      ("1+acute", "1\u{0301}"), ("#+acute", "#\u{0301}"), ("*+ring", "*\u{030A}"),
      ("©+acute", "©\u{0301}"), ("digit+VS15", "1\u{FE0E}"),
    ]
    for entry in narrow {
      let snapshot = render(
        Text(String(entry.cluster)), "setB117-\(entry.name)", width: 4, height: 1)
      // A digit with a text-presentation selector is narrow everywhere.
      do {
        #expect(
          cellWidth(of: entry.cluster) == 1, "\(entry.name): \(cellWidth(of: entry.cluster))")
        #expect(
          snapshot.measuredTree.measuredSize.width == 1,
          "\(entry.name): \(snapshot.measuredTree.measuredSize)")
        #expect(snapshot.rasterSurface.cells[0][0].spanWidth == 1, "\(entry.name)")
        #expect(snapshot.rasterSurface.cells[0][1].continuationLeadX == nil, "\(entry.name)")
      }
    }
    // The genuinely wide forms stay wide: keycap and emoji presentation.
    #expect(cellWidth(of: "1\u{FE0F}\u{20E3}") == 2)
    #expect(cellWidth(of: "#\u{FE0F}\u{20E3}") == 2)
    #expect(cellWidth(of: "©\u{FE0F}") == 2)
  }

  // A line limit just below Int.max must behave like an unbounded limit, not
  // overflow the per-token row budget.
  @Test func setB118NearMaximumLineLimitsDoNotTrap() async {
    do {
      await #expect(processExitsWith: .success) {
        let layout = layoutText(for: "abcdefghij", width: 4, lineLimit: Int.max - 1)
        #expect(layout.lines == layoutText(for: "abcdefghij", width: 4).lines)
        #expect(!layout.wasTruncated)
      }
    }
    await #expect(processExitsWith: .success) {
      let layout = layoutText(for: "abcdefghij klmnop", width: 4, lineLimit: Int.max / 2 + 1)
      #expect(layout.lines.count >= 4, "\(layout.lines.map(\.text))")
    }
    let unbounded = layoutText(for: "abcdefghij", width: 4, lineLimit: nil)
    let huge = layoutText(for: "abcdefghij", width: 4, lineLimit: 1_000_000)
    #expect(unbounded.lines.map(\.text) == huge.lines.map(\.text))
  }

  // Rich text is measured and painted from the same clusters: a grapheme whose
  // scalars straddle an interpolation boundary cannot measure narrower than it
  // paints, and no glyph is dropped at the bounds.
  @Test func setB119RichTextMeasurementAndPaintAgreeAcrossRunBoundaries() {
    let plain = layoutText(for: "🇺🇸", width: nil)
    let rich = layoutRichText(
      for: RichTextPayload(runs: [
        .init(text: "🇺"), .init(text: "🇸", style: .init(emphasis: .bold)),
      ]),
      options: .init(width: nil))
    let snapshot = render(Text("🇺\(Text("🇸").bold())"), "setB119-flag", width: 10, height: 1)
    let painted = snapshot.rasterSurface.lines.first ?? ""
    let scalars = Set(painted.unicodeScalars.map(\.value))
    let paintedWidth = snapshot.rasterSurface.cells[0].filter { $0.character != " " }.count
    #expect(
      snapshot.measuredTree.measuredSize.width >= paintedWidth,
      "measured \(snapshot.measuredTree.measuredSize) painted \(paintedWidth)")
    let accent = render(Text("e\(Text("\u{0301}").bold())"), "setB119-accent", width: 10, height: 1)
    let accentLine = accent.rasterSurface.lines.first ?? ""
    #expect(accent.measuredTree.measuredSize.width <= 2, "\(accent.measuredTree.measuredSize)")
    do {
      #expect(plain.size.width == rich.size.width, "plain \(plain.size) rich \(rich.size)")
      #expect(scalars.contains(0x1F1FA) && scalars.contains(0x1F1F8), "\(painted)")
      #expect(accentLine.unicodeScalars.contains("\u{0301}"), "\(accentLine)")
    }
  }

  // A wide glyph offered one column cannot report two: under a line limit the
  // one-column truncation is the ellipsis, and the measured width never
  // exceeds the proposal when the text cannot fit at all.
  @Test func setB120WideGlyphInOneColumnTruncatesInsteadOfOverflowing() {
    let unlimited = layoutText(for: "漢", width: 1)
    let limited = layoutText(for: "漢", width: 1, lineLimit: 1)
    let snapshot = render(Text("漢").lineLimit(1), "setB120", width: 1, height: 1)
    do {
      #expect(unlimited.size.width <= 1, "\(unlimited.size)")
      #expect(limited.lines.first?.text == "…", "\(limited.lines.map(\.text))")
      #expect(limited.wasTruncated)
      #expect(limited.size.width == 1, "\(limited.size)")
      #expect(
        snapshot.measuredTree.measuredSize.width <= 1, "\(snapshot.measuredTree.measuredSize)")
      #expect(snapshot.rasterSurface.lines == ["…"], "\(snapshot.rasterSurface.lines)")
    }

    // A narrow glyph in the same proposal is simply painted.
    let narrow = render(Text("x").lineLimit(1), "setB120-narrow", width: 1, height: 1)
    #expect(narrow.rasterSurface.lines == ["x"], "\(narrow.rasterSurface.lines)")
  }
}

extension String {
  fileprivate var trimmingTrailingSpaces: String {
    var text = self
    while text.last == " " { text.removeLast() }
    return text
  }
}
