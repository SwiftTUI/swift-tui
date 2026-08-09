import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// End-to-end proof that a real composed runtime reaches the incremental
/// rasterizer.
///
/// This is the regression that keeps the tier from going dormant again. It was
/// dormant for the whole of its existence: `FrameTailPresentationDamageResolver`
/// barriered on *every* frame of *every* app, so `rasterizeDrawTree` always got
/// `damage: nil` and the four TermUIPerf lanes checked in to measure the
/// incremental win measured a flat zero. Nothing in the codebase reported that
/// — establishing it required hand-patching the rasterizer — which is why the
/// path is now a committed frame diagnostic and why this test asserts on it.
@MainActor
@Suite("Incremental raster reachability")
struct IncrementalRasterReachabilityTests {
  @Test("a second frame of a composed runtime rasterizes incrementally")
  func secondFrameRasterizesIncrementally() throws {
    let rootIdentity = testIdentity("IncrementalRasterReachability", "Root")
    let sink = RecordingFrameDiagnosticSink()
    let terminal = IncrementalRasterRecordingHost(
      surfaceSize: .init(width: 40, height: 6)
    )
    let scheduler = FrameScheduler()
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: IncrementalRasterEmptyKeyReader(),
      signalReader: IncrementalRasterEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 40, height: 6),
      viewBuilder: { _, _ in IncrementalRasterProbeView() }
    )
    runLoop.frameSink = sink

    var renderedFrames = 0
    scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(terminal.frames.last?.contains("count 0") == true)

    // Click the button: one leaf's text changes, the rest of the surface is
    // untouched. That is precisely the shape the incremental rasterizer exists
    // for, and precisely the shape that barriered before the damage producer
    // was rebuilt on a draw-tree diff.
    let point = try #require(
      terminal.centerOfText("bump"),
      "could not find 'bump' in frame:\n\(terminal.frames.last ?? "")"
    )
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil
    )
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil
    )
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(terminal.frames.last?.contains("count 1") == true)

    let paths = sink.records.map(\.rasterPath)
    #expect(
      paths.contains(Rasterizer.RasterPath.incremental.rawValue),
      "no frame reached the incremental rasterizer; paths were \(paths), barriers were \(sink.records.map(\.rasterReuseBarriers))"
    )
    // A repaired frame means the F13 oracle caught incomplete damage. Asserting
    // "the output looks right" would not catch that: DEBUG's verify policy
    // silently repairs the surface, so the wrong damage only ships in release.
    #expect(!paths.contains(Rasterizer.RasterPath.incrementalRepaired.rawValue))
  }

  @Test("a wheel notch on a root-adjacent scroll view rasterizes incrementally")
  func rootAdjacentScrollViewWheelNotchRasterizesIncrementally() throws {
    // Characterization for scroll-latency R1.2 (plan 2026-08-08-001): when the
    // ScrollView is the root view's direct child, the wheel path's ancestor
    // spine climb used to insert `rootIdentity` into the invalidation set
    // (the `identities.count > 1` root guard never fired on the first
    // iteration), tripping the `root_invalidated` raster-reuse barrier — a
    // shallow app took a full fresh re-raster on every notch.
    let rootIdentity = testIdentity("IncrementalRasterReachability", "ScrollRoot")
    let sink = RecordingFrameDiagnosticSink()
    let terminal = IncrementalRasterRecordingHost(
      surfaceSize: .init(width: 40, height: 8)
    )
    let scheduler = FrameScheduler()
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: IncrementalRasterEmptyKeyReader(),
      signalReader: IncrementalRasterEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 40, height: 8),
      viewBuilder: { _, _ in RootAdjacentScrollProbeView() }
    )
    runLoop.frameSink = sink

    var renderedFrames = 0
    scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(terminal.frames.last?.contains("row 0") == true)

    let point = try #require(
      terminal.centerOfText("row 1"),
      "could not find 'row 1' in frame:\n\(terminal.frames.last ?? "")"
    )
    #expect(
      runLoop.handle(
        RuntimeEvent.input(
          InputEvent.mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: point))
        )
      ) == nil
    )
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    // The notch must actually have scrolled: the top row leaves the viewport.
    #expect(terminal.frames.last?.contains("row 0") == false)

    let scrollRecord = try #require(sink.records.last)
    // The R3.2b translation blit, when armed, reports the incremental path
    // with served band rows; both are the incremental tier this pin guards.
    #expect(
      scrollRecord.rasterPath == Rasterizer.RasterPath.incremental.rawValue
        || scrollRecord.rasterPath == Rasterizer.RasterPath.incrementalTranslated.rawValue,
      "scroll frame path was \(scrollRecord.rasterPath), barriers \(scrollRecord.rasterReuseBarriers)"
    )
    #expect(!scrollRecord.rasterReuseBarriers.contains("root_invalidated"))
    // Bounded damage, and no F13 repair (see the sibling test's rationale).
    #expect(scrollRecord.damageRowCount != nil)
    #expect(scrollRecord.rasterPath != Rasterizer.RasterPath.incrementalRepaired.rawValue)
  }

  @Test("a wheel notch on a deeply nested scroll view invalidates the route alone")
  func nestedScrollViewWheelNotchInvalidatesRouteOnly() throws {
    // Characterization for scroll-latency R1.6 (plan 2026-08-08-001): the wheel
    // dispatch invalidates ONLY the resolved scroll route — no lexical ancestor
    // spine. Ancestors already re-derive at the layout tiers through
    // has-invalidated-descendant and affects-indexed-source-within denial, so
    // spine membership added no soundness; it only re-ran the spine containers'
    // bodies at the resolve tier and defeated pointer-fast equivalence above
    // the route. Every other scroll entry path (keyboard, momentum registry
    // scrollBy, scrollTo/reveal, indicator drag) already invalidates through
    // the binding write alone — route-only.
    //
    // The under-invalidation oracle is the F13 verify policy: DEBUG repairs
    // incomplete damage and stamps the frame `incrementalRepaired`, so the
    // "no repair" assertion fails if route-only invalidation ever
    // under-damages this nested shape.
    let rootIdentity = testIdentity("IncrementalRasterReachability", "NestedScrollRoot")
    let sink = RecordingFrameDiagnosticSink()
    let terminal = IncrementalRasterRecordingHost(
      surfaceSize: .init(width: 40, height: 10)
    )
    let scheduler = FrameScheduler()
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: IncrementalRasterEmptyKeyReader(),
      signalReader: IncrementalRasterEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 40, height: 10),
      viewBuilder: { _, _ in NestedSpineScrollProbeView() }
    )
    runLoop.frameSink = sink

    var renderedFrames = 0
    scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(terminal.frames.last?.contains("row 0") == true)

    let point = try #require(
      terminal.centerOfText("row 1"),
      "could not find 'row 1' in frame:\n\(terminal.frames.last ?? "")"
    )
    #expect(
      runLoop.handle(
        RuntimeEvent.input(
          InputEvent.mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: point))
        )
      ) == nil
    )

    // Route-only: exactly one pending identity (the resolved scroll route;
    // the binding write's reader-attributed invalidation targets the same
    // identity), never the root. The pre-R1.6 spine climb inserted every
    // lexical ancestor below the root, so this nested fixture pinned >= 3.
    let pending = scheduler.pendingInvalidatedIdentities
    #expect(
      pending.count == 1,
      "wheel invalidation set was \(pending.map(\.path).sorted())"
    )
    #expect(!pending.contains(rootIdentity))

    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    // The notch must actually have scrolled the nested viewport.
    #expect(terminal.frames.last?.contains("row 0") == false)

    let scrollRecord = try #require(sink.records.last)
    // The R3.2b translation blit, when armed, reports the incremental path
    // with served band rows; both are the incremental tier this pin guards.
    #expect(
      scrollRecord.rasterPath == Rasterizer.RasterPath.incremental.rawValue
        || scrollRecord.rasterPath == Rasterizer.RasterPath.incrementalTranslated.rawValue,
      "scroll frame path was \(scrollRecord.rasterPath), barriers \(scrollRecord.rasterReuseBarriers)"
    )
    #expect(scrollRecord.damageRowCount != nil)
    #expect(scrollRecord.rasterPath != Rasterizer.RasterPath.incrementalRepaired.rawValue)
  }
}

// MARK: - Fixtures

private struct IncrementalRasterProbeView: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("bump") { count += 1 }
      Text("count \(count)")
      Text("static row")
    }
  }
}

/// A deep-spine app shape: real lexical containers sit between the root and
/// the scroll view, so the route identity has non-root structural ancestors —
/// the shape whose wheel invalidation set the pre-R1.6 spine climb widened.
private struct NestedSpineScrollProbeView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("chrome")
      VStack(alignment: .leading, spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<24) { row in
              Text("row \(row)")
            }
          }
        }
      }
      .padding(1)
    }
  }
}

/// A shallow real app shape: the scroll view resolves as the root node's
/// direct child, so the wheel route's spine climb reaches `rootIdentity` on
/// its first step.
private struct RootAdjacentScrollProbeView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("title")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<24) { row in
            Text("row \(row)")
          }
        }
      }
    }
  }
}

@MainActor
private final class RecordingFrameDiagnosticSink: FrameDiagnosticSink {
  private(set) var records: [FrameDiagnosticRecord] = []

  func record(_ sample: RuntimeFrameSample) {
    records.append(FrameRecordDerivation.record(from: sample))
  }
}

private final class IncrementalRasterRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(String(rendered.filter { $0 != "\r" }))
    lastPresentedSurface = surface
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(String(output.filter { $0 != "\r" }))
  }

  func centerOfText(_ target: String) -> Point? {
    guard let surface = lastPresentedSurface else {
      return nil
    }
    for row in surface.lines.indices {
      let line = surface.lines[row]
      guard let range = line.range(of: target) else {
        continue
      }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(x: Double(column) + 0.5, y: Double(row) + 0.5)
    }
    return nil
  }
}

private final class IncrementalRasterEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class IncrementalRasterEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
