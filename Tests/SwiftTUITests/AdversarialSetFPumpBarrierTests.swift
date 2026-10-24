import SwiftTUICore
import Synchronization
import Testing

@testable import SwiftTUIRuntime

/// Unscoped `EventPumpBuffer` coalescing barriers and arrival accounting
/// (campaign two F4, setF025–setF040). The buffer merges only adjacent
/// compatible pointer events, starts a fresh batch at every non-coalescible
/// event, and fuses arrival envelopes so a merged burst still reports every
/// raw arrival bracketed by its first/last instant
/// (`Sources/SwiftTUIRuntime/RunLoop/EventPumpBuffer.swift:34-128`,
/// `Sources/SwiftTUIRuntime/RunLoop/InputArrival.swift:147-199`,
/// `Sources/SwiftTUIRuntime/Input/TerminalInputCoalescing.swift:110-146`).
@Suite("set F unscoped pump barriers")
struct AdversarialSetFPumpBarrierTests {
  private func buffer(at instant: MonotonicInstant) -> EventPumpBuffer {
    EventPumpBuffer(clock: { instant })
  }

  private func moved(_ x: Int) -> RuntimeEvent {
    .input(.mouse(MouseEvent(kind: .moved, location: Point(x: Double(x), y: 1))))
  }

  private func scrolled(_ deltaX: Int, _ deltaY: Int, x: Int = 1) -> RuntimeEvent {
    .input(
      .mouse(
        MouseEvent(
          kind: .scrolled(deltaX: deltaX, deltaY: deltaY),
          location: Point(x: Double(x), y: 1))))
  }

  @Test("setF025 a pure moved burst fuses into one entry counting every arrival")
  func setF025MovedBurstFusesArrivals() throws {
    let instant = MonotonicInstant(offset: .seconds(5))
    let pump = buffer(at: instant)
    #expect(pump.enqueue(moved(1)))
    #expect(!pump.enqueue(moved(2)))
    #expect(!pump.enqueue(moved(3)))
    #expect(pump.pendingBatchCount() == 1)
    let batch = pump.drain()
    try #require(batch.count == 1)
    #expect(batch[0].arrival.id == 0)
    #expect(batch[0].arrival.count == 3)
    #expect(batch[0].arrival.first == instant)
    #expect(batch[0].arrival.last == instant)
    guard case .input(.mouse(let mouse)) = batch[0].event else {
      Issue.record("expected a fused mouse event")
      return
    }
    #expect(mouse == MouseEvent(kind: .moved, location: Point(x: 3, y: 1)))
  }

  @Test("setF026 a moved then a scrolled share one batch but do not merge across kinds")
  func setF026MovedThenScrolledShareBatchUnmerged() throws {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(1)))
    #expect(pump.enqueue(moved(1)))
    #expect(!pump.enqueue(scrolled(0, 1)))
    #expect(pump.pendingBatchCount() == 1)
    let batch = pump.drain()
    try #require(batch.count == 2)
    #expect(batch.map(\.arrival.id) == [0, 1])
    #expect(batch.map(\.arrival.count) == [1, 1])
  }

  @Test("setF027 two scrolls at the same cell merge with summed deltas")
  func setF027ScrollsAtSameCellMerge() throws {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(2)))
    #expect(pump.enqueue(scrolled(1, 2)))
    #expect(!pump.enqueue(scrolled(3, 4)))
    let batch = pump.drain()
    try #require(batch.count == 1)
    #expect(batch[0].arrival.count == 2)
    guard case .input(.mouse(let mouse)) = batch[0].event,
      case .scrolled(let deltaX, let deltaY) = mouse.kind
    else {
      Issue.record("expected a merged scroll event")
      return
    }
    #expect(deltaX == 4)
    #expect(deltaY == 6)
  }

  @Test("setF028 two scrolls at different cells share a batch unmerged")
  func setF028ScrollsAtDifferentCellsDoNotMerge() throws {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(3)))
    #expect(pump.enqueue(scrolled(1, 1, x: 1)))
    #expect(!pump.enqueue(scrolled(1, 1, x: 5)))
    let batch = pump.drain()
    try #require(batch.count == 2)
    #expect(batch.map(\.arrival.count) == [1, 1])
  }

  @Test("setF029 a non-coalescible down opens a batch a following move cannot join")
  func setF029DownThenMoveStartsSecondBatch() {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(4)))
    #expect(
      pump.enqueue(.input(.mouse(MouseEvent(kind: .down(.primary), location: Point(x: 1, y: 1))))))
    #expect(pump.enqueue(moved(2)))
    #expect(pump.pendingBatchCount() == 2)
  }

  @Test("setF030 a move batch does not admit a following non-coalescible down")
  func setF030MoveThenDownStartsSecondBatch() {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(5)))
    #expect(pump.enqueue(moved(1)))
    #expect(
      pump.enqueue(.input(.mouse(MouseEvent(kind: .down(.primary), location: Point(x: 1, y: 1))))))
    #expect(pump.pendingBatchCount() == 2)
  }

  @Test("setF031 a key is a barrier that a following move cannot join")
  func setF031KeyThenMoveStartsSecondBatch() {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(6)))
    #expect(pump.enqueue(.input(.key(.character("a")))))
    #expect(pump.enqueue(moved(1)))
    #expect(pump.pendingBatchCount() == 2)
  }

  @Test("setF032 signals never coalesce and keep their order")
  func setF032SignalsNeverCoalesce() throws {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(7)))
    #expect(pump.enqueue(.signal("SIGWINCH")))
    #expect(pump.enqueue(.signal("SIGTERM")))
    #expect(pump.pendingBatchCount() == 2)
    let first = pump.drain()
    let second = pump.drain()
    try #require(first.count == 1)
    try #require(second.count == 1)
    guard case .signal(let a) = first[0].event, case .signal(let b) = second[0].event else {
      Issue.record("expected two queued signals")
      return
    }
    #expect(a == "SIGWINCH")
    #expect(b == "SIGTERM")
  }

  @Test("setF033 input-end is a barrier after a coalescible pointer batch")
  func setF033InputEndBarrier() {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(8)))
    #expect(pump.enqueue(moved(1)))
    #expect(pump.enqueue(.inputEnded))
    #expect(pump.pendingBatchCount() == 2)
  }

  @Test("setF034 an overflowing scroll merge is refused and ships as two events")
  func setF034ScrollOverflowIsNotMerged() throws {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(9)))
    #expect(pump.enqueue(scrolled(0, Int.max)))
    #expect(!pump.enqueue(scrolled(0, 1)))
    let batch = pump.drain()
    try #require(batch.count == 2)
    #expect(batch.map(\.arrival.id) == [0, 1])
  }

  @Test("setF035 drags merge only for the same button")
  func setF035DragsMergeOnlyForSameButton() throws {
    let same = buffer(at: MonotonicInstant(offset: .seconds(10)))
    #expect(
      same.enqueue(
        .input(.mouse(MouseEvent(kind: .dragged(.primary), location: Point(x: 1, y: 1))))))
    #expect(
      !same.enqueue(
        .input(.mouse(MouseEvent(kind: .dragged(.primary), location: Point(x: 2, y: 1))))))
    #expect(same.drain().count == 1)

    let mixed = buffer(at: MonotonicInstant(offset: .seconds(11)))
    #expect(
      mixed.enqueue(
        .input(.mouse(MouseEvent(kind: .dragged(.primary), location: Point(x: 1, y: 1))))))
    #expect(
      !mixed.enqueue(
        .input(.mouse(MouseEvent(kind: .dragged(.secondary), location: Point(x: 2, y: 1))))))
    try #require(mixed.drain().count == 2)
  }

  @Test("setF036 a cancelled pointer is a barrier a following move cannot join")
  func setF036CancelledIsBarrier() {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(12)))
    #expect(pump.enqueue(.input(.mouse(MouseEvent(kind: .cancelled, location: Point(x: 1, y: 1))))))
    #expect(pump.enqueue(moved(1)))
    #expect(pump.pendingBatchCount() == 2)
  }

  @Test("setF037 alternating pointer kinds keep one batch and every arrival")
  func setF037AlternatingKindsKeepOneBatch() throws {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(13)))
    #expect(pump.enqueue(moved(1)))
    #expect(!pump.enqueue(scrolled(0, 1)))
    #expect(!pump.enqueue(moved(2)))
    #expect(pump.pendingBatchCount() == 1)
    let batch = pump.drain()
    try #require(batch.count == 3)
    #expect(batch.map(\.arrival.id) == [0, 1, 2])
    #expect(batch.reduce(0) { $0 + $1.arrival.count } == 3)
  }

  @Test("setF038 oldest pending arrival tracks the head batch across drains")
  func setF038OldestPendingArrivalTracksHead() throws {
    let instant = MonotonicInstant(offset: .seconds(5))
    let pump = EventPumpBuffer(clock: { instant })
    #expect(pump.oldestPendingArrival() == nil)
    #expect(pump.enqueue(.input(.key(.character("a")))))
    #expect(pump.enqueue(.input(.key(.character("b")))))
    #expect(pump.pendingBatchCount() == 2)
    #expect(pump.oldestPendingArrival() == instant)
    _ = pump.drain()
    #expect(pump.oldestPendingArrival() == instant)
    _ = pump.drain()
    #expect(pump.oldestPendingArrival() == nil)
    #expect(!pump.hasPendingEvents())
  }

  @Test("setF039 a merged pointer pair fuses first and last across the clock")
  func setF039MergedPairFusesFirstAndLast() throws {
    let first = MonotonicInstant(offset: .seconds(5))
    let last = first.advanced(by: .milliseconds(9))
    let readings = [first, last]
    let index = Mutex(0)
    let pump = EventPumpBuffer(clock: {
      index.withLock { current in
        let value = readings[Swift.min(current, readings.count - 1)]
        current += 1
        return value
      }
    })
    #expect(pump.enqueue(moved(1)))
    #expect(!pump.enqueue(moved(2)))
    let batch = pump.drain()
    try #require(batch.count == 1)
    #expect(batch[0].arrival.id == 0)
    #expect(batch[0].arrival.count == 2)
    #expect(batch[0].arrival.first == first)
    #expect(batch[0].arrival.last == last)
  }

  @Test("setF040 non-coalescible events drain in FIFO order and then empty")
  func setF040FifoDrainThenEmpty() throws {
    let pump = buffer(at: MonotonicInstant(offset: .seconds(14)))
    #expect(pump.enqueue(.input(.key(.character("a")))))
    #expect(pump.enqueue(.input(.key(.character("b")))))
    #expect(pump.enqueue(.input(.key(.character("c")))))
    #expect(pump.pendingBatchCount() == 3)
    var characters: [Character] = []
    while pump.hasPendingEvents() {
      let batch = pump.drain()
      try #require(batch.count == 1)
      guard case .input(.key(let press)) = batch[0].event,
        case .character(let character) = press.key
      else {
        Issue.record("expected a queued key")
        return
      }
      characters.append(character)
    }
    #expect(characters == ["a", "b", "c"])
    #expect(pump.drain().isEmpty)
  }
}
