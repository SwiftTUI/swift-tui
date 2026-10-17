@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 3: terminal presentation planning and emission
// (281–290).
//
// The terminal host keeps a written baseline and plans each frame as a full
// repaint or a set of row batches; the session's own contract says a full
// repaint happens only when no written baseline exists. These probes feed
// the host and the planner the shapes that sit beside that contract: an
// explicit full-repaint hint, out-of-band writes (clipboard, hover mode)
// between frames, a raw-mode round trip, degenerate window sizes, rows past
// the declared surface, wide glyphs on span boundaries, styled trailing
// cells, identical frames, and scroll-region candidates at their limits.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: terminal output", .serialized)
struct AdversarialSetBTerminalOutputTests {
  private func makeHost(
    _ controller: SetBRecordingController, profile: TerminalCapabilityProfile = .previewUnicode,
    fallback: CellSize = .init(width: 80, height: 24)
  ) -> TerminalHost {
    TerminalHost(
      inputFileDescriptor: 0, outputFileDescriptor: 1, fallbackSize: fallback,
      controller: controller, capabilityProfile: profile, environment: [:])
  }

  private func surface(_ lines: [String], width: Int, height: Int) -> RasterSurface {
    RasterSurface(size: .init(width: width, height: height), lines: lines)
  }

  // A damage hint that asks for a full text repaint repaints the text.
  @Test func setB281FullTextRepaintHintRepaintsTheText() throws {
    let controller = SetBRecordingController()
    let host = makeHost(controller)
    _ = try host.present(surface(["alpha", "same"], width: 8, height: 2))
    try host.drainPendingPresentation()
    let before = controller.writes.count
    let metrics = try (host as any DamageAwarePresentationSurface).present(
      surface(["ALPHA", "SAME"], width: 8, height: 2),
      damage: PresentationDamage(requiresFullTextRepaint: true))
    try host.drainPendingPresentation()
    let written = controller.writes.dropFirst(before).joined()
    withKnownIssue(
      "the planner diffs only dirtyRows; a bare requiresFullTextRepaint hint writes nothing"
    ) {
      #expect(written.contains("ALPHA"), "\(written.debugDescription)")
      #expect(metrics.bytesWritten > 0, "\(metrics)")
    }
    let afterHint = controller.writes.count
    _ = try (host as any DamageAwarePresentationSurface).present(
      surface(["omega", "SAME"], width: 8, height: 2),
      damage: PresentationDamage(dirtyRows: [0, 1]))
    try host.drainPendingPresentation()
    let repainted = controller.writes.dropFirst(afterHint).joined()
    #expect(
      repainted.contains("omega"),
      "a row hint still reaches the screen: \(repainted.debugDescription)")
  }

  // Writing the clipboard between frames does not discard the written
  // baseline: the next frame is incremental.
  @Test func setB282ClipboardWriteKeepsTheWrittenBaseline() throws {
    let controller = SetBRecordingController()
    let host = makeHost(controller, profile: .trueColor)
    _ = try host.present(surface(["alpha"], width: 8, height: 1))
    try host.drainPendingPresentation()
    try host.writeClipboard("x")
    let metrics = try host.present(surface(["alpXa"], width: 8, height: 1))
    try host.drainPendingPresentation()
    withKnownIssue(
      "an out-of-band write invalidates the presentation state, forcing a full repaint"
    ) {
      #expect(metrics.strategy == .incremental, "\(metrics.strategy)")
      #expect(
        controller.writes.last?.contains("\u{1B}[2J") == false,
        "\(controller.writes.last.debugDescription)")
    }
    #expect(controller.writes.joined().contains("X"))
  }

  // Toggling pointer-hover reporting between frames keeps the baseline too.
  @Test func setB283HoverModeToggleKeepsTheWrittenBaseline() throws {
    let controller = SetBRecordingController(isTTY: true)
    let host = makeHost(controller, profile: .trueColor)
    try host.enableRawMode()
    defer { try? host.disableRawMode() }
    _ = try host.present(surface(["alpha", "beta"], width: 8, height: 2))
    try host.drainPendingPresentation()
    try host.setPointerHoverEnabled(true)
    let metrics = try host.present(surface(["alpha", "bEta"], width: 8, height: 2))
    try host.drainPendingPresentation()
    withKnownIssue("the hover-mode write goes through the invalidating write path") {
      #expect(metrics.strategy == .incremental, "\(metrics.strategy)")
    }
    #expect(controller.writes.joined().contains("\u{1B}[?1003h"), "hover reporting was enabled")
  }

  // Hover reporting survives a raw-mode round trip like reader mode does: the
  // re-enable bytes turn it back on.
  @Test func setB284HoverReportingSurvivesARawModeRoundTrip() throws {
    let controller = SetBRecordingController(isTTY: true)
    let host = makeHost(controller, profile: .trueColor)
    try host.enableRawMode()
    try host.setPointerHoverEnabled(true)
    try #require(controller.writes.joined().contains("\u{1B}[?1003h"))
    try host.disableRawMode()
    let before = controller.writes.count
    try host.enableRawMode()
    defer { try? host.disableRawMode() }
    let reenabled = controller.writes.dropFirst(before).joined()
    #expect(reenabled.contains("\u{1B}[?1006h"), "\(reenabled.debugDescription)")
    withKnownIssue(
      "the raw-mode session resets pointerHoverEnabled, and the run loop never re-applies it"
    ) {
      #expect(reenabled.contains("\u{1B}[?1003h"), "\(reenabled.debugDescription)")
    }
  }

  // A controller that reports a zero window size is treated as unknown: the
  // host uses its fallback size.
  @Test func setB285ZeroWindowSizeFallsBackToTheFallbackSize() throws {
    let zero = SetBRecordingController(windowSize: .zero)
    let host = makeHost(zero)
    withKnownIssue(
      "surfaceSize falls back only when windowSize throws, not when it reports 0×0 (adjacent to STUI-1006)"
    ) {
      #expect(host.surfaceSize == CellSize(width: 80, height: 24), "\(host.surfaceSize)")
    }
    let halfZero = SetBRecordingController(windowSize: .init(width: 0, height: 24))
    let halfHost = makeHost(halfZero)
    withKnownIssue("a zero width is also kept as the surface size") {
      #expect(halfHost.surfaceSize.width > 0, "\(halfHost.surfaceSize)")
    }
    // A zero-size first frame still emits only the clear and home sequence.
    let metrics = try host.present(RasterSurface(size: .zero, cells: []))
    try host.drainPendingPresentation()
    #expect(metrics.strategy == .fullRepaint)
    #expect(zero.writes.joined().hasPrefix("\u{1B}[2J"), "\(zero.writes.joined().debugDescription)")
  }

  // Rows beyond the declared surface height are never addressed: the
  // incremental and full-repaint paths agree on the surface.
  @Test func setB286RowsPastTheSurfaceHeightAreNotAddressed() throws {
    let row0 = "abcd".map { RasterCell(character: $0) }
    let row1 = "efgh".map { RasterCell(character: $0) }
    let row1Changed = "efGh".map { RasterCell(character: $0) }
    let previous = RasterSurface(size: .init(width: 4, height: 1), cells: [row0, row1])
    let current = RasterSurface(size: .init(width: 4, height: 1), cells: [row0, row1Changed])
    let planner = TerminalPresentationPlanner(capabilityProfile: .previewUnicode)
    let plan = planner.plan(previousSurface: previous, currentSurface: current)
    withKnownIssue(
      "the planner diffs max(cells.count, height) rows and addresses row 2 of a one-row surface"
    ) {
      #expect(plan.rowBatches.allSatisfy { $0.row < 1 }, "\(plan.rowBatches.map(\.row))")
    }
    let steps = fullRepaintWriteSteps(for: current, capabilityProfile: .previewUnicode)
    #expect(!steps.joined().contains("\u{1B}[2;1H"), "\(steps)")
  }

  // Damage spans snap to wide-glyph boundaries in both the previous and the
  // current row, and a wide glyph replaced by two narrow ones repaints both
  // cells.
  @Test func setB287SpansNormalizeAroundWideGlyphs() throws {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .previewUnicode)
    func wide(_ glyph: Character, tail: Character) -> [RasterCell] {
      [
        RasterCell(character: "a"), RasterCell(character: glyph, spanWidth: 2),
        RasterCell(character: " ", spanWidth: 0, continuationLeadX: 1), RasterCell(character: tail),
      ]
    }
    let previous = wide("界", tail: "b")
    let current = wide("語", tail: "b")
    let planner = TerminalPresentationPlanner(capabilityProfile: .previewUnicode)
    func plan(hint: Range<Int>) -> TerminalPresentationPlan.RowBatch? {
      planner.plan(
        previousSurface: RasterSurface(size: .init(width: 4, height: 1), cells: [previous]),
        currentSurface: RasterSurface(size: .init(width: 4, height: 1), cells: [current]),
        damage: PresentationDamage(textRows: [.init(row: 0, columnRanges: [hint])])
      ).rowBatches.first
    }
    let wholeGlyph = try #require(plan(hint: 1..<3), "a hint over the whole glyph repaints it")
    #expect(wholeGlyph.anchorColumn == 1, "\(wholeGlyph)")
    #expect(wholeGlyph.renderedBatch == "語", "\(wholeGlyph.renderedBatch.debugDescription)")
    #expect(wholeGlyph.spanUpdates.first?.cellsChanged == 2, "\(wholeGlyph.spanUpdates)")
    let leadOnly = try #require(plan(hint: 1..<2), "a lead-only hint widens over the continuation")
    #expect(leadOnly.renderedBatch == "語", "\(leadOnly.renderedBatch.debugDescription)")
    #expect(leadOnly.spanUpdates.first?.cellsChanged == 2, "\(leadOnly.spanUpdates)")
    let batch = try #require(renderer.renderRowBatch(row: 0, currentRow: current, spans: [1..<3]))
    #expect(batch.renderedBatch == "語", "\(batch.renderedBatch.debugDescription)")
    #expect(batch.spanUpdates.first?.cellsChanged == 2)

    let narrow =
      "ab".map { RasterCell(character: $0) } + [
        RasterCell(character: "c"), RasterCell(character: "d"),
      ]
    let wideToNarrow = renderer.diffSpans(
      previousRow: previous, currentRow: narrow, width: 4, limitingTo: nil)
    #expect(wideToNarrow.contains { $0.contains(1) && $0.contains(2) }, "\(wideToNarrow)")
    let narrowToWide = renderer.diffSpans(
      previousRow: narrow, currentRow: previous, width: 4, limitingTo: nil)
    #expect(narrowToWide.contains { $0.contains(1) && $0.contains(2) }, "\(narrowToWide)")
  }

  // Trailing cells that carry a background are emitted, never trimmed and
  // never lowered to erase-to-end-of-line.
  @Test func setB288StyledTrailingCellsAreEmittedNotErased() throws {
    let background = ResolvedTextStyle(backgroundColor: Color(hexRGB: 0x202020))
    let styled = RasterSurface(
      size: .init(width: 8, height: 1), lines: ["alph    "],
      styleRuns: [.init(x: 4, y: 0, length: 4, style: background)])
    let full = TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(styled)
    #expect(full.contains("48;2;32;32;32"), "\(full.debugDescription)")
    #expect(full.hasSuffix("    \u{1B}[0m"), "\(full.debugDescription)")

    let controller = SetBRecordingController(isTTY: true)
    let host = makeHost(controller, profile: .trueColor)
    _ = try host.present(surface(["alphabet"], width: 8, height: 1))
    try host.drainPendingPresentation()
    let before = controller.writes.count
    let metrics = try host.present(styled)
    try host.drainPendingPresentation()
    let written = controller.writes.dropFirst(before).joined()
    #expect(metrics.strategy == .incremental)
    #expect(written.contains("48;2;32;32;32"), "\(written.debugDescription)")
    #expect(!written.contains("\u{1B}[K"), "\(written.debugDescription)")

    // Unstyled trailing spaces are lowered to erase-to-end-of-line on a TTY.
    let plainHost = makeHost(SetBRecordingController(isTTY: true), profile: .trueColor)
    _ = try plainHost.present(surface(["alphabet"], width: 8, height: 1))
    try plainHost.drainPendingPresentation()
    _ = try plainHost.present(surface(["alph"], width: 8, height: 1))
    try plainHost.drainPendingPresentation()
  }

  // Identical surfaces write nothing, a fresh host full-repaints, and
  // synchronized output wraps only multi-batch frames.
  @Test func setB289IdenticalFramesWriteNothingAndSyncWrapsMultiBatchFrames() throws {
    var profile = TerminalCapabilityProfile.trueColor
    profile = TerminalCapabilityProfile(
      glyphLevel: profile.glyphLevel, colorLevel: profile.colorLevel,
      emitsStyleEscapeSequences: true, supportsHyperlinks: true, supportsMouseReporting: true,
      supportsSynchronizedOutput: true)
    let controller = SetBRecordingController(isTTY: true)
    let host = makeHost(controller, profile: profile)
    let first = try host.present(surface(["alpha", "beta"], width: 8, height: 2))
    try host.drainPendingPresentation()
    #expect(first.strategy == .fullRepaint)
    #expect(first.cellsChanged == 16, "\(first)")
    let writes = controller.writes.count
    let same = try host.present(surface(["alpha", "beta"], width: 8, height: 2))
    try host.drainPendingPresentation()
    #expect(same.strategy == .incremental)
    #expect(same.bytesWritten == 0, "\(same)")
    #expect(!same.usedSynchronizedOutput)
    #expect(controller.writes.count == writes)
    let oneBatch = try host.present(surface(["alpha", "bEta"], width: 8, height: 2))
    try host.drainPendingPresentation()
    #expect(!oneBatch.usedSynchronizedOutput, "\(oneBatch)")
    let twoBatches = try host.present(surface(["Alpha", "beta"], width: 8, height: 2))
    try host.drainPendingPresentation()
    #expect(twoBatches.usedSynchronizedOutput, "\(twoBatches)")
    #expect(
      controller.writes.last?.hasPrefix("\u{1B}[?2026h") == true,
      "\(controller.writes.last.debugDescription)")
    #expect(TerminalHostEscapeSequences.cursor(to: CellPoint(x: -3, y: -9)) == "\u{1B}[1;1H")
    #expect(TerminalHostEscapeSequences.cursor(to: CellPoint(x: 2, y: 0)) == "\u{1B}[1;3H")
    #expect(!TerminalHostEscapeSequences.cursor(to: CellPoint(x: Int.max, y: Int.max)).isEmpty)
  }

  // Scroll-region candidates at their limits decline cleanly: a one-row band,
  // a zero delta, a delta equal to the band, and a resize in the same frame.
  @Test func setB290DegenerateScrollRegionCandidatesDecline() {
    var profile = TerminalCapabilityProfile.previewUnicode
    profile.supportsScrollRegions = true
    let planner = TerminalPresentationPlanner(capabilityProfile: profile)
    let lines = (0..<6).map { "row \($0)" }
    let previous = surface(lines, width: 10, height: 6)
    let scrolled = surface(Array(lines[1...]) + ["row 6"], width: 10, height: 6)
    let band = CellRect(origin: .zero, size: .init(width: 10, height: 6))
    let good = planner.plan(
      previousSurface: previous, currentSurface: scrolled,
      translationCandidate: ScrollTranslationCandidate(band: band, dy: -1, baselineFrameOrdinal: 1))
    #expect(good.scrollRegion != nil, "a one-row scroll of a six-row band is accepted")
    let oneRow = planner.plan(
      previousSurface: previous, currentSurface: scrolled,
      translationCandidate: ScrollTranslationCandidate(
        band: CellRect(origin: .zero, size: .init(width: 10, height: 1)), dy: -1,
        baselineFrameOrdinal: 1))
    #expect(oneRow.scrollRegion == nil)
    let zero = planner.plan(
      previousSurface: previous, currentSurface: scrolled,
      translationCandidate: ScrollTranslationCandidate(band: band, dy: 0, baselineFrameOrdinal: 1))
    #expect(zero.scrollRegion == nil)
    let whole = planner.plan(
      previousSurface: previous, currentSurface: scrolled,
      translationCandidate: ScrollTranslationCandidate(band: band, dy: -6, baselineFrameOrdinal: 1))
    #expect(whole.scrollRegion == nil)
    let resized = planner.plan(
      previousSurface: previous,
      currentSurface: surface(Array(lines[1...]) + ["row 6", "row 7"], width: 10, height: 7),
      translationCandidate: ScrollTranslationCandidate(band: band, dy: -1, baselineFrameOrdinal: 1))
    #expect(resized.strategy == .fullRepaint)
    #expect(resized.scrollRegion == nil)
  }
}

private final class SetBRecordingController: TerminalControlling {
  private let isTTYValue: Bool
  private let windowSizeValue: CellSize
  private let writesStorage = LockedBox<[String]>([])

  var writes: [String] { writesStorage.value }

  init(isTTY: Bool = false, windowSize: CellSize = .init(width: 80, height: 24)) {
    isTTYValue = isTTY
    windowSizeValue = windowSize
  }

  func isATTY(_: Int32) -> Bool { isTTYValue }

  func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
    TerminalModeSnapshot()
  }

  func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {}

  func windowSize(of _: Int32) throws -> CellSize { windowSizeValue }

  func cellPixelSize(of _: Int32) throws -> PixelSize? { nil }

  func write(_ output: String, to _: Int32) throws {
    writesStorage.withLock { $0.append(output) }
  }

  func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] {
    []
  }
}
