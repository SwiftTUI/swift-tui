import Testing

@testable import SwiftTUIRuntime

@Suite
struct TerminalCellEncodingTests {
  static let profiles: [TerminalCapabilityProfile] = [
    .trueColor, .ansi256, .ansi16, .previewUnicode, .previewASCII,
    .init(
      glyphLevel: .ascii, colorLevel: .ansi16, emitsStyleEscapeSequences: true,
      supportsHyperlinks: true),
  ]

  @Test("link runs preserve authored URI bytes and sanitizer collisions", arguments: profiles)
  func hyperlinkTransitions(profile: TerminalCapabilityProfile) {
    let renderer = TerminalCellTextRenderer(capabilityProfile: profile)
    var state = TerminalCellTextRenderer.RenderState()
    var output = ""
    let destinations: [String?] = [
      "https://a.test", "https://a.test\u{07}",
      "https://a.test/é", "https://a.test/e\u{301}",
      "", nil, "\u{1B}\\\u{07}", "https://a.test",
    ]
    for (index, destination) in destinations.enumerated() {
      let character = Character(String(index))
      renderer.appendRenderedCells(
        in: Array(repeating: RasterCell(character: character, hyperlink: destination), count: 2),
        from: 0, to: 2, into: &output, state: &state)
    }
    renderer.closeRenderState(&state, into: &output)

    let close = "\u{1B}]8;;\u{1B}\\"
    let expected =
      profile.supportsHyperlinks
      ? "\u{1B}]8;;https://a.test\u{1B}\\0011" + close
        + "\u{1B}]8;;https://a.test/%C3%A9\u{1B}\\22" + close
        + "\u{1B}]8;;https://a.test/e%CC%81\u{1B}\\33" + close
        + "445566\u{1B}]8;;https://a.test\u{1B}\\77" + close
      : "0011223344556677"
    #expect(output == expected)
  }

  @Test("canonically reordered marks with equal byte counts remain distinct URLs")
  func canonicallyReorderedDestinations() {
    let first = "https://a.test/a\u{301}\u{323}"
    let second = "https://a.test/a\u{323}\u{301}"
    #expect(first == second)
    #expect(first.utf8.count == second.utf8.count)
    let output = TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(
      RasterSurface(
        size: .init(width: 2, height: 1),
        cells: [
          [
            RasterCell(character: "A", hyperlink: first),
            RasterCell(character: "B", hyperlink: second),
          ]
        ]))
    #expect(
      output == "\u{1B}]8;;https://a.test/a%CC%81%CC%A3\u{1B}\\A\u{1B}]8;;\u{1B}\\"
        + "\u{1B}]8;;https://a.test/a%CC%A3%CC%81\u{1B}\\B\u{1B}]8;;\u{1B}\\")
  }

  @Test("closing a run reopens a cached link and re-emits its style", arguments: profiles)
  func closeAndReopen(profile: TerminalCapabilityProfile) {
    let renderer = TerminalCellTextRenderer(capabilityProfile: profile)
    var state = TerminalCellTextRenderer.RenderState()
    var output = ""
    let row = [
      RasterCell(
        character: "X", style: .init(emphasis: .bold), hyperlink: "https://a.test/é")
    ]
    for _ in 0..<2 {
      renderer.appendRenderedCells(in: row, from: 0, to: 1, into: &output, state: &state)
      renderer.closeRenderState(&state, into: &output)
    }
    let single =
      (profile.supportsHyperlinks ? "\u{1B}]8;;https://a.test/%C3%A9\u{1B}\\" : "")
      + (profile.emitsStyleEscapeSequences ? "\u{1B}[1m" : "") + "X"
      + (profile.supportsHyperlinks ? "\u{1B}]8;;\u{1B}\\" : "")
      + (profile.emitsStyleEscapeSequences ? "\u{1B}[0m" : "")
    #expect(output == single + single)
  }

  @Test(
    "row batches count owned columns including placeholders and out-of-row blanks",
    arguments: profiles)
  func rowBatchMetrics(profile: TerminalCapabilityProfile) throws {
    let row: [RasterCell] = [
      .init(character: "A"),
      .init(character: "界", spanWidth: 2),
      .init(spanWidth: 0, continuationLeadX: 1),
      .init(character: "\u{301}", spanWidth: 0),
      .init(character: "\u{1B}"),
      .init(character: "B"),
    ]
    let renderer = TerminalSurfaceRenderer(capabilityProfile: profile)
    let batch = try #require(renderer.renderRowBatch(row: 3, currentRow: row, spans: [0..<6]))
    #expect(batch.cellsChanged == 6)
    #expect(batch.spanUpdates.map(\.cellsChanged) == [6])
    #expect(batch.renderedBatch == (profile.glyphLevel == .ascii ? "A?? ?B" : "A界 �B"))

    let partial = try #require(
      renderer.renderRowBatch(
        row: 3, currentRow: row, spans: [2..<3, 4..<5, 7..<9, 1..<1]))
    #expect(partial.spanUpdates.map(\.cellsChanged) == [0, 1, 2])
    #expect(partial.cellsChanged == 3)
    #expect(
      partial.renderedBatch == "\u{1B}[1C" + (profile.glyphLevel == .ascii ? "?" : "�")
        + "\u{1B}[2C  ")
    #expect(renderer.renderRowBatch(row: 0, currentRow: row, spans: [0..<0]) == nil)
  }
}
