import Synchronization
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite("SwiftTUI runtime and transport stress behavior", .serialized)
struct FrameworkStressRuntimeTransportTests {}

// MARK: - Attempt 001: scroll-location alternation

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 001 alternating scroll locations keep event boundaries")
  func runtimeTransport001AlternatingScrollLocationsKeepEventBoundaries() {
    // Hypothesis: a scroll burst that returns to an earlier cell can merge across
    // the intervening location and apply deltas to the wrong hit-test target.
    let first = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 1),
      location: .init(x: 2, y: 3)
    )
    let second = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 2),
      location: .init(x: 8, y: 3)
    )
    let third = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 3),
      location: .init(x: 2, y: 3)
    )

    #expect(
      coalescedInputEvents([.mouse(first), .mouse(second), .mouse(third)]) == [
        .mouse(first), .mouse(second), .mouse(third)
      ]
    )
  }
}

// MARK: - Attempt 003: pointer modifier boundary

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 003 pointer modifier changes split coalesced runs")
  func runtimeTransport003PointerModifierChangesSplitCoalescedRuns() {
    // Hypothesis: moved events can merge across a modifier transition and erase
    // the last unmodified location or the first modified event.
    let events = coalescedInputEvents([
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 2, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 3, y: 1), modifiers: .shift)),
      .mouse(.init(kind: .moved, location: .init(x: 4, y: 1), modifiers: .shift)),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .moved, location: .init(x: 2, y: 1))),
        .mouse(.init(kind: .moved, location: .init(x: 4, y: 1), modifiers: .shift)),
      ]
    )
  }
}

// MARK: - Attempt 002: zero-sum scroll coalescing

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 002 opposing scroll deltas retain one ordered event")
  func runtimeTransport002OpposingScrollDeltasRetainOneOrderedEvent() {
    // Hypothesis: opposite deltas at one cell can cancel by dropping the event
    // entirely, allowing later batches to cross what should remain a boundary.
    let location = Point(x: 4, y: 2)
    let events = coalescedInputEvents([
      .mouse(.init(kind: .scrolled(deltaX: 3, deltaY: -4), location: location)),
      .mouse(.init(kind: .scrolled(deltaX: -3, deltaY: 4), location: location)),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 0), location: location))
      ]
    )
  }
}
