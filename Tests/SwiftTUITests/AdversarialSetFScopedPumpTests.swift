import SwiftTUICore
import Synchronization
import Testing

@testable import SwiftTUIRuntime

@Suite("set F scoped pump provenance")
struct AdversarialSetFScopedPumpTests {
  @Test(arguments: Array(1...24))
  func scopedPointerPair(id: Int) throws {
    let wheel = id > 12
    let row = (id - 1) % 12
    let leaseCase = row / 2
    let sameOrigin = row % 2 == 0
    let first = InputConnectionLease()
    let second = InputConnectionLease()
    if leaseCase == 5 { first.retire() }
    let firstLease: InputConnectionLease? = [2, 3].contains(leaseCase) ? nil : first
    let secondLease: InputConnectionLease? =
      [2, 4].contains(leaseCase) ? nil : (leaseCase == 1 ? second : first)
    let shouldMerge = sameOrigin && [0, 2, 5].contains(leaseCase)
    let secondOrigin: InputOrigin = sameOrigin ? .terminal : .browser
    let released = Mutex<[Int]>([])
    let instant = MonotonicInstant(offset: .seconds(5))
    let buffer = EventPumpBuffer(clock: { instant })
    let a = MouseEvent(
      kind: wheel ? .scrolled(deltaX: 1, deltaY: 2) : .moved,
      location: Point(x: 1, y: 1), timestamp: instant
    )
    let b = MouseEvent(
      kind: wheel ? .scrolled(deltaX: 3, deltaY: 4) : .moved,
      location: Point(x: wheel ? 1 : 2, y: 1), timestamp: instant
    )
    func enqueue(_ event: MouseEvent, lease: InputConnectionLease?, origin: InputOrigin, slot: Int)
      -> Bool
    {
      buffer.enqueue(
        .scopedInput(
          .init(
            .mouse(event), origin: origin, lease: lease,
            admission: InputAdmission(release: { released.withLock { $0.append(slot) } })
          )))
    }
    #expect(enqueue(a, lease: firstLease, origin: .terminal, slot: 0))
    #expect(!enqueue(b, lease: secondLease, origin: secondOrigin, slot: 1))
    #expect(buffer.pendingBatchCount() == 1)
    #expect(released.withLock { $0 } == (shouldMerge ? [1] : []))
    first.retire()
    var batch = buffer.drain()
    #expect(!buffer.hasPendingEvents())
    #expect(buffer.oldestPendingArrival() == nil)
    try verify(
      batch, merged: shouldMerge, wheel: wheel, a: a, b: b,
      leases: [firstLease, secondLease],
      currents: [firstLease === nil, secondLease === nil || leaseCase == 1],
      secondOrigin: secondOrigin, instant: instant
    )
    #expect(released.withLock { $0 } == (shouldMerge ? [1] : []))
    batch.removeAll()
    #expect(released.withLock { $0.sorted() } == [0, 1])
  }

  private func verify(
    _ batch: [PumpedEvent], merged: Bool, wheel: Bool, a: MouseEvent, b: MouseEvent,
    leases: [InputConnectionLease?], currents: [Bool], secondOrigin: InputOrigin,
    instant: MonotonicInstant
  ) throws {
    try #require(batch.count == (merged ? 1 : 2))
    #expect(batch.map(\.arrival.id) == (merged ? [0] : [0, 1]))
    #expect(batch.map(\.arrival.count) == (merged ? [2] : [1, 1]))
    for (index, entry) in batch.enumerated() {
      guard case .scopedInput(let scoped) = entry.event,
        case .mouse(let mouse) = scoped.event
      else {
        Issue.record("The pump must retain scoped mouse provenance")
        return
      }
      #expect(scoped.origin == (index == 0 ? .terminal : secondOrigin))
      #expect(scoped.lease === leases[index])
      #expect(scoped.isCurrent == currents[index])
      #expect(entry.arrival.first == instant)
      #expect(entry.arrival.last == instant)
      if merged {
        #expect(mouse.location == b.location)
        #expect(mouse.kind == (wheel ? .scrolled(deltaX: 4, deltaY: 6) : .moved))
      } else {
        #expect(mouse == (index == 0 ? a : b))
      }
    }
  }
}
