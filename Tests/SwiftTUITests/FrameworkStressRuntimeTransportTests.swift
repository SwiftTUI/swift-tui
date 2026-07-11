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

// MARK: - Attempt 008: event-pump wake ownership

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 008 event pump wakes once per pending batch")
  func runtimeTransport008EventPumpWakesOncePerPendingBatch() throws {
    // Hypothesis: an in-place pointer merge can report a new batch wake, or a
    // later key batch can fail to wake because the pointer batch already did.
    let buffer = EventPumpBuffer()

    #expect(
      buffer.enqueue(
        .input(.mouse(.init(kind: .moved, location: .init(x: 1, y: 1))))
      )
    )
    #expect(
      !buffer.enqueue(
        .input(.mouse(.init(kind: .moved, location: .init(x: 5, y: 1))))
      )
    )
    #expect(buffer.enqueue(.input(.key(.character("q")))))

    let firstBatch = buffer.drain()
    let firstEvent = try #require(firstBatch.first)
    guard case .input(.mouse(let mouse)) = firstEvent else {
      Issue.record("expected a merged pointer event")
      return
    }
    #expect(firstBatch.count == 1)
    #expect(mouse.location.cell == CellPoint(x: 5, y: 1))

    let secondBatch = buffer.drain()
    guard case .input(.key(let key))? = secondBatch.first else {
      Issue.record("expected a key in the second batch")
      return
    }
    #expect(secondBatch.count == 1)
    #expect(key == KeyPress(.character("q")))
    #expect(!buffer.hasPendingEvents())
  }
}

// MARK: - Attempt 007: click boundary inside motion traffic

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 007 click edges prevent motion merging across activation")
  func runtimeTransport007ClickEdgesPreventMotionMergingAcrossActivation() {
    // Hypothesis: noncoalescible down/up events can flush without resetting the
    // pending move, letting the post-click position replace the pre-click one.
    let events = coalescedInputEvents([
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 0))),
      .mouse(.init(kind: .moved, location: .init(x: 2, y: 0))),
      .mouse(.init(kind: .down(.primary), location: .init(x: 2, y: 0))),
      .mouse(.init(kind: .up(.primary), location: .init(x: 2, y: 0))),
      .mouse(.init(kind: .moved, location: .init(x: 9, y: 0))),
      .mouse(.init(kind: .moved, location: .init(x: 10, y: 0))),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .moved, location: .init(x: 2, y: 0))),
        .mouse(.init(kind: .down(.primary), location: .init(x: 2, y: 0))),
        .mouse(.init(kind: .up(.primary), location: .init(x: 2, y: 0))),
        .mouse(.init(kind: .moved, location: .init(x: 10, y: 0))),
      ]
    )
  }
}

// MARK: - Attempt 006: drop boundary inside hover traffic

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 006 drop keeps surrounding hover runs ordered")
  func runtimeTransport006DropKeepsSurroundingHoverRunsOrdered() {
    // Hypothesis: a file drop can be appended into a coalescible hover batch,
    // causing pre-drop motion to be replaced by post-drop motion.
    let drop: InputEvent = .drop(
      paths: ["/tmp/one", "/tmp/two"],
      context: .init(location: .init(x: 3, y: 3), modifiers: .alt)
    )
    let events = coalescedInputEvents([
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 2, y: 1))),
      drop,
      .mouse(.init(kind: .moved, location: .init(x: 7, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 8, y: 1))),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .moved, location: .init(x: 2, y: 1))),
        drop,
        .mouse(.init(kind: .moved, location: .init(x: 8, y: 1))),
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
