import Testing

@testable import SwiftTUIGraph

#if DEBUG
  @MainActor
  @Suite("Body change provenance")
  struct BodyChangeTrackerTests {
    private struct Body {}

    @Test("causes coalesce, exact readers stay separate, and late writes survive")
    func coalescingAndReaders() {
      let graph = ViewGraph()
      let node = graph.prepareDynamicPropertyUpdate(identity: testIdentity("DebugBody"))
      let tracker = graph.debugBodyChanges
      let key = StateSlotKey(owner: node.ownerLifetimeID, ordinal: 1)
      tracker.beginOwner(node.ownerLifetimeID, initial: true)
      let first = tracker.makeScope(type: Body.self, kind: "view", node: node)
      first.run {
        #expect(first.record().causes.contains { $0.category == "identity" })
        first.stateRead(key)
      }
      tracker.finishOwner(node.ownerLifetimeID)
      tracker.note(.state(key), owner: node.ownerLifetimeID)
      tracker.note(.state(key), owner: node.ownerLifetimeID)
      tracker.beginOwner(node.ownerLifetimeID, initial: false)
      let next = tracker.makeScope(type: Body.self, kind: "view", node: node)
      next.run {
        let record = next.record()
        #expect(record.causes == [.init("state", precision: "exact")])
        #expect(next.record() == record)
        tracker.note(.observation, owner: node.ownerLifetimeID)
        #expect(next.record() == record, "entry evidence is immutable")
      }
      tracker.finishOwner(node.ownerLifetimeID)
      #expect(tracker.snapshot.pending[node.ownerLifetimeID]?.reasons.count == 1)
    }

    @Test("collapsed occurrences and graphs never share diagnostic history")
    func scopeIsolation() {
      let graph = ViewGraph()
      let other = ViewGraph()
      let node = graph.prepareDynamicPropertyUpdate(identity: testIdentity("DebugBody"))
      let otherNode = other.prepareDynamicPropertyUpdate(identity: testIdentity("DebugBody"))
      let tracker = graph.debugBodyChanges
      tracker.beginOwner(node.ownerLifetimeID, initial: true)
      let first = tracker.makeScope(type: Body.self, kind: "view", node: node)
      let second = tracker.makeScope(type: Body.self, kind: "modifier", node: node)
      first.run {
        #expect(BodyChangeScope.current === first)
        second.run { #expect(BodyChangeScope.current === second) }
        #expect(BodyChangeScope.current === first)
      }
      #expect(BodyChangeScope.current == nil)
      #expect(first.key != second.key)
      other.debugBodyChanges.beginOwner(otherNode.ownerLifetimeID, initial: true)
      let foreign = other.debugBodyChanges.makeScope(type: Body.self, kind: "view", node: otherNode)
      #expect(first.graph != foreign.graph)
    }

    @Test("checkpoint restoration retains causes but never rewinds attempt identity")
    func checkpointRollback() {
      let graph = ViewGraph()
      let node = graph.prepareDynamicPropertyUpdate(identity: testIdentity("DebugBody"))
      graph.debugBodyChanges.note(.observation, owner: node.ownerLifetimeID)
      let checkpoint = graph.makeCheckpoint()
      graph.debugBodyChanges.beginOwner(node.ownerLifetimeID, initial: false)
      let aborted = graph.debugBodyChanges.makeScope(type: Body.self, kind: "view", node: node)
      aborted.run { _ = aborted.record() }
      graph.debugBodyChanges.finishOwner(node.ownerLifetimeID)
      #expect(graph.debugBodyChanges.snapshot.pending.isEmpty)
      graph.restoreCheckpoint(checkpoint)
      #expect(graph.debugBodyChanges.snapshot.histories.isEmpty)
      graph.debugBodyChanges.beginOwner(node.ownerLifetimeID, initial: false)
      let retry = graph.debugBodyChanges.makeScope(type: Body.self, kind: "view", node: node)
      #expect(retry.attempt > aborted.attempt)
      #expect(retry.record().causes.contains { $0.category == "observation" })
    }

    @Test("late enrollment does not invent precise dependency attribution")
    func lateEnrollment() {
      let graph = ViewGraph()
      let node = graph.prepareDynamicPropertyUpdate(identity: testIdentity("DebugBody"))
      let tracker = graph.debugBodyChanges
      tracker.beginOwner(node.ownerLifetimeID, initial: false)
      let scope = tracker.makeScope(type: Body.self, kind: "view", node: node)
      scope.run {
        scope.stateRead(.init(owner: node.ownerLifetimeID, ordinal: 1))
        #expect(scope.record().causes.contains { $0.category == "provenance-unavailable" })
      }
      #expect(tracker.snapshot.histories[scope.key]?.complete == false)
      tracker.remove(node.ownerLifetimeID)
      #expect(tracker.snapshot.histories.isEmpty)
      #expect(tracker.snapshot.entries.isEmpty)
    }

    @Test("recycled raw node IDs never inherit a discarded body's history")
    func recycledOwner() {
      let graph = ViewGraph()
      graph.beginFrame()
      let checkpoint = graph.makeCheckpoint()
      let identity = testIdentity("DebugRecycled")
      let old = graph.prepareDynamicPropertyUpdate(identity: identity)
      let tracker = graph.debugBodyChanges
      tracker.beginOwner(old.ownerLifetimeID, initial: true)
      let scope = tracker.makeScope(type: Body.self, kind: "view", node: old)
      scope.run { _ = scope.record() }
      tracker.note(.observation, owner: old.ownerLifetimeID)
      graph.restoreCheckpoint(checkpoint)
      let new = graph.prepareDynamicPropertyUpdate(identity: identity)
      #expect(new.viewNodeID == old.viewNodeID)
      #expect(new.ownerLifetimeID != old.ownerLifetimeID)
      tracker.beginOwner(new.ownerLifetimeID, initial: true)
      let replacement = tracker.makeScope(type: Body.self, kind: "view", node: new)
      #expect(replacement.prior == nil)
      #expect(!replacement.record().causes.contains { $0.category == "observation" })
      #expect(replacement.attempt > scope.attempt)
    }

    @Test("history churn and over-capacity writes remain bounded and uncertain")
    func churnAndOverflow() {
      let graph = ViewGraph()
      let node = graph.prepareDynamicPropertyUpdate(identity: testIdentity("DebugChurn"))
      let tracker = graph.debugBodyChanges
      tracker.beginOwner(node.ownerLifetimeID, initial: false)
      for _ in 0..<(BodyChangeTracker.maximumBodies + 10) {
        let scope = tracker.makeScope(type: Body.self, kind: "view", node: node)
        scope.run { _ = scope.record() }
        #expect(tracker.snapshot.histories.count <= BodyChangeTracker.maximumBodies)
      }
      #expect(tracker.snapshot.overflow)
      tracker.remove(node.ownerLifetimeID)
      #expect(tracker.snapshot.histories.isEmpty)
      for ordinal in 0..<64 {
        tracker.note(
          .state(.init(owner: node.ownerLifetimeID, ordinal: ordinal)), owner: node.ownerLifetimeID)
      }
      tracker.beginOwner(node.ownerLifetimeID, initial: false)
      tracker.note(.observation, owner: node.ownerLifetimeID)
      tracker.finishOwner(node.ownerLifetimeID)
      #expect(
        tracker.snapshot.pending[node.ownerLifetimeID]?.omitted == 1,
        "a dropped late write must survive entry consumption")
    }

    @Test("pending evidence stays bounded and reports omitted causes")
    func boundedCauses() {
      let tracker = BodyChangeTracker()
      let owner = NodeOwnerLifetimeID(rawValue: 1)
      for ordinal in 0..<100 {
        tracker.note(.state(.init(owner: owner, ordinal: ordinal)), owner: owner)
      }
      #expect(tracker.snapshot.pending[owner]?.reasons.count == BodyChangeTracker.maximumCauses)
      #expect(tracker.snapshot.pending[owner]?.omitted == 36)
      tracker.reused(owner)
      #expect(tracker.snapshot.pending.isEmpty)
    }
  }
#endif
