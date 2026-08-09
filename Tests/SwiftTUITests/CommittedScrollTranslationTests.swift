import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// R3.2a: the committed-products translation candidate — the tail-time
/// sibling of the present-time R2.2 candidate, derived from committed placed
/// trees instead of live registry offsets.
///
/// These tests pin the route-table extraction from placed trees, the
/// candidate derivation rules (exactly one moved route, rigid vertical
/// anchor shift, unchanged viewport), the surface clamp, and the end-to-end
/// wheel-notch agreement with the present-time candidate through a live run
/// loop (including the `translation_committed` frames.tsv verdict column).
@MainActor
@Suite
struct CommittedScrollTranslationTests {
  // MARK: - Fixtures

  private static let routeA = testIdentity("Fixture", "ScrollA")
  private static let routeB = testIdentity("Fixture", "ScrollB")
  private static let contentA = testIdentity("Fixture", "ScrollA", "Content")
  private static let viewport = CellRect(
    origin: CellPoint(x: 2, y: 3),
    size: CellSize(width: 40, height: 12)
  )

  /// A plain scroll-shaped route: one node with a scroll role whose single
  /// content child is placed at `viewportOrigin − offset`.
  private static func scrollRouteTree(
    routeIdentity: Identity = routeA,
    contentIdentity: Identity = contentA,
    viewportRect: CellRect = viewport,
    offsetY: Int,
    offsetX: Int = 0,
    extraChildren: [PlacedNode] = []
  ) -> PlacedNode {
    let content = PlacedNode(
      identity: contentIdentity,
      bounds: CellRect(
        origin: CellPoint(
          x: viewportRect.origin.x - offsetX,
          y: viewportRect.origin.y - offsetY
        ),
        size: CellSize(width: viewportRect.size.width, height: 40)
      )
    )
    let route = PlacedNode(
      identity: routeIdentity,
      bounds: viewportRect,
      children: [content] + extraChildren,
      semanticMetadata: SemanticMetadata(scrollRole: .scrollView)
    )
    return PlacedNode(
      identity: testIdentity("Fixture", "Root"),
      bounds: CellRect(origin: .zero, size: CellSize(width: 80, height: 24)),
      children: [route]
    )
  }

  private static func table(_ root: PlacedNode) -> CommittedScrollRouteTable {
    CommittedScrollRouteTable(placedRoot: root)
  }

  // MARK: - Extraction

  @Test("extraction records the route's viewport rect and child anchors")
  func extractionRecordsRouteState() throws {
    let table = Self.table(Self.scrollRouteTree(offsetY: 4))

    let state = try #require(table.routes[Self.routeA])
    #expect(state.viewportRect == Self.viewport)
    #expect(
      state.contentAnchors == [
        .placedChild(Self.contentA): CellPoint(x: 2, y: -1)
      ]
    )
    #expect(!table.hasDuplicateRouteIdentities)
  }

  @Test("a route-free tree extracts an empty table")
  func routeFreeTreeExtractsEmptyTable() {
    let root = PlacedNode(
      identity: testIdentity("Fixture", "Root"),
      bounds: CellRect(origin: .zero, size: CellSize(width: 80, height: 24))
    )
    #expect(Self.table(root).routes.isEmpty)
  }

  // MARK: - Candidate derivation

  @Test("a one-notch content-child shift produces the candidate")
  func contentChildShiftProducesCandidate() {
    let candidate = CommittedScrollRouteTable.candidate(
      advancing: Self.table(Self.scrollRouteTree(offsetY: 4)),
      to: Self.table(Self.scrollRouteTree(offsetY: 5))
    )

    // Offset +1 (user scrolled down) slides content UP one row on screen.
    #expect(
      candidate
        == CommittedScrollTranslation(
          routeIdentity: Self.routeA,
          band: Self.viewport,
          dy: -1
        )
    )
  }

  @Test("a scroll-up shift produces a positive dy")
  func scrollUpShiftProducesPositiveDy() {
    let candidate = CommittedScrollRouteTable.candidate(
      advancing: Self.table(Self.scrollRouteTree(offsetY: 5)),
      to: Self.table(Self.scrollRouteTree(offsetY: 2))
    )
    #expect(candidate?.dy == 3)
  }

  @Test("an unmoved frame produces no candidate")
  func unmovedFrameProducesNoCandidate() {
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(offsetY: 4)),
        to: Self.table(Self.scrollRouteTree(offsetY: 4))
      ) == nil
    )
  }

  @Test("no baseline produces no candidate")
  func noBaselineProducesNoCandidate() {
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: nil,
        to: Self.table(Self.scrollRouteTree(offsetY: 4))
      ) == nil
    )
  }

  @Test("a horizontal component produces no candidate")
  func horizontalComponentProducesNoCandidate() {
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(offsetY: 4)),
        to: Self.table(Self.scrollRouteTree(offsetY: 5, offsetX: 1))
      ) == nil
    )
  }

  @Test("a viewport-rect change on the moved route produces no candidate")
  func viewportChangeProducesNoCandidate() {
    let movedViewport = CellRect(
      origin: CellPoint(x: 2, y: 4),
      size: CellSize(width: 40, height: 12)
    )
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(offsetY: 4)),
        to: Self.table(Self.scrollRouteTree(viewportRect: movedViewport, offsetY: 5))
      ) == nil
    )
  }

  @Test("a non-rigid shift (one anchor pinned) produces no candidate")
  func nonRigidShiftProducesNoCandidate() {
    let pinned = PlacedNode(
      identity: testIdentity("Fixture", "ScrollA", "Pinned"),
      bounds: CellRect(
        origin: CellPoint(x: 41, y: 3),
        size: CellSize(width: 1, height: 12)
      )
    )
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(offsetY: 4, extraChildren: [pinned])),
        to: Self.table(Self.scrollRouteTree(offsetY: 5, extraChildren: [pinned]))
      ) == nil
    )
  }

  @Test("a shift at least as tall as the viewport produces no candidate")
  func viewportSizedJumpProducesNoCandidate() {
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(offsetY: 0)),
        to: Self.table(Self.scrollRouteTree(offsetY: 12))
      ) == nil
    )
  }

  @Test("no shared anchors produces no candidate")
  func noSharedAnchorsProducesNoCandidate() {
    let replacement = Self.scrollRouteTree(
      contentIdentity: testIdentity("Fixture", "ScrollA", "OtherContent"),
      offsetY: 5
    )
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(offsetY: 4)),
        to: Self.table(replacement)
      ) == nil
    )
  }

  @Test("two moved routes produce no candidate")
  func twoMovedRoutesProduceNoCandidate() {
    let otherViewport = CellRect(
      origin: CellPoint(x: 50, y: 3),
      size: CellSize(width: 20, height: 12)
    )
    func twoRouteTree(offsetA: Int, offsetB: Int) -> PlacedNode {
      var root = Self.scrollRouteTree(offsetY: offsetA)
      let routeB = Self.scrollRouteTree(
        routeIdentity: Self.routeB,
        contentIdentity: testIdentity("Fixture", "ScrollB", "Content"),
        viewportRect: otherViewport,
        offsetY: offsetB
      ).children[0]
      root.children.append(routeB)
      return root
    }
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(twoRouteTree(offsetA: 4, offsetB: 9)),
        to: Self.table(twoRouteTree(offsetA: 5, offsetB: 10))
      ) == nil
    )
    // One moved, one unmoved: the candidate exists and names the mover.
    let candidate = CommittedScrollRouteTable.candidate(
      advancing: Self.table(twoRouteTree(offsetA: 4, offsetB: 9)),
      to: Self.table(twoRouteTree(offsetA: 5, offsetB: 9))
    )
    #expect(candidate?.routeIdentity == Self.routeA)
    #expect(candidate?.dy == -1)
  }

  @Test("a route-set change produces no candidate")
  func routeSetChangeProducesNoCandidate() {
    let replaced = Self.scrollRouteTree(
      routeIdentity: Self.routeB,
      contentIdentity: testIdentity("Fixture", "ScrollB", "Content"),
      offsetY: 5
    )
    #expect(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(offsetY: 4)),
        to: Self.table(replaced)
      ) == nil
    )
  }

  @Test("the surface clamp trims the band and re-validates the shift")
  func surfaceClampTrimsBand() throws {
    let overhanging = CellRect(
      origin: CellPoint(x: 2, y: 20),
      size: CellSize(width: 40, height: 12)
    )
    let candidate = try #require(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(viewportRect: overhanging, offsetY: 4)),
        to: Self.table(Self.scrollRouteTree(viewportRect: overhanging, offsetY: 5))
      )
    )
    let clamped = candidate.clamped(toSurface: CellSize(width: 80, height: 24))
    #expect(
      clamped?.band
        == CellRect(
          origin: CellPoint(x: 2, y: 20),
          size: CellSize(width: 40, height: 4)
        )
    )
    // A clamped band shorter than the shift cannot host a translation.
    let jumped = try #require(
      CommittedScrollRouteTable.candidate(
        advancing: Self.table(Self.scrollRouteTree(viewportRect: overhanging, offsetY: 0)),
        to: Self.table(Self.scrollRouteTree(viewportRect: overhanging, offsetY: 6))
      )
    )
    #expect(jumped.clamped(toSurface: CellSize(width: 80, height: 24)) == nil)
  }

  // MARK: - Wheel-notch integration

  @Test("a wheel notch commits a candidate that agrees with the present-time one")
  func wheelNotchCommitsAgreeingCandidate() throws {
    let harness = try CommittedTranslationHarness()
    let mountFrame = try #require(harness.sink.committedSamples.last)
    #expect(mountFrame.committedTranslation == nil, "the mount frame has no baseline to claim")
    let mountRecord = FrameRecordDerivation.record(from: .committed(mountFrame))
    #expect(Self.tsvField("translation_committed", of: mountRecord) == "-")

    harness.scroll(deltaY: 1)
    try harness.render()
    let notchFrame = try #require(harness.sink.committedSamples.last)
    #expect(notchFrame.frameNumber > mountFrame.frameNumber)

    let committed = try #require(notchFrame.committedTranslation)
    let presentTime = try #require(notchFrame.translationCandidate)
    #expect(committed.dy == -1, "a one-notch scroll-down slides content up one row")
    #expect(committed.dy == presentTime.dy)
    #expect(committed.band == presentTime.band)

    let record = FrameRecordDerivation.record(from: .committed(notchFrame))
    #expect(Self.tsvField("translation_committed", of: record) == "agree")

    // A follow-up commit with an unchanged offset — the @State-echo shape —
    // must produce no committed candidate either.
    harness.invalidateRoot()
    try harness.render()
    let echoFrame = try #require(harness.sink.committedSamples.last)
    #expect(echoFrame.committedTranslation == nil)
    let echoRecord = FrameRecordDerivation.record(from: .committed(echoFrame))
    #expect(Self.tsvField("translation_committed", of: echoRecord) == "-")

    // The next notch claims against the echo frame's committed products.
    harness.scroll(deltaY: 1)
    try harness.render()
    let secondNotch = try #require(harness.sink.committedSamples.last)
    let secondCommitted = try #require(secondNotch.committedTranslation)
    #expect(secondCommitted.dy == -1)
    let secondRecord = FrameRecordDerivation.record(from: .committed(secondNotch))
    #expect(Self.tsvField("translation_committed", of: secondRecord) == "agree")
  }

  @Test("a list wheel notch commits a line-anchored candidate that agrees")
  func listWheelNotchCommitsAgreeingCandidate() throws {
    let harness = try CommittedTranslationHarness(fixture: .list)
    _ = try #require(harness.sink.committedSamples.last)

    // The first notch pins the anchor; scroll twice so at least one notch
    // moves the window from a stored-anchor baseline.
    harness.scroll(deltaY: 1)
    try harness.render()
    harness.scroll(deltaY: 1)
    try harness.render()
    let notchFrame = try #require(harness.sink.committedSamples.last)

    let committed = try #require(notchFrame.committedTranslation)
    let presentTime = try #require(notchFrame.translationCandidate)
    #expect(committed.dy == presentTime.dy)
    #expect(committed.band == presentTime.band)
    let record = FrameRecordDerivation.record(from: .committed(notchFrame))
    #expect(Self.tsvField("translation_committed", of: record) == "agree")
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

/// A live run-loop session over a scrollable fixture, mirroring
/// `ScrollTranslationHarness` (R2.2) so both candidate currencies can be
/// compared on the same frames.
@MainActor
private final class CommittedTranslationHarness {
  enum Fixture {
    case plainScrollView
    case list
  }

  let sink = RecordingCommittedTranslationSink()
  let rootIdentity = testIdentity("CommittedTranslationFixture")
  let terminalSize = CellSize(width: 24, height: 10)
  let runLoop: RunLoop<Int, AnyView>
  private var renderedFrames = 0

  init(fixture: Fixture = .plainScrollView) throws {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = terminalSize
    let rootIdentity = rootIdentity

    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: RecordingPresentationSurface(surfaceSize: terminalSize),
      terminalInputReader: CommittedTranslationInputReader(),
      signalReader: CommittedTranslationSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: ScopedMapper { _ in
        switch fixture {
        case .plainScrollView:
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
        case .list:
          AnyView(
            List(0..<40, id: \.self) { index in
              Text("row \(index)")
            }
            .frame(width: 20, height: 9, alignment: .topLeading)
          )
        }
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
private final class RecordingCommittedTranslationSink: FrameDiagnosticSink {
  private(set) var committedSamples: [CommittedFrameSample] = []

  nonisolated init() {}

  func record(_ sample: RuntimeFrameSample) {
    if case .committed(let committed) = sample {
      committedSamples.append(committed)
    }
  }
}

private final class CommittedTranslationInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class CommittedTranslationSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
