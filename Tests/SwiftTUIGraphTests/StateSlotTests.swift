import Testing

@testable import SwiftTUIGraph

@Suite
struct StateSlotTests {
  @Test("equatable state slot preserves type and reports real changes")
  func equatableStateSlotTracksChanges() {
    var slot = AnyStateSlot(1)

    let initial: Int = slot.value(as: Int.self)
    let unchanged = slot.set(1)
    let changed = slot.set(2)
    let updated: Int = slot.value(as: Int.self)

    #expect(initial == 1)
    #expect(!unchanged)
    #expect(changed)
    #expect(updated == 2)
  }

  @Test("uninitialized slot can be filled lazily")
  func uninitializedSlotInitializesLazily() {
    var slot = AnyStateSlot()
    slot.initializeIfNeeded(with: "hello")

    let value: String = slot.value(as: String.self)
    #expect(value == "hello")
  }
}
