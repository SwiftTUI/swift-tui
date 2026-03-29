import Testing

@testable import TerminalUI

@MainActor
@Suite
struct InputBatchingResponsivenessTests {
  @Test("pointer batching keeps a short debounce window")
  func pointerBatchingUsesShortDebounce() {
    #expect(InputReaderTiming.mouseEventFlushDelayMilliseconds == 1)
    #expect(RunLoop<EventBatchProbeState>.EventPumpTiming.coalescedPointerDrainYieldCount == 4)
  }

  @Test("pointer burst coalescing still preserves event boundaries")
  func coalescedPointerBurstsStillMerge() {
    let events: [InputEvent] = [
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: .init(x: 2, y: 3))),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 2), location: .init(x: 2, y: 3))),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 4, y: 1))),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 7, y: 1))),
      .key(.character("q")),
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 3, y: 1))),
      .mouse(.init(kind: .down(.primary), location: .init(x: 3, y: 1))),
    ]

    #expect(
      coalescedInputEvents(events) == [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: .init(x: 2, y: 3))),
        .mouse(.init(kind: .dragged(.primary), location: .init(x: 7, y: 1))),
        .key(.character("q")),
        .mouse(.init(kind: .moved, location: .init(x: 3, y: 1))),
        .mouse(.init(kind: .down(.primary), location: .init(x: 3, y: 1))),
      ])
  }
}

private struct EventBatchProbeState: Equatable, Sendable {}
