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

  @Test("overlay capture carries baseline owners and excludes draft-minted owners")
  @MainActor
  func overlayCaptureExcludesDraftMintedOwners() {
    // Gallery fuzzer find (2026-07-16, `--tab animations`, zero input): a
    // `@Namespace` allocation — a resolve-time lazy state write into a node
    // minted by the pending draft — was carried across the draft's discard,
    // and its vanished owner tripped the F93 drop alarm on every boot of an
    // animating tab. Input events dispatch against committed trees, so a
    // draft-minted owner's write is never preservable: capture must skip it
    // (the replayed resolve regenerates it), while a baseline-present
    // owner's in-flight write must still restore alarm-free.
    let graph = ViewGraph()
    graph.beginFrame()
    let baselineNode = graph.beginEvaluation(
      identity: testIdentity("Root", "Stable"),
      invalidator: nil
    )
    let baselineSeed: Int = 1
    _ = baselineNode.stateSlot(ordinal: 0, seed: baselineSeed)
    let checkpoint = graph.makeCheckpoint()

    let draftNode = graph.beginEvaluation(
      identity: testIdentity("Root", "DraftMinted"),
      invalidator: nil
    )
    let draftSeed: Int = 5
    _ = draftNode.stateSlot(ordinal: 0, seed: draftSeed)
    baselineNode.restoreStateSlot(ordinal: 0, slot: AnyStateSlot(42))
    graph.queueDirtyForStateChange(
      StateSlotKey(owner: baselineNode.viewNodeID, ordinal: 0)
    )
    draftNode.restoreStateSlot(ordinal: 0, slot: AnyStateSlot(99))
    graph.queueDirtyForStateChange(
      StateSlotKey(owner: draftNode.viewNodeID, ordinal: 0)
    )

    let overlay = graph.stateMutationOverlay(restorableInto: checkpoint)
    let baselineKey = StateMutationSlotKey(
      key: StateSlotKey(owner: baselineNode.viewNodeID, ordinal: 0)
    )
    let draftKey = StateMutationSlotKey(
      key: StateSlotKey(owner: draftNode.viewNodeID, ordinal: 0)
    )
    #expect(overlay.stateSlots[baselineKey] != nil)
    #expect(
      overlay.stateSlots[draftKey] == nil,
      "a draft-minted owner's write must die with the draft, not ride the overlay"
    )

    let dropCount = SoundnessProbeConfiguration.stateSlotRestorationDropCount
    let detail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.stateSlotRestorationDropCount = dropCount
      SoundnessProbeConfiguration.lastViolationDetail = detail
    }
    _ = graph.restoreCheckpoint(checkpoint)
    graph.applyStateMutationOverlay(overlay)

    #expect(
      SoundnessProbeConfiguration.stateSlotRestorationDropCount == dropCount,
      "a baseline-filtered overlay must apply without tripping the drop alarm"
    )
    let restoredOwner = graph.nodeIfExists(for: baselineNode.viewNodeID)
    #expect(restoredOwner != nil)
    var restoredValue: Int = -1
    if let restoredOwner {
      let sentinel: Int = -1
      restoredValue = restoredOwner.stateSlot(ordinal: 0, seed: sentinel)
    }
    #expect(
      restoredValue == 42,
      "the baseline owner's in-flight write must survive the restore"
    )
  }

  @Test("overlay application unions the dirty and invalidation bookkeeping")
  @MainActor
  func overlayApplicationUnionsBookkeeping() {
    // F112 (pairs with the F93 drop-alarm test): the overlay's whole point
    // is carrying in-flight invalidation intent across a discarded draft —
    // the slot restore without the set unions would restore values that
    // nothing re-evaluates.
    let graph = ViewGraph()
    graph.beginFrame()
    let identity = testIdentity("Root", "Owner")
    let node = graph.beginEvaluation(identity: identity, invalidator: nil)
    let key = StateSlotKey(owner: node.viewNodeID, ordinal: 0)

    graph.applyStateMutationOverlay(
      ViewGraph.StateMutationOverlay(
        stateSlots: [:],
        invalidatedNodeIDs: [node.viewNodeID],
        graphLocalDirtyNodeIDs: [node.viewNodeID],
        stateMutationKeys: [key],
        stateMutationNodeIDsByKey: [key: [node.viewNodeID]]
      )
    )

    #expect(graph.invalidatedNodeIDs.contains(node.viewNodeID))
    #expect(graph.graphLocalDirtyNodeIDs.contains(node.viewNodeID))
    #expect(graph.stateMutationKeys.contains(key))
    #expect(graph.stateMutationNodeIDsByKey[key]?.contains(node.viewNodeID) == true)
  }
}

/// Pins the `.task(id:)` identity-slot contract (F112): the slot's stable
/// label is what keeps an unchanged `.task(id:)` from being cancelled and
/// restarted every pass — the stale-seed `.task` regression family.
@MainActor
@Suite("Task descriptor identity slots")
struct TaskDescriptorIdentitySlotTests {
  @Test("an unchanged id value keeps its stable label across passes")
  func unchangedValueKeepsLabel() {
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: testIdentity("Root", "Tasker"), invalidator: nil)

    let first = graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 0, value: 42)
    let second = graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 0, value: 42)
    #expect(first == second, "an unchanged id must not plan a cancel + restart")
  }

  @Test("a changed id value mints a new label")
  func changedValueMintsNewLabel() {
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: testIdentity("Root", "Tasker"), invalidator: nil)

    let first = graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 0, value: 1)
    let second = graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 0, value: 2)
    #expect(first != second)
  }

  @Test("a same-looking value of a different type mints a new label")
  func typeConfusionMintsNewLabel() {
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: testIdentity("Root", "Tasker"), invalidator: nil)

    let intLabel = graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 0, value: 1)
    let stringLabel = graph.taskDescriptorIdentityLabel(
      for: node.viewNodeID, ordinal: 0, value: "1"
    )
    #expect(intLabel != stringLabel, "the slot's type-erased equality must not cross types")
  }

  @Test("ordinals on one node hold independent slots")
  func ordinalsAreIndependent() {
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: testIdentity("Root", "Tasker"), invalidator: nil)

    let zero = graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 0, value: 7)
    let one = graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 1, value: 7)
    #expect(zero != one, "two .task(id:) modifiers on one node must not share a slot")
    // Both remain stable on re-query.
    #expect(graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 0, value: 7) == zero)
    #expect(graph.taskDescriptorIdentityLabel(for: node.viewNodeID, ordinal: 1, value: 7) == one)
  }
}
