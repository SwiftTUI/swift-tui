@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AnimatedOverflowRuntimeTests {
  @Test(
    "overflow expansion preserves an active geometry task and its frames", arguments: [false, true])
  func geometryTaskKeepsRendering(async: Bool) async throws {
    let probe = OverflowTickProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AnimatedOverflow"), size: .init(width: 40, height: 16)
    ) { OverflowTickRoot(probe: probe) }
    defer { harness.shutdown() }
    harness.runLoop.renderMode = async ? .async : .sync
    var renderedFrames = 0
    func render() async throws {
      if async {
        try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      } else {
        _ = try harness.render()
      }
    }
    func tick() async throws {
      let next = probe.ticks + 1
      probe.continuation.yield(())
      await probe.signal.wait { probe.ticks >= next || probe.stops > 0 }
      try #require(probe.ticks == next)
      try await render()
      #expect(harness.frame.contains("tick \(next)"))
    }
    // Drive the task through an awaitable tick source, avoiding both wall-clock
    // polling and assumptions about a game simulation's eventual resting state.
    for _ in 0..<3 { try await tick() }
    let point = try #require(harness.point(forText: "▼"))
    _ = harness.runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: point))))
    _ = harness.runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: point))))
    try await render()
    #expect(harness.frame.contains("▲"))
    var observedFrames: Set<String> = []
    for _ in 0..<3 {
      try await tick()
      observedFrames.insert(harness.frame)
      #expect(harness.frame.contains("▲"))
    }
    #expect(observedFrames.count == 3)
    #expect(probe.starts == 1)
    #expect(probe.stops == 0)
  }
}

@MainActor
private final class OverflowTickProbe {
  let signal = MainActorConditionSignal()
  let stream: AsyncStream<Void>
  let continuation: AsyncStream<Void>.Continuation
  var starts = 0
  var stops = 0
  var ticks = 0

  init() {
    (stream, continuation) = AsyncStream<Void>.makeStream()
  }
}

private struct OverflowTickRoot: View {
  let probe: OverflowTickProbe
  @State private var selection = 7
  var body: some View {
    TabView(selection: $selection) {
      ForEach(0..<8) { index in
        Tab("Tab number \(index)", value: index) {
          OverflowTickContent(probe: probe)
        }
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

private struct OverflowTickContent: View {
  let probe: OverflowTickProbe
  @State private var tick = 0
  var body: some View {
    GeometryReader { _ in
      Text("tick \(tick)")
        .task {
          probe.starts += 1
          defer {
            probe.stops += 1
            probe.signal.notify()
          }
          for await _ in probe.stream {
            guard !Task.isCancelled else { return }
            tick += 1
            probe.ticks = tick
            probe.signal.notify()
          }
        }
    }
  }
}
