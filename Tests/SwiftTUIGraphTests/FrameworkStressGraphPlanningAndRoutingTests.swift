import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("SwiftTUIGraph planning and routing stress behavior", .serialized)
struct FrameworkStressGraphPlanningAndRoutingTests {
  @Test("stress graph planning 001 dirty work requires a rooted graph")
  func graphPlanning001DirtyWorkRequiresRootedGraph() {
    let node = planningNode(1, "Leaf", evaluator: true)

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: false, dirty: [node], nodes: [node])
    )

    #expect(planning.plan == nil)
  }

  @Test("stress graph planning 002 empty dirty queue produces no target plan")
  func graphPlanning002EmptyDirtyQueueProducesNoTargetPlan() {
    let node = planningNode(1, "Root", evaluator: true)

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: true, dirty: [], nodes: [node])
    )

    #expect(planning.plan == nil)
  }

  @Test("stress graph planning 003 unknown dirty ID cannot suppress live target")
  func graphPlanning003UnknownDirtyIDCannotSuppressLiveTarget() {
    let node = planningNode(1, "Live", evaluator: true)
    let input = ViewGraphDirtyEvaluationPlanningInput(
      hasRoot: true,
      graphLocalDirtyNodeIDs: [node.viewNodeID, ViewNodeID(rawValue: 999)],
      nodesByNodeID: [node.viewNodeID: node],
      lifecycleEvaluationOwnersByNodeID: [:]
    )

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(input: input)

    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [node.viewNodeID])
  }

  @Test("stress graph planning 004 queued clean node is ignored")
  func graphPlanning004QueuedCleanNodeIsIgnored() {
    let node = planningNode(1, "Clean", evaluator: true)
    node.isDirty = false

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: true, dirty: [node], nodes: [node])
    )

    #expect(planning.plan == nil)
  }

  @Test("stress graph planning 005 queued dirty ancestor collapses descendant frontier")
  func graphPlanning005QueuedDirtyAncestorCollapsesDescendantFrontier() {
    let parent = planningNode(1, "Root", "Parent", evaluator: true)
    let child = planningNode(2, "Root", "Parent", "Child", evaluator: true)
    connectPlanningNode(parent, children: [child])
    parent.markDirty()
    child.markDirty()

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: true, dirty: [parent, child], nodes: [parent, child])
    )

    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [parent.viewNodeID])
  }

  @Test("stress graph planning 006 unqueued dirty ancestor cannot strand descendant")
  func graphPlanning006UnqueuedDirtyAncestorCannotStrandDescendant() {
    let parent = planningNode(1, "Root", "Parent", evaluator: true)
    let child = planningNode(2, "Root", "Parent", "Child", evaluator: true)
    connectPlanningNode(parent, children: [child])
    parent.markDirty()
    child.markDirty()

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: true, dirty: [child], nodes: [parent, child])
    )

    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [child.viewNodeID])
  }

  @Test("stress graph planning 007 parentless island walks through evaluation host")
  func graphPlanning007ParentlessIslandWalksThroughEvaluationHost() {
    let host = planningNode(1, "Root", "Host", evaluator: true)
    let island = planningNode(2, "Island", evaluator: false)
    establishEvaluationHost(host: host, island: island)
    island.markDirty()

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: true, dirty: [island], nodes: [host, island])
    )

    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [host.viewNodeID])
  }

  @Test("stress graph planning 008 evaluator below island seam is not stitchable")
  func graphPlanning008EvaluatorBelowIslandSeamIsNotStitchable() {
    let host = planningNode(1, "Root", "Host", evaluator: true)
    let islandRoot = planningNode(2, "Island", evaluator: false)
    let leaf = planningNode(3, "Island", "Leaf", evaluator: true)
    connectPlanningNode(islandRoot, children: [leaf])
    establishEvaluationHost(host: host, island: islandRoot)
    leaf.markDirty()

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: true, dirty: [leaf], nodes: [host, islandRoot, leaf])
    )

    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [host.viewNodeID])
  }

  @Test("stress graph planning 009 lifecycle ownership redirects evaluation")
  func graphPlanning009LifecycleOwnershipRedirectsEvaluation() {
    let owner = planningNode(1, "Root", "Owner", evaluator: true)
    let dirty = planningNode(2, "Root", "Dirty", evaluator: true)
    dirty.markDirty()
    let input = planningInput(
      hasRoot: true,
      dirty: [dirty],
      nodes: [owner, dirty],
      lifecycleOwners: [dirty.viewNodeID: owner.viewNodeID]
    )

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(input: input)

    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [owner.viewNodeID])
  }

  @Test("stress graph planning 010 lifecycle owner below seam hoists above host")
  func graphPlanning010LifecycleOwnerBelowSeamHoistsAboveHost() {
    let host = planningNode(1, "Root", "Host", evaluator: true)
    let owner = planningNode(2, "Island", "Owner", evaluator: true)
    let dirty = planningNode(3, "Island", "Owner", "Dirty", evaluator: true)
    connectPlanningNode(owner, children: [dirty])
    establishEvaluationHost(host: host, island: owner)
    dirty.markDirty()
    let input = planningInput(
      hasRoot: true,
      dirty: [dirty],
      nodes: [host, owner, dirty],
      lifecycleOwners: [dirty.viewNodeID: owner.viewNodeID]
    )

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(input: input)

    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [host.viewNodeID])
  }

  @Test("stress graph planning 011 shared evaluator is emitted once")
  func graphPlanning011SharedEvaluatorIsEmittedOnce() {
    let parent = planningNode(1, "Root", "Parent", evaluator: true)
    let left = planningNode(2, "Root", "Parent", "Left", evaluator: false)
    let right = planningNode(3, "Root", "Parent", "Right", evaluator: false)
    connectPlanningNode(parent, children: [left, right])
    left.markDirty()
    right.markDirty()

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: true, dirty: [left, right], nodes: [parent, left, right])
    )

    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [parent.viewNodeID])
  }

  @Test("stress graph planning 012 target ordering is depth then identity")
  func graphPlanning012TargetOrderingIsDepthThenIdentity() {
    let deep = planningNode(1, "Root", "Z", "Deep", evaluator: true)
    let shallowZ = planningNode(2, "Root", "Z", evaluator: true)
    let shallowA = planningNode(3, "Root", "A", evaluator: true)

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(
        hasRoot: true,
        dirty: [deep, shallowZ, shallowA],
        nodes: [deep, shallowZ, shallowA]
      )
    )

    #expect(
      planning.plan?.targetNodes.map(\.identity) == [shallowA.identity, shallowZ.identity, deep.identity]
    )
  }

  @Test("stress graph planning 013 invalidate unions ledger and dirties only live nodes")
  func graphPlanning013InvalidateUnionsLedgerAndDirtiesOnlyLiveNodes() {
    let live = planningNode(1, "Live", evaluator: false)
    live.isDirty = false
    let prior = ViewNodeID(rawValue: 40)
    let missing = ViewNodeID(rawValue: 41)
    var invalidated: Set<ViewNodeID> = [prior]

    ViewGraphInvalidationPlanner.invalidate(
      [live.viewNodeID, missing],
      invalidatedNodeIDs: &invalidated,
      nodesByNodeID: [live.viewNodeID: live]
    )

    #expect(invalidated == [prior, live.viewNodeID, missing])
    #expect(live.isDirty)
  }

  @Test("stress graph planning 014 invalidate and queue excludes missing node from queue")
  func graphPlanning014InvalidateAndQueueExcludesMissingNodeFromQueue() {
    let live = planningNode(1, "Live", evaluator: false)
    live.isDirty = false
    let missing = ViewNodeID(rawValue: 99)
    var invalidated: Set<ViewNodeID> = []
    var queued: Set<ViewNodeID> = []

    ViewGraphInvalidationPlanner.invalidateAndQueueDirty(
      [live.viewNodeID, missing],
      invalidatedNodeIDs: &invalidated,
      graphLocalDirtyNodeIDs: &queued,
      nodesByNodeID: [live.viewNodeID: live]
    )

    #expect(invalidated == [live.viewNodeID, missing])
    #expect(queued == [live.viewNodeID])
    #expect(live.isDirty)
  }

  @Test("stress graph planning 015 stale queued ID remains harmless beside live target")
  func graphPlanning015StaleQueuedIDRemainsHarmlessBesideLiveTarget() {
    let live = planningNode(1, "Live", evaluator: true)
    live.isDirty = false
    let missing = ViewNodeID(rawValue: 99)
    var queued: Set<ViewNodeID> = []

    ViewGraphInvalidationPlanner.queueDirty(
      [live.viewNodeID, missing],
      graphLocalDirtyNodeIDs: &queued,
      nodesByNodeID: [live.viewNodeID: live]
    )
    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: ViewGraphDirtyEvaluationPlanningInput(
        hasRoot: true,
        graphLocalDirtyNodeIDs: queued,
        nodesByNodeID: [live.viewNodeID: live],
        lifecycleEvaluationOwnersByNodeID: [:]
      )
    )

    #expect(queued == [live.viewNodeID, missing])
    #expect(planning.plan?.targetNodes.map(\.viewNodeID) == [live.viewNodeID])
  }

  @Test("stress graph planning 016 environment fanout unions disjoint roots and keys")
  func graphPlanning016EnvironmentFanoutUnionsDisjointRootsAndKeys() {
    let keyA = ObjectIdentifier(GraphPlanningEnvironmentKeyA.self)
    let keyB = ObjectIdentifier(GraphPlanningEnvironmentKeyB.self)
    let first = ViewNodeID(rawValue: 1)
    let second = ViewNodeID(rawValue: 2)
    let excluded = ViewNodeID(rawValue: 3)

    let result = ViewGraphInvalidationPlanner.environmentReaderDirtyNodeIDs(
      within: [testIdentity("Root", "A"), testIdentity("Root", "B")],
      changedKeys: [keyA, keyB],
      environmentDependents: [keyA: [first, excluded], keyB: [second]],
      identityByNodeID: [
        first: testIdentity("Root", "A", "Leaf"),
        second: testIdentity("Root", "B"),
        excluded: testIdentity("Root", "C"),
      ]
    )

    #expect(result == [first, second])
  }

  @Test("stress graph planning 017 dependency reindex replaces every family atomically")
  func graphPlanning017DependencyReindexReplacesEveryFamilyAtomically() {
    let nodeID = ViewNodeID(rawValue: 7)
    let stateA = StateSlotKey(owner: ViewNodeID(rawValue: 1), ordinal: 0)
    let stateB = StateSlotKey(owner: ViewNodeID(rawValue: 2), ordinal: 1)
    let environmentShared = ObjectIdentifier(GraphPlanningEnvironmentKeyA.self)
    let observableOld = ObjectIdentifier(GraphPlanningObservableA.self)
    let observableNew = ObjectIdentifier(GraphPlanningObservableB.self)
    var stateIndex = [stateA: Set([nodeID])]
    var environmentIndex = [environmentShared: Set([nodeID])]
    var observableIndex = [observableOld: Set([nodeID])]

    ViewGraphDependencyIndex.reindex(
      viewNodeID: nodeID,
      previous: .init(
        stateSlotReads: [stateA],
        environmentReads: [environmentShared],
        observableReads: [observableOld]
      ),
      current: .init(
        stateSlotReads: [stateB],
        environmentReads: [environmentShared],
        observableReads: [observableNew]
      ),
      stateSlotDependents: &stateIndex,
      environmentDependents: &environmentIndex,
      observableDependents: &observableIndex
    )

    #expect(stateIndex == [stateB: [nodeID]])
    #expect(environmentIndex == [environmentShared: [nodeID]])
    #expect(observableIndex == [observableNew: [nodeID]])
  }

  @Test("stress graph planning 018 entity move clears old reverse binding")
  func graphPlanning018EntityMoveClearsOldReverseBinding() {
    let entity = EntityIdentity("entity")
    let oldNode = ViewNodeID(rawValue: 1)
    let newNode = ViewNodeID(rawValue: 2)
    var table = EntityRoutingTable()
    table.bind(entity, to: oldNode)

    table.bind(entity, to: newNode)

    #expect(table.route(entity) == newNode)
    #expect(table.entityByNodeID[oldNode] == nil)
    #expect(table.entityByNodeID[newNode] == entity)
  }

  @Test("stress graph planning 019 new entity claim clears old forward route")
  func graphPlanning019NewEntityClaimClearsOldForwardRoute() {
    let oldEntity = EntityIdentity("old")
    let newEntity = EntityIdentity("new")
    let node = ViewNodeID(rawValue: 1)
    var table = EntityRoutingTable()
    table.bind(oldEntity, to: node)

    table.bind(newEntity, to: node)

    #expect(table.route(oldEntity) == nil)
    #expect(table.route(newEntity) == node)
    #expect(table.entityByNodeID[node] == newEntity)
  }

  @Test("stress graph planning 020 cross rebind leaves strict bijection")
  func graphPlanning020CrossRebindLeavesStrictBijection() {
    let entityA = EntityIdentity("A")
    let entityB = EntityIdentity("B")
    let node1 = ViewNodeID(rawValue: 1)
    let node2 = ViewNodeID(rawValue: 2)
    var table = EntityRoutingTable()
    table.bind(entityA, to: node1)
    table.bind(entityB, to: node2)

    table.bind(entityA, to: node2)

    #expect(table.nodeIDByEntity == [entityA: node2])
    #expect(table.entityByNodeID == [node2: entityA])
  }

  @Test("stress graph planning 021 releasing unknown node is a no op")
  func graphPlanning021ReleasingUnknownNodeIsNoOp() {
    let entity = EntityIdentity("entity")
    let node = ViewNodeID(rawValue: 1)
    var table = EntityRoutingTable()
    table.bind(entity, to: node)
    let before = table

    table.release(ViewNodeID(rawValue: 99))

    #expect(table == before)
  }

  @Test("stress graph planning 022 inactive entity release preserves active bijection")
  func graphPlanning022InactiveEntityReleasePreservesActiveBijection() {
    let active = EntityIdentity("active")
    let stale = EntityIdentity("stale")
    let activeNode = ViewNodeID(rawValue: 1)
    let staleNode = ViewNodeID(rawValue: 2)
    var table = EntityRoutingTable()
    table.bind(active, to: activeNode)
    table.bind(stale, to: staleNode)

    table.releaseEntities(notIn: [active])

    #expect(table.nodeIDByEntity == [active: activeNode])
    #expect(table.entityByNodeID == [activeNode: active])
  }

  @Test("stress graph planning 023 nonlive node release preserves live bijection")
  func graphPlanning023NonliveNodeReleasePreservesLiveBijection() {
    let live = EntityIdentity("live")
    let stale = EntityIdentity("stale")
    let liveNode = ViewNodeID(rawValue: 1)
    let staleNode = ViewNodeID(rawValue: 2)
    var table = EntityRoutingTable()
    table.bind(live, to: liveNode)
    table.bind(stale, to: staleNode)

    table.releaseNodes(notIn: [liveNode])

    #expect(table.nodeIDByEntity == [live: liveNode])
    #expect(table.entityByNodeID == [liveNode: live])
  }

  @Test("stress graph planning 024 removal plan ignores stale old index")
  func graphPlanning024RemovalPlanIgnoresStaleOldIndex() {
    let old = [
      planningDescriptor("Root", "First"),
      planningDescriptor("Root", "Stale"),
    ]
    let committed = [planningResolvedNode("Root", "First")]
    let new = [planningResolvedNode("Root", "First")]

    let plan = ViewGraphStructuralReconciler.removalPlan(
      oldChildDescriptors: old,
      currentChildCount: 1,
      committedChildren: committed,
      newChildren: new
    )

    #expect(plan.removedChildren.isEmpty)
  }

  @Test("stress graph planning 025 live removal tolerates missing committed snapshot")
  func graphPlanning025LiveRemovalToleratesMissingCommittedSnapshot() {
    let old = [planningDescriptor("Root", "Departing")]

    let plan = ViewGraphStructuralReconciler.removalPlan(
      oldChildDescriptors: old,
      currentChildCount: 1,
      committedChildren: [],
      newChildren: []
    )

    #expect(plan.removedChildren.count == 1)
    #expect(plan.removedChildren.first?.oldIndex == 0)
    #expect(plan.removedChildren.first?.committedSnapshot == nil)
  }

  @Test("stress graph planning 026 target-less frontier node cannot form a silent partial plan")
  func graphPlanning026TargetlessFrontierNodeCannotFormSilentPartialPlan() {
    // A dirty frontier node with no stitchable evaluator anywhere on its
    // chain has no target. Dropping just that node forms a plan covering
    // LESS than the queued dirty work — `finalizeFrame` then wipes the
    // dirty rails and the orphan's re-evaluation is silently lost for the
    // session (F160). The plan must escalate (nil → root evaluation), never
    // proceed partially.
    let live = planningNode(1, "Root", "Live", evaluator: true)
    let orphan = planningNode(2, "Orphan", evaluator: false)
    live.markDirty()
    orphan.markDirty()
    let escalationsBefore =
      SoundnessProbeConfiguration.plannerTargetlessFrontierEscalationCount

    let planning = ViewGraphDirtyEvaluationPlanner.targetPlan(
      input: planningInput(hasRoot: true, dirty: [live, orphan], nodes: [live, orphan])
    )

    #expect(
      planning.plan == nil,
      "a target-less frontier node must escalate the whole plan to root evaluation, not drop the node from a partial plan"
    )
    #expect(planning.droppedTargetlessNodeCount == 1)
    #expect(
      SoundnessProbeConfiguration.plannerTargetlessFrontierEscalationCount
        == escalationsBefore + 1
    )
  }
}

private enum GraphPlanningEnvironmentKeyA {}
private enum GraphPlanningEnvironmentKeyB {}
private final class GraphPlanningObservableA {}
private final class GraphPlanningObservableB {}

@MainActor
private func planningNode(
  _ rawID: UInt64,
  _ components: String...,
  evaluator: Bool
) -> ViewNode {
  let node = ViewNode(
    viewNodeID: ViewNodeID(rawValue: rawID),
    identity: Identity(components: components)
  )
  if evaluator {
    node.setEvaluator {}
  }
  return node
}

@MainActor
private func connectPlanningNode(
  _ parent: ViewNode,
  children: [ViewNode]
) {
  parent.apply(
    resolved: ResolvedNode(
      identity: parent.identity,
      kind: .view("PlanningNode"),
      children: children.map { child in
        ResolvedNode(identity: child.identity, kind: .view("PlanningChild"))
      }
    ),
    children: children
  )
}

@MainActor
private func establishEvaluationHost(
  host: ViewNode,
  island: ViewNode
) {
  ViewNodeContext.withCurrentValue(host) {
    island.beginEvaluation(frameID: 1, invalidator: nil)
    _ = island.finishEvaluation(accessedStateSlots: 0)
  }
}

@MainActor
private func planningInput(
  hasRoot: Bool,
  dirty: [ViewNode],
  nodes: [ViewNode],
  lifecycleOwners: [ViewNodeID: ViewNodeID] = [:]
) -> ViewGraphDirtyEvaluationPlanningInput {
  ViewGraphDirtyEvaluationPlanningInput(
    hasRoot: hasRoot,
    graphLocalDirtyNodeIDs: Set(dirty.map(\.viewNodeID)),
    nodesByNodeID: Dictionary(uniqueKeysWithValues: nodes.map { ($0.viewNodeID, $0) }),
    lifecycleEvaluationOwnersByNodeID: lifecycleOwners
  )
}

private func planningDescriptor(
  _ components: String...
) -> ChildDescriptor {
  ChildDescriptor(
    identity: Identity(components: components),
    typeIdentity: "view:PlanningChild"
  )
}

private func planningResolvedNode(
  _ components: String...
) -> ResolvedNode {
  ResolvedNode(
    identity: Identity(components: components),
    kind: .view("PlanningChild")
  )
}
