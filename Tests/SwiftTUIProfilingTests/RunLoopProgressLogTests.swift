@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIProfiling

@MainActor
@Suite
struct RunLoopProgressLogTests {
  @Test("The log retains the events it is given")
  func retainsEvents() {
    let log = RunLoopProgressLog()
    log.record(RunLoopProgressEvent(sequence: 0, kind: .frameCommitted, frameNumber: 1))
    log.record(RunLoopProgressEvent(sequence: 1, kind: .schedulerIdle, frameNumber: 1))
    #expect(log.events.count == 2)
    #expect(log.events.first?.kind == .frameCommitted)
    log.clear()
    #expect(log.events.isEmpty)
  }

  @Test("An installed log captures events the probe forwards through the registry")
  func capturesForwardedEvents() {
    let log = RunLoopProgressLog.install()
    defer { ProfilingRegistry.shared.progressObserver = nil }

    let probe = RunLoopProgressProbe()
    probe.record(.frameCommitted, frameNumber: 9991, desiredGeneration: 2)
    probe.record(.schedulerIdle, frameNumber: 9991)

    let mine = log.events.filter { $0.frameNumber == 9991 }
    #expect(mine.count == 2)
    #expect(mine.contains { $0.kind == .frameCommitted })
    #expect(mine.contains { $0.kind == .schedulerIdle })
  }

  @Test("Quiescence still resolves locally with no observer installed")
  func quiescenceWithoutObserver() async {
    ProfilingRegistry.shared.progressObserver = nil
    let probe = RunLoopProgressProbe()
    // Event fired before the await — resolves via the retained-events fast path.
    probe.record(.schedulerIdle, frameNumber: 0)
    let event = await probe.idle()
    #expect(event.kind == .schedulerIdle)
  }
}
