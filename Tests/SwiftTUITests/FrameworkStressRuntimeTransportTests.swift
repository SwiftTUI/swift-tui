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

// MARK: - Attempt 005: paste boundary inside pointer traffic

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 005 paste keeps surrounding scroll bursts ordered")
  func runtimeTransport005PasteKeepsSurroundingScrollBurstsOrdered() {
    // Hypothesis: paste delivery can flush only one side of a coalesced pointer
    // burst, allowing scroll deltas to cross the non-pointer event.
    let location = Point(x: 5, y: 4)
    let events = coalescedInputEvents([
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: location)),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 2), location: location)),
      .paste(.init(content: "payload")),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 4), location: location)),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 8), location: location)),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: location)),
        .paste(.init(content: "payload")),
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 12), location: location)),
      ]
    )
  }
}

// MARK: - Attempt 004: dragged-button transition

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 004 drag button changes preserve separate runs")
  func runtimeTransport004DragButtonChangesPreserveSeparateRuns() {
    // Hypothesis: high-rate drag compression can merge primary and secondary
    // button ownership and deliver the later route to the earlier recognizer.
    let events = coalescedInputEvents([
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 1, y: 2))),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 3, y: 2))),
      .mouse(.init(kind: .dragged(.secondary), location: .init(x: 4, y: 2))),
      .mouse(.init(kind: .dragged(.secondary), location: .init(x: 6, y: 2))),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .dragged(.primary), location: .init(x: 3, y: 2))),
        .mouse(.init(kind: .dragged(.secondary), location: .init(x: 6, y: 2))),
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
