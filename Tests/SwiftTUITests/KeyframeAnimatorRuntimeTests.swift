import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage K0 runtime pins for `KeyframeAnimator` (plan 2026-08-25-002 §4),
/// driven through a real `RunLoop` so the `.task` driver, state writes, and
/// the controller all take part.
@MainActor
@Suite(.serialized)
struct KeyframeAnimatorRuntimeTests {
  private static let bumpLabel = "bump"

  // MARK: - Trigger mode

  @Test("trigger mode does not animate on mount")
  func triggerModeIsQuietOnMount() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness {
      KeyframeTriggerFixture(probe: probe, duration: .milliseconds(200))
    }
    defer { harness.shutdown() }

    try await harness.hold(for: .milliseconds(250))
    #expect(Set(probe.values) == [0], "values: \(probe.values)")
  }

  @Test("one trigger change advances monotonically and lands on the end value exactly once")
  func oneTriggerRunsToTheEnd() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness {
      KeyframeTriggerFixture(probe: probe, duration: .milliseconds(800))
    }
    defer { harness.shutdown() }

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { probe.values.last == 10 })
    // Let a few more ticks' worth of wall clock pass: nothing else may write.
    try await harness.hold(for: .milliseconds(150))

    let distinct = probe.distinctRun
    #expect(distinct.first == 0)
    #expect(distinct.last == 10)
    #expect(distinct.count > 2, "expected intermediate values, got \(distinct)")
    #expect(distinct == distinct.sorted(), "not monotone: \(distinct)")
    #expect(
      distinct.filter { $0 == 10 }.count == 1, "end value written more than once: \(distinct)")
  }

  @Test("a retrigger mid-flight restarts from the current interpolated value")
  func retriggerContinuesFromCurrentValue() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness {
      KeyframeTriggerFixture(probe: probe, duration: .milliseconds(1_200))
    }
    defer { harness.shutdown() }

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { (probe.values.last ?? 0) >= 3 })
    let before = try #require(probe.values.last)
    let countBefore = probe.values.count

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { probe.values.count >= countBefore + 3 })
    let after = Array(probe.values.dropFirst(countBefore))
    #expect(
      after.allSatisfy { $0 >= before - 0.5 },
      "retrigger jumped back below \(before): \(after)"
    )
    try await harness.wait(until: { probe.values.last == 10 })
  }

  @Test("a retrigger carries velocity into a leading cubic keyframe")
  func retriggerCarriesVelocity() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness {
      KeyframeCubicTriggerFixture(probe: probe)
    }
    defer { harness.shutdown() }

    try harness.clickText(Self.bumpLabel)
    // Midway through a rest-to-rest cubic the velocity is at its peak.
    try await harness.wait(until: { (probe.values.last ?? 0) >= 4 })
    let countBefore = probe.distinctRun.count

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { probe.distinctRun.count >= countBefore + 3 })

    let run = probe.distinctRun
    let deltasBefore = zip(run[..<countBefore].dropFirst(), run[..<countBefore]).map { $0 - $1 }
    let deltasAfter = zip(run[countBefore...].dropFirst(), run[countBefore...]).map { $0 - $1 }
    let lastBefore = try #require(deltasBefore.suffix(2).max())
    let firstAfter = try #require(deltasAfter.prefix(2).max())
    // A cubic restarted at rest would produce a near-zero first step (the
    // Hermite curve leaves rest with zero slope); a seeded one keeps moving.
    #expect(
      firstAfter >= lastBefore * 0.35,
      "velocity discontinuity at retrigger: before \(deltasBefore) after \(deltasAfter)"
    )
    try await harness.wait(until: { probe.values.last == 10 })
  }

  // MARK: - Repeating mode

  @Test("repeating mode wraps around and stays inside the keyframe range")
  func repeatingModeWraps() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness {
      KeyframeRepeatingFixture(probe: probe)
    }
    defer { harness.shutdown() }

    try await harness.wait(until: {
      let run = probe.distinctRun
      return zip(run.dropFirst(), run).contains { $0 < $1 }
    })
    #expect(probe.values.allSatisfy { $0 >= 0 && $0 <= 10 }, "\(probe.values)")
    #expect(probe.distinctRun.count >= 4)
  }

  // MARK: - Ancestor animations

  @Test("coincident ancestor withAnimation and .animation(_:value:) do not animate keyframe slots")
  func ancestorAnimationsDoNotReachKeyframeSlots() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness {
      KeyframeAncestorAnimationFixture(probe: probe)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try harness.clickText(Self.bumpLabel)
    var sawOffsetAnimation = false
    try await harness.wait(until: {
      let keys = controller.debugStateSnapshot().activeAnimationKeys
      if keys.contains(where: { $0.scope == .property(.offset) }) {
        sawOffsetAnimation = true
      }
      return probe.values.last == 10
    })
    #expect(!sawOffsetAnimation, "the keyframe-driven offset picked up an ancestor animation")
    #expect(probe.distinctRun.count > 2, "\(probe.distinctRun)")
  }

  // MARK: - Tabs

  @Test("leaving a tab stops the loop and returning with an unchanged trigger does not replay")
  func tabSwitchStopsAndReturnDoesNotReplay() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness(size: .init(width: 60, height: 10)) {
      KeyframeTabFixture(probe: probe)
    }
    defer { harness.shutdown() }

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { (probe.values.last ?? 0) >= 2 })

    try harness.clickText("PlainTab")
    #expect(harness.frame.contains("plain-pane"))
    let frozen = try #require(probe.values.last)
    let countAtSwitch = probe.values.count
    try await harness.hold(for: .milliseconds(300))
    #expect(
      probe.values.count == countAtSwitch,
      "the keyframe loop kept writing after its tab went dormant: \(probe.values)"
    )

    try harness.clickText("AnimTab")
    try await harness.hold(for: .milliseconds(300))
    let afterReturn = Array(probe.values.dropFirst(countAtSwitch))
    #expect(
      afterReturn.allSatisfy { $0 == frozen },
      "returning to the tab replayed the keyframes: \(afterReturn) (frozen \(frozen))"
    )
  }

  // MARK: - Reduce motion

  @Test("under reduce motion a trigger change snaps to the end value")
  func reduceMotionSnapsTriggerToEnd() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness(motion: .reduced) {
      KeyframeTriggerFixture(probe: probe, duration: .milliseconds(400))
    }
    defer { harness.shutdown() }

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { probe.values.last == 10 })
    #expect(
      Set(probe.values) == [0, 10], "intermediate values under reduce motion: \(probe.values)")
  }

  @Test("under reduce motion repeating mode never writes")
  func reduceMotionRestsRepeatingMode() async throws {
    let probe = KeyframeValueProbe()
    let harness = try KeyframeAnimatorHarness(motion: .reduced) {
      KeyframeRepeatingFixture(probe: probe)
    }
    defer { harness.shutdown() }

    try await harness.hold(for: .milliseconds(300))
    #expect(Set(probe.values) == [0], "\(probe.values)")
    #expect(harness.activeTaskCount == 0)
  }
}

// MARK: - Probe

@MainActor
private final class KeyframeValueProbe {
  private(set) var values: [Double] = []

  func record(_ value: Double) {
    values.append(value)
  }

  /// `values` with consecutive duplicates collapsed: body re-evaluations
  /// that did not change the value do not count as writes.
  var distinctRun: [Double] {
    var run: [Double] = []
    for value in values where run.last != value {
      run.append(value)
    }
    return run
  }
}

// MARK: - Fixtures

@MainActor
private struct KeyframeTriggerFixture: View {
  let probe: KeyframeValueProbe
  let duration: Duration
  @State private var bumps = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("bump") { bumps += 1 }
      KeyframeAnimator(initialValue: 0.0, trigger: bumps) { value in
        let _ = probe.record(value)
        Text("v=\(Int(value.rounded()))")
      } keyframes: { _ in
        LinearKeyframe(10.0, duration: duration)
      }
    }
  }
}

@MainActor
private struct KeyframeCubicTriggerFixture: View {
  let probe: KeyframeValueProbe
  @State private var bumps = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("bump") { bumps += 1 }
      KeyframeAnimator(initialValue: 0.0, trigger: bumps) { value in
        let _ = probe.record(value)
        Text("v=\(Int(value.rounded()))")
      } keyframes: { _ in
        CubicKeyframe(10.0, duration: .milliseconds(1_500))
      }
    }
  }
}

@MainActor
private struct KeyframeRepeatingFixture: View {
  let probe: KeyframeValueProbe

  var body: some View {
    KeyframeAnimator(initialValue: 0.0, repeating: true) { value in
      let _ = probe.record(value)
      Text("v=\(Int(value.rounded()))")
    } keyframes: { _ in
      LinearKeyframe(10.0, duration: .milliseconds(200))
    }
  }
}

@MainActor
private struct KeyframeAncestorAnimationFixture: View {
  let probe: KeyframeValueProbe
  @State private var bumps = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("bump") {
        withAnimation(.linear(duration: .seconds(2))) {
          bumps += 1
        }
      }
      KeyframeAnimator(initialValue: 0.0, trigger: bumps) { value in
        let _ = probe.record(value)
        Text("★").offset(x: Int(value.rounded()), y: 0)
      } keyframes: { _ in
        LinearKeyframe(10.0, duration: .milliseconds(800))
      }
    }
    .animation(.linear(duration: .seconds(2)), value: bumps)
  }
}

@MainActor
private struct KeyframeTabFixture: View {
  let probe: KeyframeValueProbe
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
      Tab("AnimTab", value: 0) {
        KeyframeTriggerFixture(probe: probe, duration: .seconds(1))
      }
      Tab("PlainTab", value: 1) {
        Text("plain-pane")
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

// MARK: - Harness

@MainActor
private final class KeyframeAnimatorHarness<Content: View> {
  private let terminal: KeyframeRecordingHost
  let runLoop: SwiftTUIRuntime.RunLoop<Int, Content>
  private let scheduler: FrameScheduler
  private let rootIdentity = testIdentity("KeyframeAnimatorRoot")
  private var renderedFrames = 0
  private var didShutdown = false
  private let schedulerWake = MainActorConditionSignal()

  init(
    size: CellSize = .init(width: 40, height: 6),
    motion: RuntimeConfiguration.MotionMode = .normal,
    @ViewBuilder content: @escaping () -> Content
  ) throws {
    let terminal = KeyframeRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: KeyframeEmptyKeyReader(),
      signalReader: KeyframeEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      runtimeConfiguration: RuntimeConfiguration(motion: motion),
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: ScopedMapper { _ in content() }
    )
    focusTracker.invalidator = scheduler
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
        throw KeyframeHarnessTimeout(frame: frame)
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
  private func awaitPendingFrame(within limit: Duration) async {
    let scheduler = self.scheduler
    let schedulerWake = self.schedulerWake
    // The signal resumes on cancellation, so a timer task bounds the wait.
    let waiter = Task { @MainActor in
      await schedulerWake.wait(until: { scheduler.hasPendingFrame() })
    }
    let timer = Task { @MainActor in
      try? await Task.sleep(for: limit)
      waiter.cancel()
    }
    await waiter.value
    timer.cancel()
  }
}

private struct KeyframeHarnessTimeout: Error, CustomStringConvertible {
  let frame: String

  var description: String {
    "timed out waiting for the keyframe condition; last frame:\n\(frame)"
  }
}

private final class KeyframeRecordingHost: PresentationSurface {
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

private final class KeyframeEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class KeyframeEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
