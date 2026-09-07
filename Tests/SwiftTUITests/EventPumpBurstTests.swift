@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Event pump burst handling")
struct EventPumpBurstTests {
  @Test("a large queued signal burst retains order and arrival accounting")
  func signalBurstPreservesOrder() throws {
    let buffer = EventPumpBuffer()
    for index in 0..<10_000 {
      #expect(buffer.enqueue(.signal("signal-\(index)")))
    }
    for index in 0..<10_000 {
      let batch = buffer.drain()
      #expect(batch.count == 1)
      let event = try #require(batch.first)
      guard case .signal(let name) = event.event else {
        Issue.record("expected a queued signal")
        return
      }
      #expect(name == "signal-\(index)")
      #expect(event.arrival.id == UInt64(index))
      #expect(event.arrival.count == 1)
    }
    #expect(!buffer.hasPendingEvents())
    #expect(buffer.drain().isEmpty)
  }

  @Test("alternating pointer kinds preserve one batch and every arrival")
  func alternatingPointerBurstPreservesArrivals() {
    let buffer = EventPumpBuffer()
    for index in 0..<2_000 {
      let event: MouseEvent = .init(
        kind: index.isMultiple(of: 2) ? .moved : .scrolled(deltaX: 0, deltaY: 1),
        location: .init(x: 2, y: 3)
      )
      #expect(buffer.enqueue(.input(.mouse(event))) == (index == 0))
    }
    let batch = buffer.drain()
    #expect(batch.count == 2_000)
    #expect(batch.map(\.arrival.id) == (0..<2_000).map(UInt64.init))
    #expect(batch.reduce(0) { $0 + $1.arrival.count } == 2_000)
    #expect(!buffer.hasPendingEvents())
  }

  @Test("scheduler bursts retain bounded wake tokens while preserving pending work")
  func schedulerBurstCoalescesWakeTokens() async {
    let root = testIdentity("WakeBurst")
    let scheduler = FrameScheduler()
    let input = InjectedTerminalInputReader()
    let runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: RecordingPresentationSurface(surfaceSize: .init(width: 20, height: 4)),
      terminalInputReader: input,
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      viewBuilder: { _, _ in Text("Root") }
    )
    let pump = runLoop.makeEventPump()
    defer { pump.cancel() }
    for _ in 0..<10_000 { scheduler.requestInvalidation(of: [root]) }
    input.finish()
    var wakeCount = 0
    for await _ in pump.stream { wakeCount += 1 }
    // Input-end may arrive after the first wake is consumed. The 10,000
    // scheduler notifications represent only one pending unit of work.
    #expect(wakeCount <= 2)
    #expect(wakeCount > 0)
    #expect(scheduler.pendingInvalidatedIdentities == [root])
    #expect(pump.hasPendingEvents())
    let events = pump.drainEvents()
    #expect(events.count == 1)
    if case .inputEnded? = events.first?.event {
    } else {
      Issue.record("input termination was lost while coalescing wakes")
    }
  }
}
