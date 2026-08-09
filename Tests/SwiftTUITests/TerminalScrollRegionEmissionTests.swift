import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// R2.3: verified scroll-region emission — the planner proves a
/// scroll-translation candidate cell-for-cell against the written baseline
/// and, on success, emits DECSTBM + SU/SD + targeted repaints instead of
/// repainting the band.
///
/// The screen-model round trips are the soundness pins: previous emission
/// then scroll-region emission must land the model on exactly the surface a
/// fresh full repaint would produce, for both scroll directions, multi-row
/// deltas, and flanking-chrome/indicator mismatches.
@MainActor
@Suite
struct TerminalScrollRegionEmissionTests {
  // MARK: - Fixtures

  /// Style-free profile with the scroll-region vocabulary enabled, so the
  /// emitted bytes stay plain text + cursor motion and the ANSI screen model
  /// replays them exactly.
  private static let scrollRegionProfile: TerminalCapabilityProfile = {
    var profile = TerminalCapabilityProfile.previewUnicode
    profile.supportsScrollRegions = true
    return profile
  }()

  private static let surfaceSize = CellSize(width: 12, height: 8)
  /// Band rows 2...6 (half-open maxY 7): rows 0, 1, and 7 are off-band chrome.
  private static let band = CellRect(
    origin: CellPoint(x: 0, y: 2),
    size: CellSize(width: 12, height: 5)
  )

  private static func surface(bandRows: [String]) -> RasterSurface {
    precondition(bandRows.count == 5)
    return RasterSurface(
      size: surfaceSize,
      lines: ["header", "-------"] + bandRows + ["footer"]
    )
  }

  private static let previousSurface = surface(
    bandRows: ["item 10", "item 11", "item 12", "item 13", "item 14"]
  )

  private static func candidate(dy: Int, band: CellRect = band) -> ScrollTranslationCandidate {
    ScrollTranslationCandidate(band: band, dy: dy, baselineFrameOrdinal: 1)
  }

  private static func padded(_ text: String, to width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
  }

  private static func plan(
    previous: RasterSurface = previousSurface,
    current: RasterSurface,
    damage: PresentationDamage? = nil,
    candidate: ScrollTranslationCandidate?,
    capabilityProfile: TerminalCapabilityProfile = scrollRegionProfile
  ) -> TerminalPresentationPlan {
    TerminalPresentationPlanner(capabilityProfile: capabilityProfile).plan(
      previousSurface: previous,
      currentSurface: current,
      damage: damage,
      translationCandidate: candidate
    )
  }

  private static func emissionOutput(
    for surface: RasterSurface,
    plan: TerminalPresentationPlan,
    capabilityProfile: TerminalCapabilityProfile = scrollRegionProfile
  ) -> String {
    var transmittedKittyImages: Set<UInt32> = []
    var residentKittyImageData: Set<UInt32> = []
    let emission = TerminalHostPresentationEmissionBuilder(
      capabilityProfile: capabilityProfile,
      usesTerminalEditOperations: false,
      imageRenderer: TerminalImageRenderer(repository: sharedImageAssetRepository),
      fallbackBackground: TerminalAppearance.fallback.backgroundColor,
      terminalBackgroundColor: nil
    ).build(
      for: surface,
      plan: plan,
      graphicsCapabilities: .none,
      transmittedKittyImages: &transmittedKittyImages,
      residentKittyImageData: &residentKittyImageData
    )
    return TerminalHostEscapeSequences.wrappedSynchronizedOutput(
      emission.output,
      plan: plan,
      capabilityProfile: capabilityProfile
    )
  }

  /// Replays `previous` as a full repaint and then the scroll-region frame's
  /// emission, asserting the model lands on exactly what a fresh full
  /// repaint of `current` shows — the byte-level soundness contract.
  private static func expectRoundTrip(
    previous: RasterSurface = previousSurface,
    current: RasterSurface,
    plan: TerminalPresentationPlan
  ) {
    var screen = ANSIVisibleScreen(size: surfaceSize)
    screen.feed(
      Array(
        fullRepaintOutput(for: previous, capabilityProfile: scrollRegionProfile).utf8
      )
    )
    screen.feed(Array(emissionOutput(for: current, plan: plan).utf8))

    var freshScreen = ANSIVisibleScreen(size: surfaceSize)
    freshScreen.feed(
      Array(
        fullRepaintOutput(for: current, capabilityProfile: scrollRegionProfile).utf8
      )
    )
    #expect(screen.renderedText == freshScreen.renderedText)
  }

  // MARK: - Escape vocabulary

  @Test("scroll-region escape sequences use 1-based inclusive DECSTBM rows")
  func escapeSequenceVocabulary() {
    #expect(TerminalHostEscapeSequences.setScrollRegion(top: 3, bottom: 7) == "\u{001B}[3;7r")
    #expect(TerminalHostEscapeSequences.resetScrollRegion == "\u{001B}[r")
    #expect(TerminalHostEscapeSequences.scrollUp(2) == "\u{001B}[2S")
    #expect(TerminalHostEscapeSequences.scrollDown(3) == "\u{001B}[3T")
  }

  // MARK: - Planner verification

  @Test("a verified scroll-down candidate plans SU with only the exposed row repainted")
  func verifiedScrollDownPlansScrollRegion() {
    // dy = -1: content slid up one row; row 6 is exposed.
    let current = Self.surface(
      bandRows: ["item 11", "item 12", "item 13", "item 14", "item 15"]
    )
    let plan = Self.plan(current: current, candidate: Self.candidate(dy: -1))

    #expect(plan.strategy == .incremental)
    #expect(plan.scrollRegion == .init(topRow: 2, bottomRow: 6, delta: -1))
    #expect(plan.rowBatches.map(\.row) == [6])
    Self.expectRoundTrip(current: current, plan: plan)
  }

  @Test("a verified scroll-up candidate plans SD with the exposed row at the top")
  func verifiedScrollUpPlansScrollDown() {
    // dy = +1: content slid down one row; row 2 is exposed.
    let current = Self.surface(
      bandRows: ["item 9", "item 10", "item 11", "item 12", "item 13"]
    )
    let plan = Self.plan(current: current, candidate: Self.candidate(dy: 1))

    #expect(plan.scrollRegion == .init(topRow: 2, bottomRow: 6, delta: 1))
    #expect(plan.rowBatches.map(\.row) == [2])
    Self.expectRoundTrip(current: current, plan: plan)
  }

  @Test("a multi-row delta translates the surviving rows and repaints the exposed tail")
  func multiRowDeltaScrollRegion() {
    // dy = -3: rows 2...3 translate (sources 5...6), rows 4...6 are exposed.
    let current = Self.surface(
      bandRows: ["item 13", "item 14", "item 15", "item 16", "item 17"]
    )
    let plan = Self.plan(current: current, candidate: Self.candidate(dy: -3))

    #expect(plan.scrollRegion == .init(topRow: 2, bottomRow: 6, delta: -3))
    #expect(plan.rowBatches.map(\.row) == [4, 5, 6])
    Self.expectRoundTrip(current: current, plan: plan)
  }

  @Test("a moving indicator column keeps the translation and repaints only the thumb cells")
  func indicatorColumnMismatchRepaintsAsSpans() {
    // A plain ScrollView's band includes its trailing indicator column
    // (r2b-notes trap (a)): the thumb glyph moves every notch, so the
    // translated rows mismatch in exactly that column. The translation must
    // survive with the thumb repainted as ordinary span updates.
    func indicatored(_ rows: [String], thumbRow: Int) -> RasterSurface {
      Self.surface(
        bandRows: rows.enumerated().map { index, row in
          Self.padded(row, to: 11) + (index == thumbRow ? "█" : "│")
        }
      )
    }
    let previous = indicatored(
      ["item 10", "item 11", "item 12", "item 13", "item 14"],
      thumbRow: 0
    )
    let current = indicatored(
      ["item 11", "item 12", "item 13", "item 14", "item 15"],
      thumbRow: 1
    )
    let plan = Self.plan(
      previous: previous,
      current: current,
      candidate: Self.candidate(dy: -1)
    )

    #expect(plan.scrollRegion == .init(topRow: 2, bottomRow: 6, delta: -1))
    // Exposed row 6 plus the thumb-mismatch repaints; every batch except the
    // exposed row must be a narrow indicator-column span, not a row repaint.
    let indicatorBatches = plan.rowBatches.filter { $0.row != 6 }
    #expect(!indicatorBatches.isEmpty)
    for batch in indicatorBatches {
      #expect(batch.spanUpdates.allSatisfy { $0.column == 11 && $0.cellsChanged == 1 })
    }
    Self.expectRoundTrip(previous: previous, current: current, plan: plan)
  }

  @Test("partial-width bands translate when flanking chrome is row-invariant")
  func partialWidthBandWithRowInvariantChrome() {
    // The perf fixtures wrap their collections in padding + border, so the
    // candidate band is narrower than the surface. DECSTBM still shifts the
    // full width; row-invariant chrome (border verticals) proves equal under
    // translation, so the region survives verification.
    func bordered(_ items: [String]) -> RasterSurface {
      Self.surface(
        bandRows: items.map { item in
          "│" + Self.padded(item, to: 10) + "│"
        }
      )
    }
    let previous = bordered(["item 10", "item 11", "item 12", "item 13", "item 14"])
    let current = bordered(["item 11", "item 12", "item 13", "item 14", "item 15"])
    let plan = Self.plan(
      previous: previous,
      current: current,
      candidate: Self.candidate(
        dy: -1,
        band: CellRect(origin: CellPoint(x: 1, y: 2), size: CellSize(width: 10, height: 5))
      )
    )

    #expect(plan.scrollRegion == .init(topRow: 2, bottomRow: 6, delta: -1))
    #expect(plan.rowBatches.map(\.row) == [6])
    Self.expectRoundTrip(previous: previous, current: current, plan: plan)
  }

  @Test("off-band damage keeps its hinted repaint alongside the scroll region")
  func offBandRowsFollowDamageHints() {
    // Row 0 changes in the same frame the band scrolls: the scroll region
    // covers the band, the off-band row keeps today's damage-hinted diff.
    let scrolled = Self.surface(
      bandRows: ["item 11", "item 12", "item 13", "item 14", "item 15"]
    )
    let current = RasterSurface(
      size: Self.surfaceSize,
      lines: ["HEADER"] + Array(scrolled.lines.dropFirst())
    )
    let plan = Self.plan(
      current: current,
      damage: PresentationDamage(dirtyRows: [0, 2, 3, 4, 5, 6]),
      candidate: Self.candidate(dy: -1)
    )

    #expect(plan.scrollRegion != nil)
    #expect(plan.rowBatches.map(\.row) == [0, 6])
    Self.expectRoundTrip(current: current, plan: plan)
  }

  @Test("an in-band row the damage hint omits is still verified against the shifted baseline")
  func inBandRowsIgnoreDamageHints() {
    // A damage hint computed against the unshifted baseline can omit an
    // in-band row whose content is frame-over-frame identical — but the
    // scroll moves it anyway. The planner must diff every band row against
    // the shifted source regardless of the hint, or the emission repaints
    // nothing and the terminal shows the shifted row.
    let previous = Self.surface(
      bandRows: ["same", "same", "same", "same", "item 14"]
    )
    let current = Self.surface(
      bandRows: ["same", "same", "same", "item 14", "item 15"]
    )
    let plan = Self.plan(
      previous: previous,
      current: current,
      // The hint claims only rows 5 and 6 changed — true against the
      // unshifted baseline, incomplete under translation.
      damage: PresentationDamage(dirtyRows: [5, 6]),
      candidate: Self.candidate(dy: -1)
    )

    #expect(plan.scrollRegion != nil)
    Self.expectRoundTrip(previous: previous, current: current, plan: plan)
  }

  @Test("screen-pinned chrome rows at the band edges are trimmed out of the region")
  func pinnedEdgeRowsAreTrimmedFromRegion() {
    // A hosted collection's published band includes its overflow-indicator
    // lines and box-border rows, which stay at fixed screen positions while
    // the content translates. They must leave the DECSTBM region — outside
    // it their unshifted diff is empty and they cost nothing; inside it they
    // would be repainted full-width every notch.
    func chromed(_ items: [String]) -> RasterSurface {
      precondition(items.count == 3)
      return Self.surface(bandRows: ["== top =="] + items + ["== bot =="])
    }
    let previous = chromed(["item 1", "item 2", "item 3"])
    let current = chromed(["item 2", "item 3", "item 4"])
    let plan = Self.plan(
      previous: previous,
      current: current,
      candidate: Self.candidate(dy: -1)
    )

    // Band rows 2...6; pinned rows 2 and 6 trimmed; region 3...5 scrolls,
    // row 5 is the exposed row; the pinned rows emit nothing at all.
    #expect(plan.scrollRegion == .init(topRow: 3, bottomRow: 5, delta: -1))
    #expect(plan.rowBatches.map(\.row) == [5])
    Self.expectRoundTrip(previous: previous, current: current, plan: plan)
  }

  @Test("a sliver-sized damage hint skips the translation entirely")
  func sliverDamageHintSkipsTranslation() {
    // The uniform-collection shape: consecutive rows differ in a couple of
    // digit cells, so the hinted plain diff is already tiny and the
    // full-band verification could only add planner cost. The pre-gate must
    // decline before diffing a single band row.
    let current = Self.surface(
      bandRows: ["item 11", "item 12", "item 13", "item 14", "item 15"]
    )
    let plan = Self.plan(
      current: current,
      // Narrow hinted ranges: one cell on each band row (5 of the band's 60
      // cells) — well below the 15% band share the pre-gate requires.
      damage: PresentationDamage(
        textRows: (2..<7).map { .init(row: $0, columnRanges: [5..<6]) }
      ),
      candidate: Self.candidate(dy: -1)
    )

    #expect(plan.scrollRegion == nil)
    #expect(plan.strategy == .incremental)
  }

  @Test("band-wide mismatch falls back to the plain incremental diff")
  func bandWideMismatchFallsBackWholesale() {
    // Every translated row disagrees with its shifted source: the
    // translation hypothesis is wrong, and the planner must decline rather
    // than emit a scroll plus a full band repaint.
    let current = Self.surface(
      bandRows: ["other 1", "other 2", "other 3", "other 4", "other 5"]
    )
    let plan = Self.plan(current: current, candidate: Self.candidate(dy: -1))

    #expect(plan.scrollRegion == nil)
    #expect(plan.strategy == .incremental)
  }

  @Test("the capability gate and degenerate candidates decline the translation")
  func capabilityAndGeometryGates() {
    let current = Self.surface(
      bandRows: ["item 11", "item 12", "item 13", "item 14", "item 15"]
    )

    // Profile without the scroll-region vocabulary (the previewUnicode
    // default): plain incremental, identical row batches to no candidate.
    let gated = Self.plan(
      current: current,
      candidate: Self.candidate(dy: -1),
      capabilityProfile: .previewUnicode
    )
    #expect(gated.scrollRegion == nil)

    // A band-sized jump shares no rows with the baseline.
    let jump = Self.plan(current: current, candidate: Self.candidate(dy: -5))
    #expect(jump.scrollRegion == nil)

    // A band that leaves the surface can't scope a DECSTBM region.
    let overhang = Self.plan(
      current: current,
      candidate: Self.candidate(
        dy: -1,
        band: CellRect(origin: CellPoint(x: 0, y: 4), size: CellSize(width: 12, height: 5))
      )
    )
    #expect(overhang.scrollRegion == nil)
  }

  // MARK: - Emission bytes

  @Test("the emission orders region ops before repaints inside the synchronized wrap")
  func emissionOrdersRegionOpsBeforeRepaints() {
    var profile = Self.scrollRegionProfile
    profile.supportsSynchronizedOutput = true
    let current = Self.surface(
      bandRows: ["item 11", "item 12", "item 13", "item 14", "item 15"]
    )
    let plan = Self.plan(
      current: current,
      candidate: Self.candidate(dy: -1),
      capabilityProfile: profile
    )
    let output = Self.emissionOutput(for: current, plan: plan, capabilityProfile: profile)

    // Begin sync → DECSTBM(3;7) → SU 1 → region reset → cursor home →
    // exposed-row repaint (absolute CUP) → end sync.
    #expect(
      output.hasPrefix(
        "\u{001B}[?2026h" + "\u{001B}[3;7r" + "\u{001B}[1S" + "\u{001B}[r" + "\u{001B}[1;1H"
      )
    )
    #expect(output.hasSuffix("\u{001B}[?2026l"))
    #expect(output.contains("\u{001B}[7;1H"), "the exposed row repaints via absolute CUP")
    // The exposed row's diff against blank skips the blank-equal gap between
    // words, so the repaint is "item", cursor-forward, "15".
    #expect(output.contains("item"))
    #expect(output.contains("15"))
    #expect(!output.contains("item 12"), "translated rows must not be repainted")

    // A scroll-region frame always wraps, even below the multi-batch
    // threshold (this plan repaints a single row).
    #expect(plan.rowBatches.count == 1)
    #expect(
      TerminalHostEscapeSequences.usesSynchronizedOutput(
        for: output,
        plan: plan,
        capabilityProfile: profile
      )
    )
  }

  // MARK: - End-to-end (run loop → latch → planner → emission)

  @Test("a wheel notch over a live scroll view emits one scroll-region translation")
  func wheelNotchEmitsScrollRegionEndToEnd() throws {
    let harness = try ScrollRegionEmissionHarness()
    let mountMetrics = try #require(harness.presentedMetrics.last)
    #expect(mountMetrics.strategy == .fullRepaint)
    #expect(mountMetrics.scrollRegionOperationCount == 0)

    harness.scroll(deltaY: 1)
    try harness.render()

    let notchMetrics = try #require(harness.presentedMetrics.last)
    #expect(notchMetrics.strategy == .incremental)
    #expect(
      notchMetrics.scrollRegionOperationCount == 1,
      "the candidate must survive the latch, verify against the baseline, and emit"
    )
    // The translated band is not repainted: the notch frame's bytes are the
    // region ops plus the exposed row and indicator-thumb repaints — well
    // below the mount frame's full repaint.
    #expect(notchMetrics.bytesWritten < mountMetrics.bytesWritten / 2)
  }
}

/// A live run-loop session over a plain full-height `ScrollView` presented
/// through `TerminalEmissionSimulationHost` — the real planner + emission
/// builder, byte-counting sink, scroll regions armed (the lane profile).
///
/// The fixture's content overflows, so the trailing indicator column is live
/// and its thumb moves on every notch — the end-to-end pin covers the
/// indicator-mismatch repaint path, not just clean translations.
@MainActor
private final class ScrollRegionEmissionHarness {
  let rootIdentity = testIdentity("ScrollRegionEmissionFixture")
  let terminalSize = CellSize(width: 24, height: 10)
  var presentedMetrics: [TerminalPresentationMetrics] { metricsLog.metrics }
  private let metricsLog = PresentedMetricsLog()
  private(set) var runLoop: RunLoop<Int, AnyView>!
  private var renderedFrames = 0

  init() throws {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = terminalSize
    let rootIdentity = rootIdentity
    let metricsLog = metricsLog

    let host = TerminalEmissionSimulationHost(
      surfaceSize: terminalSize,
      onPresent: { _, metrics in
        metricsLog.record(metrics)
      }
    )
    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: EmissionInputReader(),
      signalReader: EmissionSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: ScopedMapper { _ in
        AnyView(
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<40) { index in
                // Rows must differ across most of their width so the
                // frame-tail damage hint is band-shaped: the scroll-region
                // pre-gate deliberately skips sliver hints (digit-only
                // deltas), and this pin is about the translation path.
                Text(String(repeating: "\(index % 10)", count: 18))
              }
            }
          }
          .frame(width: 24, height: 10, alignment: .topLeading)
        )
      }
    )
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
  }

  func scroll(deltaY: Int) {
    _ = runLoop.handle(
      .input(
        .mouse(
          MouseEvent(
            kind: .scrolled(deltaX: 0, deltaY: deltaY),
            location: .cellFallback(CellPoint(x: 4, y: 3))
          )))
    )
  }

  func render() throws {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }
}

/// The presented-frame metrics log the simulation host's `onPresent` feeds —
/// a plain nonisolated class (the run loop presents synchronously on the
/// test's thread), mirroring `PerfTerminalHost`'s recording shape.
private final class PresentedMetricsLog {
  private(set) var metrics: [TerminalPresentationMetrics] = []

  func record(_ metrics: TerminalPresentationMetrics) {
    self.metrics.append(metrics)
  }
}

private final class EmissionInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class EmissionSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
