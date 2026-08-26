import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// MARK: - Run-loop harness for the `.task`-driven animators

/// Drives a view through a real `RunLoop` so the `.task` driver, state
/// writes, and the animation controller all take part. Shared by the
/// `KeyframeAnimator` and `PhaseAnimator` runtime suites.

@MainActor
final class AnimatorRuntimeHarness<Content: View> {
  private let terminal: AnimatorRecordingHost
  let runLoop: SwiftTUIRuntime.RunLoop<Int, Content>
  private let scheduler: FrameScheduler
  private let rootIdentity: Identity
  private var renderedFrames = 0
  private var didShutdown = false
  private let schedulerWake = MainActorConditionSignal()
  private let frameSink = AnimatorFrameDiagnosticSink()

  init(
    size: CellSize = .init(width: 40, height: 6),
    motion: RuntimeConfiguration.MotionMode = .normal,
    rootLabel: String = "AnimatorRuntimeRoot",
    @ViewBuilder content: @escaping () -> Content
  ) throws {
    let rootIdentity = testIdentity(rootLabel)
    self.rootIdentity = rootIdentity
    let terminal = AnimatorRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: AnimatorEmptyKeyReader(),
      signalReader: AnimatorEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      runtimeConfiguration: RuntimeConfiguration(motion: motion),
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: ScopedMapper { _ in content() }
    )
    focusTracker.invalidator = scheduler
    runLoop.frameSink = frameSink
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler

    let schedulerWake = self.schedulerWake
    scheduler.setWakeHandler {
      Task { @MainActor in
        schedulerWake.notify()
      }
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String { terminal.frames.last ?? "" }

  /// Every rendered frame's diagnostic record, oldest first.
  var frameRecords: [FrameDiagnosticRecord] { frameSink.records }

  var activeTaskCount: Int {
    runLoop.lifecycleCoordinator.activeTaskCount
  }

  func shutdown() {
    guard !didShutdown else { return }
    didShutdown = true
    scheduler.setWakeHandler(nil)
    runLoop.lifecycleCoordinator.shutdown()
  }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return terminal.frames.last ?? ""
  }

  @discardableResult
  func clickText(_ label: String) throws -> String {
    let point = try #require(
      terminal.centerOfText(label),
      "could not find '\(label)' in frame:\n\(frame)"
    )
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil
    )
    return try render()
  }

  /// Renders pending frames as they arrive until `condition` holds, failing
  /// after `timeout` of wall clock so a stalled driver cannot hang the suite.
  func wait(
    until condition: @escaping @MainActor () -> Bool,
    timeout: Duration = .seconds(8)
  ) async throws {
    let deadline = MonotonicInstant.now().advanced(by: timeout)
    while !condition() {
      let remaining = MonotonicInstant.now().duration(to: deadline)
      guard remaining > .zero else {
        throw AnimatorHarnessTimeout(frame: frame)
      }
      await awaitPendingFrame(within: remaining)
      _ = try render()
    }
  }

  /// Renders whatever arrives for `duration` of wall clock, then returns.
  func hold(for duration: Duration) async throws {
    let deadline = MonotonicInstant.now().advanced(by: duration)
    while true {
      let remaining = MonotonicInstant.now().duration(to: deadline)
      guard remaining > .zero else { return }
      await awaitPendingFrame(within: remaining)
      _ = try render()
    }
  }

  /// Suspends until the scheduler has a pending frame or `limit` elapses.
  /// The wait is signal-driven (the scheduler's wake); the Support deadline
  /// event is only the failure bound, and the signal resumes on cancellation.
  private func awaitPendingFrame(within limit: Duration) async {
    let deadline = AsyncEvent.firing(after: limit)
    let waiter = AnimatorFrameSignalWaiter(wake: schedulerWake, scheduler: scheduler)
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await waiter.awaitPendingFrame() }
      group.addTask { await deadline.wait() }
      await group.next()
      group.cancelAll()
    }
  }
}

/// Non-generic, main-actor-isolated (so implicitly `Sendable`) waiter the
/// harness hands to its task group: the generic harness itself carries a
/// non-`Sendable` metatype that an isolated child task may not capture.
@MainActor
final class AnimatorFrameSignalWaiter {
  private let wake: MainActorConditionSignal
  private let scheduler: FrameScheduler

  init(wake: MainActorConditionSignal, scheduler: FrameScheduler) {
    self.wake = wake
    self.scheduler = scheduler
  }

  func awaitPendingFrame() async {
    let scheduler = self.scheduler
    await wake.wait(until: { scheduler.hasPendingFrame() })
  }
}

struct AnimatorHarnessTimeout: Error, CustomStringConvertible {
  let frame: String

  var description: String {
    "timed out waiting for the animator condition; last frame:\n\(frame)"
  }
}

final class AnimatorRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []

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
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  func centerOfText(_ target: String) -> Point? {
    guard let frame = frames.last else { return nil }
    for (row, line) in frame.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let text = String(line)
      guard let range = text.range(of: target) else { continue }
      let column = text.distance(from: text.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

final class AnimatorEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

final class AnimatorEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}

@MainActor
final class AnimatorFrameDiagnosticSink: FrameDiagnosticSink {
  private(set) var records: [FrameDiagnosticRecord] = []

  func record(_ sample: RuntimeFrameSample) {
    records.append(FrameRecordDerivation.record(from: sample))
  }
}
