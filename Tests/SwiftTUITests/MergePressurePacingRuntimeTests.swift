import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite
struct MergePressurePacingRuntimeTests {
  @Test("an unprofiled disabled run does not feed frame cost", arguments: [false, true])
  func telemetryArming(profiled: Bool) async throws {
    let h = try PacingHarness(enabled: false, profiled: profiled)
    defer { h.loop.frameSink = nil }
    h.renderCost = .milliseconds(12)
    _ = h.state.replace(with: 1)
    try await h.render()
    #expect(
      h.scheduler.pacingSnapshot(at: h.now).ewmaFrameCost == (profiled ? .milliseconds(6) : .zero))
  }
  @Test("the async driver defers invalidation, then an input event opens the gate")
  func inputBypass() async throws {
    let h = try PacingHarness()
    defer { h.loop.frameSink = nil }
    try h.engage()
    let before = h.frames
    try await h.render()
    #expect(h.frames == before)
    #expect(h.scheduler.nextWakeInstant(after: h.now) == h.now.advanced(by: .milliseconds(10)))
    _ = h.loop.handle(.input(.key(.character("x"))))
    try await h.render()
    #expect(h.frames == before + 1)
    let sample = try #require(h.samples.last)
    #expect(sample.scheduledFrame.causes.contains(.input))
    #expect(sample.scheduledFrame.causes.contains(.invalidation))
    #expect(sample.scheduledFrame.pacing.engaged)
    let record = FrameRecordDerivation.record(from: .committed(sample))
    let headers = FrameDiagnosticsTSVFormatting.headerFields
    let fields = FrameDiagnosticsTSVFormatting.fields(for: record)
    #expect(headers.count == fields.count)
    #expect(fields[try #require(headers.firstIndex(of: "pace_engaged"))] == "1")
    #expect(record.pacing.ewmaFrameCost == .milliseconds(20))
  }

  @Test("animation deadlines keep their exact cadence under engaged pressure")
  func animationDeadlines() async throws {
    let h = try PacingHarness()
    defer { h.loop.frameSink = nil }
    let controller = h.loop.renderer.internalAnimationController
    withAnimationSinks(controller) {
      withAnimation(.linear(duration: .milliseconds(300))) { _ = h.state.replace(with: 6) }
    }
    try await h.render()
    #expect(controller.activeAnimationCount > 0)
    for _ in 0..<3 {
      let tick = try #require(h.scheduler.nextWakeInstant(after: h.now))
      h.now = tick
      h.scheduler.requestInvalidation(of: [h.root])
      h.scheduler.requestInvalidation(of: [h.root])
      // An expensive recent commit puts this instant inside a hypothetical gap.
      h.scheduler.recordCommittedFrame(cost: .milliseconds(200), at: tick)
      let before = h.samples.count
      try await h.render()
      let sample = try #require(h.samples.dropFirst(before).first)
      #expect(sample.scheduledFrame.triggeredDeadline == tick)
      #expect(sample.scheduledFrame.causes.contains(.invalidation))
      #expect(sample.scheduledFrame.causes.contains(.deadline))
    }
  }

  @Test("runtime cost feed is armed by profiling and idle pressure expires")
  func costAndExpiry() async throws {
    let h = try PacingHarness()
    defer { h.loop.frameSink = nil }
    h.renderCost = .milliseconds(12)
    _ = h.state.replace(with: 1)
    try await h.render()
    #expect(h.scheduler.pacingSnapshot(at: h.now).ewmaFrameCost == .milliseconds(6))
    h.renderCost = .zero
    try h.engage()
    h.now = h.now.advanced(by: .seconds(2))
    h.scheduler.recordCommittedFrame(cost: .seconds(1), at: h.now)
    let before = h.frames
    try await h.render()
    #expect(h.frames == before + 1)
    #expect(h.samples.last?.scheduledFrame.pacing.gap == .zero)
  }
}

@MainActor
private final class PacingHarness: FrameDiagnosticSink {
  var now = MonotonicInstant(offset: .seconds(100))
  var renderCost: Duration = .zero
  let root = testIdentity("PacingRuntime")
  let scheduler: FrameScheduler
  let state: StateContainer<Int>
  var loop: RunLoop<Int, AnyView>!
  var frames = 0
  var samples: [CommittedFrameSample] = []

  init(enabled: Bool = true, profiled: Bool = true) throws {
    scheduler = FrameScheduler(mergePressurePacingEnabled: enabled)
    state = StateContainer(initialState: 0, invalidationIdentities: [root])
    state.invalidator = scheduler
    let size = CellSize(width: 24, height: 4)
    loop = RunLoop(
      rootIdentity: root,
      presentationSurface: RecordingPresentationSurface(surfaceSize: size),
      inputReader: PacingInputReader(), signalReader: PacingSignalReader(),
      scheduler: scheduler, stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      viewBuilder: { [weak self] state, _ in
        if let self { self.now = self.now.advanced(by: self.renderCost) }
        return AnyView(Text("motion").offset(x: state, y: 0))
      })
    loop.frameClock = { [unowned self] in now }
    loop.frameSink = profiled ? self : nil
    scheduler.requestInvalidation(of: [root])
    try loop.renderPendingFrames(renderedFrames: &frames)
  }

  func engage() throws {
    scheduler.requestInvalidation(of: [root])
    scheduler.requestInvalidation(of: [root])
    try loop.renderPendingFrames(renderedFrames: &frames)
    scheduler.recordCommittedFrame(cost: .milliseconds(40), at: now)
    scheduler.requestInvalidation(of: [root])
  }

  func render() async throws {
    var count = frames
    defer { frames = count }
    try await loop.renderPendingFramesAsync(renderedFrames: &count)
  }
  func record(_ sample: RuntimeFrameSample) {
    if case .committed(let frame) = sample { samples.append(frame) }
  }
}

private final class PacingInputReader: InputReading {
  func events() -> AsyncStream<KeyPress> { AsyncStream { $0.finish() } }
}
private final class PacingSignalReader: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}
