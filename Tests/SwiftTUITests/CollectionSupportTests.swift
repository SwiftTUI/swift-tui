import Testing

@_spi(Testing) @testable import Core
@testable import View

@MainActor
@Suite
struct CollectionSupportTests {
  @Test("picker selection helpers support exact and optional matches")
  func pickerSelectionHelpersSupportExactAndOptionalMatches() {
    let tag = SelectionTag(value: 3, includeOptional: true)

    #expect(pickerSelectionMatches(tag, selection: 3))
    #expect(!pickerSelectionMatches(tag, selection: 4))
    #expect(pickerSelectionMatches(tag, selection: Optional<Int>.some(3)))
    #expect(!pickerSelectionMatches(tag, selection: Optional<Int>.none))
    #expect(pickerSelectionValue(from: tag, as: Int.self) == 3)
    #expect(pickerSelectionValue(from: tag, as: Optional<Int>.self) == .some(3))

    let nonOptionalTag = SelectionTag(value: 3, includeOptional: false)
    #expect(pickerSelectionMatches(nonOptionalTag, selection: Optional<Int>.some(3)))
    #expect(pickerSelectionValue(from: nonOptionalTag, as: Optional<Int>.self) == .some(3))
    #expect(!pickerSelectionMatches(nonOptionalTag, selection: Optional<Int>.none))
  }

  @Test("table formatting helpers honor width and alignment")
  func tableFormattingHelpersHonorWidthAndAlignment() {
    let columns = [
      TableColumn("Name", width: 6, alignment: .leading),
      TableColumn("Score", width: 5, alignment: .trailing, titleAlignment: .center),
    ]

    let row = formattedTableLine(
      cells: ["Ada", "42"],
      widths: [6, 5],
      columns: columns
    )
    let header = formattedTableLine(
      cells: ["Name", "Score"],
      widths: [6, 5],
      columns: columns,
      usesTitleAlignment: true
    )

    #expect(row == "Ada    |    42")
    #expect(header == "Name   | Score")
    #expect(paddedTableCell("toolong", width: 4, alignment: .leading) == "too…")
  }

  @Test("collection text extraction flattens nested text nodes")
  func collectionTextExtractionFlattensNestedTextNodes() {
    let node = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .view("Group"),
      children: [
        .init(
          identity: testIdentity("Root", "0"),
          kind: .view("Text"),
          drawPayload: .text("Alpha")
        ),
        .init(
          identity: testIdentity("Root", "1"),
          kind: .view("Group"),
          children: [
            .init(
              identity: testIdentity("Root", "1", "0"),
              kind: .view("Text"),
              drawPayload: .text("Beta")
            )
          ]
        ),
      ]
    )

    #expect(resolvedNodeLabelText(from: node) == "Alpha Beta")
    #expect(
      tableRowCells(
        from: ResolvedNode(
          identity: testIdentity("Row"),
          kind: .view("TableRow"),
          children: [
            .init(identity: testIdentity("Row", "0"), kind: .view("Text"), drawPayload: .text("A")),
            .init(identity: testIdentity("Row", "1"), kind: .view("Text"), drawPayload: .text("B")),
          ]
        )
      ) == ["A", "B"]
    )
  }

  @Test("collection text extraction flattens rich text payloads to visible text")
  func collectionTextExtractionFlattensRichTextPayloads() {
    let richPayload = RichTextPayload(
      runs: [
        .init(text: "Alpha "),
        .init(
          text: "Docs",
          destination: "https://example.com",
          linkIdentifier: "InlineLink[0]"
        ),
      ]
    )
    let node = ResolvedNode(
      identity: testIdentity("RichRow"),
      kind: .view("Group"),
      children: [
        .init(
          identity: testIdentity("RichRow", "0"),
          kind: .view("Text"),
          drawPayload: .richText(richPayload)
        ),
        .init(
          identity: testIdentity("RichRow", "1"),
          kind: .view("Text"),
          drawPayload: .text("Beta")
        ),
      ]
    )

    #expect(resolvedNodeLabelText(from: node) == "Alpha Docs Beta")
  }

  @Test("collection text extraction uses TextFigure source text instead of banner output")
  func collectionTextExtractionUsesTextFigureSourceText() {
    let node = ResolvedNode(
      identity: testIdentity("FigureRow"),
      kind: .view("Group"),
      children: [
        .init(
          identity: testIdentity("FigureRow", "0"),
          kind: .view("TextFigure"),
          drawPayload: .textFigure(
            .init(
              content: "Alpha",
              font: embeddedTextFigureFont(named: "standard")
            )
          )
        ),
        .init(
          identity: testIdentity("FigureRow", "1"),
          kind: .view("Text"),
          drawPayload: .text("Beta")
        ),
      ]
    )

    #expect(resolvedNodeLabelText(from: node) == "Alpha Beta")
  }

  private func embeddedTextFigureFont(named name: String) -> TextFigureFont {
    guard let font = TextFigure.availableFonts.first(where: { $0.rawValue == name }) else {
      fatalError("Missing embedded TextFigure font \(name)")
    }
    return font
  }

  @Test("table row cell payloads preserve per-cell text and merged row styling")
  func tableRowCellPayloadsPreserveMergedCellStyling() {
    let row = ResolvedNode(
      identity: testIdentity("Row"),
      kind: .view("TableRow"),
      children: [
        .init(
          identity: testIdentity("Row", "0"),
          kind: .view("Text"),
          drawMetadata: .init(foregroundStyle: .color(Color.yellow)),
          drawPayload: .text("Alpha")
        ),
        .init(
          identity: testIdentity("Row", "1"),
          kind: .view("Text"),
          drawPayload: .text("Beta")
        ),
      ],
      drawMetadata: .init(emphasis: .bold)
    )

    let cells = tableRowCellPayloads(from: row)

    #expect(cells.map(\.text) == ["Alpha", "Beta"])
    #expect(cells[0].style.foregroundStyle == .color(Color.yellow))
    #expect(cells[0].style.emphasis.contains(.bold))
    #expect(cells[1].style.emphasis.contains(.bold))
  }

  @Test("control value math clamps and steps within bounds")
  func controlValueMathClampsAndStepsWithinBounds() {
    #expect(clampedControlValue(-1, to: 0...10) == 0)
    #expect(clampedControlValue(11, to: 0...10) == 10)
    #expect(steppedControlValue(from: 5, delta: 3, bounds: 0...10) == 8)
    #expect(steppedControlValue(from: 9, delta: 3, bounds: 0...10) == 10)
    #expect(stepperCanAdjust(9, delta: 1, bounds: 0...10))
    #expect(!stepperCanAdjust(10, delta: 1, bounds: 0...10))
  }

  @Test("double control values preserve fractional steps and clean formatting")
  func doubleControlValuesPreserveFractionalStepsAndFormatting() {
    #expect(clampedControlValue(-0.5, to: 0.0...1.0) == 0.0)
    #expect(
      steppedControlValue(
        from: 0.2,
        delta: 1,
        step: 0.1,
        bounds: 0.0...1.0
      ) == 0.3
    )
    #expect(
      steppedControlValue(
        from: 0.35,
        delta: 1,
        step: 0.1,
        bounds: 0.0...1.0
      ) == 0.45
    )
    #expect(
      sliderValue(
        at: 5.5,
        in: .init(origin: .zero, size: .init(width: 11, height: 1)),
        bounds: 0.0...1.0,
        step: 0.25
      ) == 0.5
    )
    #expect(
      sliderValue(
        at: 1.75,
        in: .init(origin: .zero, size: .init(width: 4, height: 1)),
        bounds: 0.0...1.0,
        step: 0.01
      ) == 0.25
    )
    #expect(
      sliderValue(
        at: PointerLocation.cellFallback(.init(x: 2, y: 0)).location.x,
        in: .init(origin: .zero, size: .init(width: 4, height: 1)),
        bounds: 0.0...1.0,
        step: 0.01
      ) == 1.0
    )
    #expect(formattedControlValue(0.30000000000000004, bounds: 0.0...1.0, step: 0.1) == "0.3")
    #expect(formattedControlValue(0.45, bounds: 0.0...1.0, step: 0.1) == "0.45")
  }
}
