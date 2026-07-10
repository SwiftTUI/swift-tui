import Testing

@testable import SwiftTUIGraph

/// Direct units for the read-capture session (F111): `DependencyTracker`
/// decides which state/environment/observable reads register dependencies —
/// a capture bug is an under-invalidation (stale UI) generator — and was
/// previously exercised only through Views-layer resolution;
/// `DependencyTracker.Checkpoint` had no coverage at all.
@MainActor
@Suite("Dependency tracker")
struct DependencyTrackerTests {
  @Test("each read kind lands in the current capture set")
  func readsLandInCurrentSet() {
    let tracker = DependencyTracker()
    let slot = StateSlotKey(owner: ViewNodeID(rawValue: 1), ordinal: 0)
    let environmentKey = ObjectIdentifier(DependencyTrackerTests.self)
    let observableID = ObjectIdentifier(DependencyTracker.self)

    tracker.recordStateRead(slot)
    tracker.recordEnvironmentRead(environmentKey)
    tracker.recordObservableRead(observableID)
    tracker.recordFocusComparisonTargets([testIdentity("Root", "A")])
    tracker.recordFocusComparisonTargets([testIdentity("Root", "B")])

    let captured = tracker.currentDependencies
    #expect(captured.stateSlotReads == [slot])
    #expect(captured.environmentReads == [environmentKey])
    #expect(captured.observableReads == [observableID])
    #expect(
      captured.focusComparisonTargets
        == [testIdentity("Root", "A"), testIdentity("Root", "B")],
      "focus targets union across record calls"
    )
  }

  @Test("reset returns the captured session and starts the next one empty")
  func resetReturnsAndClears() {
    let tracker = DependencyTracker()
    let slot = StateSlotKey(owner: ViewNodeID(rawValue: 2), ordinal: 1)
    tracker.recordStateRead(slot)

    let captured = tracker.reset()
    #expect(captured.stateSlotReads == [slot])
    #expect(tracker.currentDependencies.stateSlotReads.isEmpty)

    // The returned set is a value: the tracker's next session cannot
    // retroactively mutate it.
    tracker.recordStateRead(StateSlotKey(owner: ViewNodeID(rawValue: 3), ordinal: 0))
    #expect(captured.stateSlotReads == [slot])
  }

  @Test("restoring a checkpoint discards reads recorded after it")
  func checkpointRestoreDiscardsLaterReads() {
    let tracker = DependencyTracker()
    let early = StateSlotKey(owner: ViewNodeID(rawValue: 4), ordinal: 0)
    let late = StateSlotKey(owner: ViewNodeID(rawValue: 4), ordinal: 1)

    tracker.recordStateRead(early)
    let checkpoint = tracker.makeCheckpoint()
    tracker.recordStateRead(late)
    #expect(tracker.currentDependencies.stateSlotReads == [early, late])

    tracker.restoreCheckpoint(checkpoint)
    #expect(
      tracker.currentDependencies.stateSlotReads == [early],
      "a restore rewinds the capture to the checkpointed session"
    )
  }

  @Test("a checkpoint is a value: later tracker mutation cannot corrupt it")
  func checkpointIsAValue() {
    let tracker = DependencyTracker()
    let early = StateSlotKey(owner: ViewNodeID(rawValue: 5), ordinal: 0)
    tracker.recordStateRead(early)

    let checkpoint = tracker.makeCheckpoint()
    tracker.recordStateRead(StateSlotKey(owner: ViewNodeID(rawValue: 5), ordinal: 1))
    _ = tracker.reset()

    #expect(checkpoint.currentDependencies.stateSlotReads == [early])
    tracker.restoreCheckpoint(checkpoint)
    #expect(tracker.currentDependencies.stateSlotReads == [early])
  }
}
