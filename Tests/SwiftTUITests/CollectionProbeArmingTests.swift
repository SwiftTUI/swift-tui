import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// WP-4: the collection magnitude probes are armable outside DEBUG and are
/// sampled per committed frame into `realized_rows` / `list_layout_derivations`.
///
/// These counters exist to make a millisecond readable. A scrolling collection
/// whose `resolve_ms` doubled either realized twice the rows or paid twice per
/// row, and nothing else in `frames.tsv` separates those two stories.
///
/// The suite is `@MainActor` + `.serialized`, matching every other probe suite:
/// the probes are process-global, and a synchronous main-actor body cannot
/// interleave with another suite's. The disarming cases restore the latches
/// through `defer` so a failure cannot leave a later suite reading a disarmed
/// counter.
@MainActor
@Suite(.serialized)
struct CollectionProbeArmingTests {
  // MARK: - T-30

  @Test("An armed run reports realized rows and list derivations for the frame")
  func armedRunPopulatesBothColumns() throws {
    let harness = try CollectionProbeHarness()

    harness.scroll(deltaY: 1)
    try harness.render()

    let frame = try #require(harness.sink.committedSamples.last)
    let realizedRows = try #require(
      frame.collectionProbes.realizedRows,
      "armed run reported no realized-row measurement"
    )
    let derivations = try #require(
      frame.collectionProbes.listLayoutDerivations,
      "armed run reported no list-derivation measurement"
    )
    #expect(realizedRows > 0, "a scrolled list frame realized no rows at all")
    #expect(derivations > 0, "a scrolled list frame derived no visible layout")

    let record = FrameRecordDerivation.record(from: .committed(frame))
    #expect(record.realizedRowCount == realizedRows)
    #expect(record.listLayoutDerivationCount == derivations)
    #expect(Self.tsvField("realized_rows", of: record) == String(realizedRows))
    #expect(Self.tsvField("list_layout_derivations", of: record) == String(derivations))
  }

  @Test("A disarmed run reports no measurement rather than a measurement of zero")
  func disarmedRunLeavesBothColumnsEmpty() throws {
    let armedRealization = IndexedChildRealizationProbe.isArmed
    let armedDerivation = ListLayoutDerivationProbe.isArmed
    defer {
      IndexedChildRealizationProbe.isArmed = armedRealization
      ListLayoutDerivationProbe.isArmed = armedDerivation
    }
    IndexedChildRealizationProbe.isArmed = false
    ListLayoutDerivationProbe.isArmed = false

    let harness = try CollectionProbeHarness()
    harness.scroll(deltaY: 1)
    try harness.render()

    let frame = try #require(harness.sink.committedSamples.last)
    #expect(frame.collectionProbes.realizedRows == nil)
    #expect(frame.collectionProbes.listLayoutDerivations == nil)

    let record = FrameRecordDerivation.record(from: .committed(frame))
    #expect(record.realizedRowCount == nil)
    #expect(record.listLayoutDerivationCount == nil)
    // The distinction this whole design turns on: a disarmed run must not be
    // readable as a collection that realized nothing, because "0 rows
    // realized" is what a perfectly windowed collection reports.
    #expect(Self.tsvField("realized_rows", of: record) == "-")
    #expect(Self.tsvField("list_layout_derivations", of: record) == "-")
  }

  // MARK: - T-31

  @Test("Consecutive frames report per-frame counts, not a running total")
  func frameHeadResetKeepsCountsPerFrame() throws {
    let harness = try CollectionProbeHarness()

    harness.scroll(deltaY: 1)
    try harness.render()
    let first = try #require(harness.sink.committedSamples.last)
    let firstRows = try #require(first.collectionProbes.realizedRows)
    let firstDerivations = try #require(first.collectionProbes.listLayoutDerivations)
    #expect(firstRows > 0)

    harness.scroll(deltaY: 1)
    try harness.render()
    let second = try #require(harness.sink.committedSamples.last)
    #expect(second.frameNumber > first.frameNumber, "the second scroll committed no new frame")

    // Both notches do the same work on this fixture, so equality is the
    // assertion with teeth: drop the frame-head reset and the second frame
    // reports the sum of both, which is neither equal nor plausible.
    #expect(second.collectionProbes.realizedRows == firstRows)
    #expect(second.collectionProbes.listLayoutDerivations == firstDerivations)
  }

  /// The rendered value of one column, located by header name rather than by
  /// index — the row and the header are built by the same formatter, and
  /// hard-coding a position would silently follow any column inserted before
  /// it.
  private static func tsvField(_ name: String, of record: FrameDiagnosticRecord) -> String? {
    let header = FrameDiagnosticsTSVFormatting.headerFields
    let row = FrameDiagnosticsTSVFormatting.fields(for: record)
    guard let index = header.firstIndex(of: name), index < row.count else {
      return nil
    }
    return row[index]
  }
}

/// A live run-loop session over a `List` of `ForEach` rows: the shape that
/// drives both probes at once — `ForEach` realizes rows, and the list derives a
/// visible layout from them.
@MainActor
private final class CollectionProbeHarness {
  let sink = RecordingCollectionProbeSink()
  let rootIdentity = testIdentity("CollectionProbeFixture")
  let runLoop: RunLoop<Int, AnyView>
  private var renderedFrames = 0

  init() throws {
    let terminalSize = CellSize(width: 24, height: 10)
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = terminalSize
    let rootIdentity = rootIdentity

    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: RecordingPresentationSurface(surfaceSize: terminalSize),
      terminalInputReader: CollectionProbeInputReader(),
      signalReader: CollectionProbeSignalReader(),
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
          List {
            ForEach(0..<40) { index in
              Text("Row \(index)")
            }
          }
          .frame(width: 20, height: 8, alignment: .topLeading)
        )
      }
    )
    runLoop.frameSink = sink

    // Mount synchronously, mirroring `RunLoop.run()`'s pre-loop bootstrap.
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    sink.reset()
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

@MainActor
private final class RecordingCollectionProbeSink: FrameDiagnosticSink {
  private(set) var committedSamples: [CommittedFrameSample] = []

  nonisolated init() {}

  func record(_ sample: RuntimeFrameSample) {
    if case .committed(let committed) = sample {
      committedSamples.append(committed)
    }
  }

  func reset() {
    committedSamples.removeAll()
  }
}

private final class CollectionProbeInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class CollectionProbeSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
