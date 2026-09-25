import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite
struct RunLoopDrainFairnessTests {
  @Test(
    "slow frames yield even when periodic state writes keep invalidating", arguments: [false, true])
  func slowFramesYield(synchronous: Bool) async throws {
    let harness = DrainFairnessHarness()
    harness.ticks.isActive = true
    harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    var frames = 0

    if synchronous {
      try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    } else {
      try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &frames)
    }

    #expect(frames > 0)
    #expect(frames < PeriodicInvalidationSink.safetyLimit)
    #expect(harness.scheduler.hasPendingFrame(at: harness.clock.now))

    // Yielding must preserve the pending write for the next pass.
    harness.ticks.isActive = false
    let framesBeforeResume = frames
    try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &frames)
    #expect(frames > framesBeforeResume)
    #expect(!harness.scheduler.hasPendingFrame(at: harness.clock.now))
  }

  @Test(
    "with an event pump attached and the budget set, a pass yields once it is spent",
    arguments: [
      (renderCost: Duration.milliseconds(40), framesPerPass: 1),
      (renderCost: Duration.milliseconds(5), framesPerPass: 4),
    ]
  )
  func elapsedWorkBudgetBoundsAPass(renderCost: Duration, framesPerPass: Int) async throws {
    // The producer ticks at least once per commit, so every pass has more
    // work than the budget admits.
    let harness = DrainFairnessHarness(renderCost: renderCost, tickInterval: renderCost)
    harness.runLoop.drainPassWorkBudget = .milliseconds(16)
    let pump = harness.runLoop.makeEventPump()
    defer { pump.cancel() }
    harness.ticks.isActive = true
    harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    var frames = 0

    _ = try await harness.runLoop.renderPendingFramesAsync(
      renderedFrames: &frames, eventPump: pump)

    // 16 ms of frame-clock work per pass: one 40 ms frame overshoots it at
    // once; 5 ms frames fit four acquisitions (0, 5, 10, 15 ms elapsed)
    // before the fifth check trips. The producer still has work pending.
    #expect(frames == framesPerPass, "frames: \(frames)")
    #expect(harness.scheduler.hasPendingFrame(at: harness.clock.now))

    // The synchronous driver applies the same budget when given the pump.
    harness.ticks.isActive = true
    var syncFrames = 0
    try harness.runLoop.renderPendingFrames(renderedFrames: &syncFrames, eventPump: pump)
    #expect(syncFrames == framesPerPass, "sync frames: \(syncFrames)")
  }

  @Test("end of input flushes the input change without draining a periodic producer forever")
  func inputEndBoundsPeriodicFlush() async throws {
    let harness = DrainFairnessHarness()
    harness.input.send(.key(.return))
    harness.input.finish()

    let result = try await harness.runLoop.run()

    #expect(result.exitReason == .inputEnded)
    #expect(result.finalState == 1)
    #expect(harness.surface.frames.last?.contains("value 1") == true)
    #expect(harness.ticks.tickCount > 0)
    #expect(harness.ticks.tickCount < PeriodicInvalidationSink.safetyLimit)
  }
}

@MainActor
private final class DrainFairnessHarness {
  let rootIdentity = testIdentity("DrainFairness")
  let scheduler = FrameScheduler()
  let clock = VirtualFrameClock()
  let input = InjectedTerminalInputReader()
  let surface = RecordingPresentationSurface(surfaceSize: .init(width: 20, height: 2))
  let ticks: PeriodicInvalidationSink
  let runLoop: RunLoop<Int, Text>

  init(renderCost: Duration = .milliseconds(40), tickInterval: Duration = .milliseconds(33)) {
    let ticks = PeriodicInvalidationSink(
      scheduler: scheduler, identity: rootIdentity, clock: clock, renderCost: renderCost,
      tickInterval: tickInterval)
    self.ticks = ticks
    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: input,
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { key, _, state in
        guard key == KeyPress(.return) else { return .ignored }
        ticks.isActive = true
        state.mutate { $0 += 1 }
        return .handled
      },
      proposal: .init(width: 20, height: 2),
      viewBuilder: { value, _ in Text("value \(value)") }
    )
    runLoop.frameClock = { [clock] in clock.now }
    runLoop.frameSink = ticks
  }
}

/// Models a 33 ms producer on a machine that takes 40 ms to render a frame.
/// Each frame therefore encounters a fresh state invalidation. The safety
/// limit makes the unfixed test fail assertions instead of hanging its runner.
@MainActor
private final class PeriodicInvalidationSink: FrameDiagnosticSink {
  static let safetyLimit = 32
  var isActive = false
  private(set) var tickCount = 0
  private let scheduler: FrameScheduler
  private let identity: Identity
  private let clock: VirtualFrameClock
  private let renderCost: Duration
  private let tickInterval: Duration
  private var nextTick: MonotonicInstant

  init(
    scheduler: FrameScheduler, identity: Identity, clock: VirtualFrameClock,
    renderCost: Duration = .milliseconds(40),
    tickInterval: Duration = .milliseconds(33)
  ) {
    self.scheduler = scheduler
    self.identity = identity
    self.clock = clock
    self.renderCost = renderCost
    self.tickInterval = tickInterval
    nextTick = clock.now.advanced(by: tickInterval)
  }

  func record(_ sample: RuntimeFrameSample) {
    guard case .committed = sample, isActive else { return }
    clock.advance(by: renderCost)
    guard clock.now >= nextTick else { return }
    tickCount += 1
    nextTick = clock.now.advanced(by: tickInterval)
    if tickCount < Self.safetyLimit {
      scheduler.requestInvalidation(of: [identity])
    }
  }
}
