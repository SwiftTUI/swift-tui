import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// R2.2: the scroll-translation candidate — a per-presented-frame claim that
/// exactly one scroll route's content moved vertically, produced from the run
/// loop's presented-frame scroll ledger and recorded in `frames.tsv`.
///
/// Nothing consumes the candidate yet; these tests pin its *production*
/// semantics (the ledger diff), its trust-latch discard (the drop-recovery
/// frame must not carry a claim against a rolled-back baseline), and the
/// end-to-end wheel-notch path through a live run loop.
@MainActor
@Suite
struct ScrollTranslationCandidateTests {
  // MARK: - Ledger diff

  private static let routeA = testIdentity("Fixture", "ScrollA")
  private static let routeB = testIdentity("Fixture", "ScrollB")
  private static let surfaceSize = CellSize(width: 80, height: 24)
  private static let viewport = CellRect(
    origin: CellPoint(x: 2, y: 3),
    size: CellSize(width: 40, height: 12)
  )

  private static func ledger(
    ordinal: Int,
    surfaceSize: CellSize = surfaceSize,
    routes: [Identity: ScrollTranslationFrameLedger.RouteState]
  ) -> ScrollTranslationFrameLedger {
    ScrollTranslationFrameLedger(
      frameOrdinal: ordinal,
      surfaceSize: surfaceSize,
      routes: routes
    )
  }

  private static func state(
    x: Int = 0,
    y: Int,
    viewportRect: CellRect = viewport
  ) -> ScrollTranslationFrameLedger.RouteState {
    .init(offset: CellPoint(x: x, y: y), viewportRect: viewportRect)
  }

  @Test("a single moved route produces the candidate with screen-space dy")
  func singleMovedRouteProducesCandidate() {
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(ordinal: 7, routes: [Self.routeA: Self.state(y: 4)]),
      to: Self.ledger(ordinal: 8, routes: [Self.routeA: Self.state(y: 5)])
    )

    // Offset +1 (user scrolled down) slides content UP one row on screen.
    #expect(
      candidate
        == ScrollTranslationCandidate(
          band: Self.viewport,
          dy: -1,
          baselineFrameOrdinal: 7
        )
    )
  }

  @Test("a scroll-up notch produces a positive dy")
  func scrollUpNotchProducesPositiveDy() {
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(ordinal: 3, routes: [Self.routeA: Self.state(y: 5)]),
      to: Self.ledger(ordinal: 4, routes: [Self.routeA: Self.state(y: 2)])
    )

    #expect(candidate?.dy == 3)
  }

  @Test("an unchanged frame (momentum @State echo) produces no candidate")
  func unchangedFrameProducesNoCandidate() {
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(ordinal: 1, routes: [Self.routeA: Self.state(y: 4)]),
      to: Self.ledger(ordinal: 2, routes: [Self.routeA: Self.state(y: 4)])
    )

    #expect(candidate == nil)
  }

  @Test("two moved routes produce no candidate")
  func twoMovedRoutesProduceNoCandidate() {
    let otherViewport = CellRect(
      origin: CellPoint(x: 50, y: 3),
      size: CellSize(width: 20, height: 12)
    )
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(
        ordinal: 1,
        routes: [
          Self.routeA: Self.state(y: 4),
          Self.routeB: Self.state(y: 9, viewportRect: otherViewport),
        ]
      ),
      to: Self.ledger(
        ordinal: 2,
        routes: [
          Self.routeA: Self.state(y: 5),
          Self.routeB: Self.state(y: 10, viewportRect: otherViewport),
        ]
      )
    )

    #expect(candidate == nil)
  }

  @Test("a viewport geometry change on the moved route produces no candidate")
  func geometryChangeProducesNoCandidate() {
    let movedViewport = CellRect(
      origin: CellPoint(x: 2, y: 4),
      size: CellSize(width: 40, height: 12)
    )
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(ordinal: 1, routes: [Self.routeA: Self.state(y: 4)]),
      to: Self.ledger(
        ordinal: 2,
        routes: [Self.routeA: Self.state(y: 5, viewportRect: movedViewport)]
      )
    )

    #expect(candidate == nil)
  }

  @Test("a surface resize produces no candidate")
  func surfaceResizeProducesNoCandidate() {
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(ordinal: 1, routes: [Self.routeA: Self.state(y: 4)]),
      to: Self.ledger(
        ordinal: 2,
        surfaceSize: CellSize(width: 80, height: 25),
        routes: [Self.routeA: Self.state(y: 5)]
      )
    )

    #expect(candidate == nil)
  }

  @Test("a horizontal component produces no candidate (dx deferred)")
  func horizontalComponentProducesNoCandidate() {
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(ordinal: 1, routes: [Self.routeA: Self.state(x: 0, y: 4)]),
      to: Self.ledger(ordinal: 2, routes: [Self.routeA: Self.state(x: 1, y: 5)])
    )

    #expect(candidate == nil)
  }

  @Test("a route-set change produces no candidate")
  func routeSetChangeProducesNoCandidate() {
    // Added route (count differs).
    #expect(
      ScrollTranslationFrameLedger.candidate(
        advancing: Self.ledger(ordinal: 1, routes: [Self.routeA: Self.state(y: 4)]),
        to: Self.ledger(
          ordinal: 2,
          routes: [
            Self.routeA: Self.state(y: 5),
            Self.routeB: Self.state(y: 0),
          ]
        )
      ) == nil
    )
    // Replaced route (same count, different identity).
    #expect(
      ScrollTranslationFrameLedger.candidate(
        advancing: Self.ledger(ordinal: 1, routes: [Self.routeA: Self.state(y: 4)]),
        to: Self.ledger(ordinal: 2, routes: [Self.routeB: Self.state(y: 5)])
      ) == nil
    )
    // No baseline at all (first presented frame).
    #expect(
      ScrollTranslationFrameLedger.candidate(
        advancing: nil,
        to: Self.ledger(ordinal: 1, routes: [Self.routeA: Self.state(y: 4)])
      ) == nil
    )
  }

  @Test("a band-sized jump produces no candidate")
  func bandSizedJumpProducesNoCandidate() {
    // |dy| == band height: no baseline row survives inside the band.
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(ordinal: 1, routes: [Self.routeA: Self.state(y: 0)]),
      to: Self.ledger(ordinal: 2, routes: [Self.routeA: Self.state(y: 12)])
    )

    #expect(candidate == nil)
  }

  @Test("the band is clamped to the surface")
  func bandIsClampedToSurface() {
    let overhangingViewport = CellRect(
      origin: CellPoint(x: 2, y: 20),
      size: CellSize(width: 40, height: 12)
    )
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: Self.ledger(
        ordinal: 1,
        routes: [Self.routeA: Self.state(y: 4, viewportRect: overhangingViewport)]
      ),
      to: Self.ledger(
        ordinal: 2,
        routes: [Self.routeA: Self.state(y: 5, viewportRect: overhangingViewport)]
      )
    )

    #expect(
      candidate?.band
        == CellRect(
          origin: CellPoint(x: 2, y: 20),
          size: CellSize(width: 40, height: 4)
        )
    )
  }

  // MARK: - Trust latch

  @Test("the presentation trust latch discards the candidate after a writer drop")
  func trustLatchDiscardsCandidateAfterDrop() {
    var session = TerminalPresentationSession()
    let candidate = ScrollTranslationCandidate(
      band: Self.viewport,
      dy: -1,
      baselineFrameOrdinal: 7
    )

    #expect(session.presentationTranslationCandidate(requested: candidate) == candidate)

    // A submitted frame the writer never committed: reconcile rolls the
    // baseline back and clears the one-shot latch.
    session.inFlightFrame = .init(
      sequence: 3,
      surface: RasterSurface(size: .init(width: 4, height: 1), lines: ["AAAA"]),
      transmittedKittyImagesBeforeSubmission: [],
      residentKittyImageDataBeforeSubmission: []
    )
    session.reconcile(lastCommittedSequence: 2)

    #expect(session.presentationTranslationCandidate(requested: candidate) == nil)
    #expect(session.presentationDamage(requested: PresentationDamage(dirtyRows: [0])) == nil)

    // The next plan re-arms the latch after consuming (ignoring) the stale
    // hint — from then on candidates flow again.
    session.requestedDamageTrustsBaseline = true
    #expect(session.presentationTranslationCandidate(requested: candidate) == candidate)
  }

  // MARK: - Wheel-notch integration

  @Test("a wheel notch on a scroll fixture yields a matching candidate")
  func wheelNotchYieldsMatchingCandidate() throws {
    let harness = try ScrollTranslationHarness()
    let mountFrame = try #require(harness.sink.committedSamples.last)
    #expect(mountFrame.translationCandidate == nil, "the mount frame has no baseline to claim")

    harness.scroll(deltaY: 1)
    try harness.render()
    let notchFrame = try #require(harness.sink.committedSamples.last)
    #expect(notchFrame.frameNumber > mountFrame.frameNumber)

    let route = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
    let surfaceBounds = CellRect(origin: .zero, size: harness.terminalSize)
    let candidate = try #require(notchFrame.translationCandidate)
    #expect(candidate.dy == -1, "a one-notch scroll-down slides content up one row")
    #expect(candidate.band == route.viewportRect.intersection(surfaceBounds))
    #expect(candidate.baselineFrameOrdinal == mountFrame.frameNumber)

    let record = FrameRecordDerivation.record(from: .committed(notchFrame))
    let expectedField =
      "dy=-1@rows\(candidate.band.origin.y)..\(candidate.band.maxY)"
    #expect(Self.tsvField("translation_candidate", of: record) == expectedField)

    // A follow-up commit with an unchanged offset — the @State-echo shape —
    // must produce no candidate.
    harness.invalidateRoot()
    try harness.render()
    let echoFrame = try #require(harness.sink.committedSamples.last)
    #expect(echoFrame.frameNumber > notchFrame.frameNumber)
    #expect(echoFrame.translationCandidate == nil)
    let echoRecord = FrameRecordDerivation.record(from: .committed(echoFrame))
    #expect(Self.tsvField("translation_candidate", of: echoRecord) == "-")

    // The next notch claims against the moved frame, not the mount frame.
    harness.scroll(deltaY: 1)
    try harness.render()
    let secondNotch = try #require(harness.sink.committedSamples.last)
    let secondCandidate = try #require(secondNotch.translationCandidate)
    #expect(secondCandidate.dy == -1)
    #expect(secondCandidate.baselineFrameOrdinal == echoFrame.frameNumber)
  }

  /// The rendered value of one column, located by header name rather than by
  /// index, so an inserted column cannot silently shift the assertion.
  private static func tsvField(_ name: String, of record: FrameDiagnosticRecord) -> String? {
    let header = FrameDiagnosticsTSVFormatting.headerFields
    let row = FrameDiagnosticsTSVFormatting.fields(for: record)
    guard let index = header.firstIndex(of: name), index < row.count else {
      return nil
    }
    return row[index]
  }
}

/// A live run-loop session over a plain `ScrollView` with overflowing content:
/// the minimal fixture whose wheel notch moves exactly one scroll route.
@MainActor
private final class ScrollTranslationHarness {
  let sink = RecordingTranslationSink()
  let rootIdentity = testIdentity("ScrollTranslationFixture")
  let terminalSize = CellSize(width: 24, height: 10)
  let runLoop: RunLoop<Int, AnyView>
  private var renderedFrames = 0

  init() throws {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = terminalSize
    let rootIdentity = rootIdentity

    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: RecordingPresentationSurface(surfaceSize: terminalSize),
      terminalInputReader: TranslationInputReader(),
      signalReader: TranslationSignalReader(),
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
                Text("line \(index)")
              }
            }
          }
          .frame(width: 16, height: 8, alignment: .topLeading)
        )
      }
    )
    runLoop.frameSink = sink

    // Mount synchronously, mirroring `RunLoop.run()`'s pre-loop bootstrap.
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

  func invalidateRoot() {
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
  }

  func render() throws {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }
}

@MainActor
private final class RecordingTranslationSink: FrameDiagnosticSink {
  private(set) var committedSamples: [CommittedFrameSample] = []

  nonisolated init() {}

  func record(_ sample: RuntimeFrameSample) {
    if case .committed(let committed) = sample {
      committedSamples.append(committed)
    }
  }
}

private final class TranslationInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class TranslationSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
