import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Shared plumbing for the segmented bordered-button-row journeys (GitHub issue
// SwiftTUI/swift-tui#5). A journey drives a real `RunLoop` with scripted input,
// paces each event on the host presenting a frame (bounded, never a fixed
// sleep), and reads the F13 incremental-vs-fresh oracle through its counter:
// in DEBUG the rasterizer's default policy runs the fresh comparison on every
// incremental raster, and `recordIncrementalRasterMismatchIfCaught` records
// before it decides whether to trap, so disabling the probe's assertion keeps
// the oracle observable without taking the test runner down.

/// Records every presented surface. `Sendable` by construction (immutable
/// configuration plus a `Mutex`-guarded frame list) so the scripted input's
/// task can read the latest frame to aim mouse events.
final class SegmentedRowRecordingHost: PresentationSurface, Sendable {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance = .fallback
  private let frames = Mutex<[RasterSurface]>([])

  init(size: CellSize, capabilityProfile: TerminalCapabilityProfile = .trueColor) {
    self.surfaceSize = size
    self.capabilityProfile = capabilityProfile
  }

  var presentedFrames: [RasterSurface] {
    frames.withLock { $0 }
  }

  var presentedFrameCount: Int {
    frames.withLock { $0.count }
  }

  /// Cell locations of every `glyph` in the most recent presented frame.
  func glyphLocations(of glyph: Character) -> [Point] {
    guard let last = presentedFrames.last else {
      return []
    }
    var points: [Point] = []
    for (row, line) in last.lines.enumerated() {
      for (column, character) in line.enumerated() where character == glyph {
        points.append(Point(CellPoint(x: column, y: row)))
      }
    }
    return points
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frames.withLock { $0.append(surface) }
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

/// One scripted step: its events are computed at emission time against the
/// host, so a later step can aim clicks at glyphs the earlier steps produced.
struct SegmentedRowJourneyStep: Sendable {
  let events: @Sendable (SegmentedRowRecordingHost) -> [InputEvent]

  /// One key press per event.
  static func keys(_ keys: [KeyEvent]) -> Self {
    Self { _ in keys.map { .key(KeyPress($0)) } }
  }

  /// A press/release pair on every `●` glyph of the latest frame, in the
  /// given order.
  static func clickEverySegmentGlyph(reversed: Bool = false) -> Self {
    Self { host in
      let targets = host.glyphLocations(of: "●")
      return (reversed ? targets.reversed() : targets).flatMap { target in
        [
          InputEvent.mouse(.init(kind: .down(.primary), location: target)),
          InputEvent.mouse(.init(kind: .up(.primary), location: target)),
        ]
      }
    }
  }

  /// A press on the first `●` glyph, a move to the last, and a release there.
  static func dragAcrossSegmentGlyphs() -> Self {
    Self { host in
      let targets = host.glyphLocations(of: "●")
      guard let first = targets.first, let last = targets.last else {
        return []
      }
      return [
        .mouse(.init(kind: .down(.primary), location: first)),
        .mouse(.init(kind: .moved, location: last)),
        .mouse(.init(kind: .up(.primary), location: last)),
      ]
    }
  }
}

/// Scripted input that emits each step's events and paces every event on the
/// host presenting a frame (bounded wait), never on a fixed sleep.
final class SegmentedRowJourneyInput: TerminalInputReading {
  typealias Step = SegmentedRowJourneyStep

  /// Upper bound on the wait for a frame after one event. An event that does
  /// not change the frame (a no-op arrow on an unfocused view) must not stall
  /// the journey, so the bound is short; an event that does change it is
  /// released as soon as the host presents.
  static let frameWaitNanoseconds: UInt64 = 400_000_000
  static let framePollNanoseconds: UInt64 = 2_000_000

  private let host: SegmentedRowRecordingHost
  private let steps: [Step]

  init(host: SegmentedRowRecordingHost, steps: [Step]) {
    self.host = host
    self.steps = steps
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    let host = host
    let steps = steps
    return AsyncStream { continuation in
      let task = Task {
        // Let the first frame land before the first event so focus exists.
        await Self.waitForFrame(on: host, after: 0)
        for step in steps {
          for event in step.events(host) {
            let before = host.presentedFrameCount
            continuation.yield(event)
            await Self.waitForFrame(on: host, after: before)
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func waitForFrame(on host: SegmentedRowRecordingHost, after count: Int) async {
    let clock = ContinuousClock()
    let deadline =
      clock.now + .nanoseconds(Int64(AsyncTestTimeouts.scaledNanoseconds(frameWaitNanoseconds)))
    while host.presentedFrameCount <= count, clock.now < deadline {
      try? await Task.sleep(nanoseconds: framePollNanoseconds)
    }
  }
}

final class SegmentedRowEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

@MainActor
final class SegmentedRowDiagnosticSink: FrameDiagnosticSink {
  private(set) var records: [FrameDiagnosticRecord] = []

  func record(_ sample: RuntimeFrameSample) {
    records.append(FrameRecordDerivation.record(from: sample))
  }
}

struct SegmentedRowJourneyResult {
  var frames: [RasterSurface]
  var rasterPaths: [String]
  var rasterReuseBarriers: [[String]]
  var mismatchGrowth: Int
  var mismatchDetail: String?

  var reachedIncrementalRaster: Bool {
    rasterPaths.contains(Rasterizer.RasterPath.incremental.rawValue)
  }

  var summary: String {
    """
    frames=\(frames.count) paths=\(rasterPaths) barriers=\(rasterReuseBarriers) \
    mismatch=\(mismatchGrowth) detail=\(mismatchDetail ?? "-")
    """
  }

  var renderedFrames: String {
    frames.enumerated().map { index, frame in
      "--- frame \(index) ---\n" + frame.lines.joined(separator: "\n")
    }.joined(separator: "\n")
  }
}

/// Runs `root` through a real `RunLoop` with the scripted `steps` and reports
/// the raster paths and the F13 oracle's counter growth.
@MainActor
func runSegmentedRowJourney<Root: View>(
  rootIdentity: Identity,
  terminalSize: CellSize,
  capabilityProfile: TerminalCapabilityProfile = .trueColor,
  steps: [SegmentedRowJourneyInput.Step],
  root: @escaping () -> Root
) async throws -> SegmentedRowJourneyResult {
  let probeEnabled = SoundnessProbeConfiguration.isEnabled
  let before = SoundnessCounterSnapshot.current()
  defer {
    SoundnessProbeConfiguration.isEnabled = probeEnabled
  }
  // Observe the oracle through its counter rather than its DEBUG trap.
  SoundnessProbeConfiguration.isEnabled = false

  let host = SegmentedRowRecordingHost(size: terminalSize, capabilityProfile: capabilityProfile)
  var environment = EnvironmentValues()
  environment.terminalSize = terminalSize
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: host,
    terminalInputReader: SegmentedRowJourneyInput(host: host, steps: steps),
    signalReader: SegmentedRowEmptySignals(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [rootIdentity]
    ),
    environmentValues: environment,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in root() }
  )
  let sink = SegmentedRowDiagnosticSink()
  runLoop.frameSink = sink
  _ = try await runLoop.run()

  let after = SoundnessCounterSnapshot.current()
  return SegmentedRowJourneyResult(
    frames: host.presentedFrames,
    rasterPaths: sink.records.map(\.rasterPath),
    rasterReuseBarriers: sink.records.map(\.rasterReuseBarriers),
    mismatchGrowth: after.rasterDamageMismatchCount - before.rasterDamageMismatchCount,
    mismatchDetail: after.rasterDamageMismatchCount == before.rasterDamageMismatchCount
      ? nil
      : after.lastViolationDetailByKind["raster-damage"]
  )
}

// MARK: - The reported view

/// The segmented-control-style row from GitHub issue SwiftTUI/swift-tui#5,
/// verbatim in shape: `.bordered` Buttons whose labels swap text and bold on
/// selection change, under a focus-ring `strokeBorder` overlay, arrowed via
/// `onKeyPress` on the focusable container.
enum SegmentedRowOption: String, CaseIterable, Identifiable, Sendable {
  case red, green, blue
  var id: String { rawValue }
  var color: Color {
    switch self {
    case .red: .red
    case .green: .green
    case .blue: .blue
    }
  }
}

struct SegmentedRowPicker: View {
  @Binding var selection: SegmentedRowOption
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 0) {
      ForEach(SegmentedRowOption.allCases) { option in
        let isSelected = option == selection
        Button {
          selection = option
        } label: {
          Text(isSelected ? "[●]" : " ● ")
            .foregroundStyle(option.color)
            .bold(isSelected)
        }
        .buttonStyle(.bordered)
        .focusable(false)
      }
    }
    .padding(.init(horizontal: 1, vertical: 0))
    .overlay {
      RoundedRectangle(cornerRadius: 1).strokeBorder(
        isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
        style: isFocused ? .heavy : .init()
      )
    }
    .focusable()
    .focused($isFocused)
    .onKeyPress(.key(.arrowLeft)) { _ in
      move(-1)
      return .handled
    }
    .onKeyPress(.key(.arrowRight)) { _ in
      move(1)
      return .handled
    }
  }

  private func move(_ delta: Int) {
    let all = SegmentedRowOption.allCases
    guard let index = all.firstIndex(of: selection) else { return }
    selection = all[(index + delta + all.count) % all.count]
  }
}
