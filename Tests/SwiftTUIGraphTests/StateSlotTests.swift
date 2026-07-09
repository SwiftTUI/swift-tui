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

  @Test("overlay restoration onto a vanished owner raises the drop alarm; live owners restore")
  @MainActor
  func overlayRestorationOntoVanishedOwnerRaisesDropAlarm() {
    // F93: the state-mutation overlay carries in-flight user writes across a
    // discarded async frame draft. A vanished owner used to drop the write
    // with no signal — the F63/F43 lost-write class. The drop now raises
    // `stateSlotRestorationDropCount`; a live owner's restoration must be
    // unaffected by a dropped sibling entry.
    let graph = ViewGraph()
    graph.beginFrame()
    let identity = testIdentity("Root", "Owner")
    let node = graph.beginEvaluation(identity: identity, invalidator: nil)

    let dropCount = SoundnessProbeConfiguration.stateSlotRestorationDropCount
    let detail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.stateSlotRestorationDropCount = dropCount
      SoundnessProbeConfiguration.lastViolationDetail = detail
    }

    let liveKey = StateMutationSlotKey(key: StateSlotKey(owner: node.viewNodeID, ordinal: 0))
    let vanishedKey = StateMutationSlotKey(
      key: StateSlotKey(owner: ViewNodeID(rawValue: 999_999), ordinal: 0)
    )
    graph.applyStateMutationOverlay(
      ViewGraph.StateMutationOverlay(
        stateSlots: [liveKey: AnyStateSlot(7), vanishedKey: AnyStateSlot(9)],
        invalidatedNodeIDs: [],
        graphLocalDirtyNodeIDs: [],
        stateMutationKeys: [],
        stateMutationNodeIDsByKey: [:]
      )
    )

    #expect(SoundnessProbeConfiguration.stateSlotRestorationDropCount == dropCount + 1)
    #expect(
      SoundnessProbeConfiguration.lastViolationDetail?.contains("no longer exists") == true
    )
    #expect(
      node.stateSlot(ordinal: 0, seed: 0) == 7,
      "a dropped sibling entry must not disturb the live owner's restoration"
    )
  }
}
