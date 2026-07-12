import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("SwiftTUIGraph viewport lifecycle planning stress behavior", .serialized)
struct FrameworkStressViewportLifecyclePlanningTests {
  @Test("stress viewport lifecycle 001 duplicate stable cancel is emitted once")
  func viewportLifecycle001DuplicateStableCancelIsEmittedOnce() {
    let task = lifecycleTask("load")
    var stableCancels: [LifecycleEvent] = []
    var structuralCancels: [LifecycleEvent] = []
    let starts: [LifecycleEvent] = []

    appendLifecycleCancel(
      task,
      identity: testIdentity("Leaf"),
      isStructural: false,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )
    appendLifecycleCancel(
      task,
      identity: testIdentity("Leaf"),
      isStructural: false,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )

    #expect(stableCancels.count == 1)
    #expect(structuralCancels.isEmpty)
  }

  @Test("stress viewport lifecycle 002 cancel deduplicates across stable and structural buffers")
  func viewportLifecycle002CancelDeduplicatesAcrossBuffers() {
    let task = lifecycleTask("load")
    var stableCancels: [LifecycleEvent] = []
    var structuralCancels: [LifecycleEvent] = []
    let starts: [LifecycleEvent] = []

    appendLifecycleCancel(
      task,
      identity: testIdentity("Leaf"),
      isStructural: false,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )
    appendLifecycleCancel(
      task,
      identity: testIdentity("Leaf"),
      isStructural: true,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )

    #expect(stableCancels.count == 1)
    #expect(structuralCancels.isEmpty)
  }

  @Test("stress viewport lifecycle 003 duplicate task start is emitted once")
  func viewportLifecycle003DuplicateTaskStartIsEmittedOnce() {
    let task = lifecycleTask("load")
    let stableCancels: [LifecycleEvent] = []
    let structuralCancels: [LifecycleEvent] = []
    var starts: [LifecycleEvent] = []

    appendLifecycleStart(
      task,
      identity: testIdentity("Leaf"),
      stableCancels: stableCancels,
      structuralCancels: structuralCancels,
      starts: &starts
    )
    appendLifecycleStart(
      task,
      identity: testIdentity("Leaf"),
      stableCancels: stableCancels,
      structuralCancels: structuralCancels,
      starts: &starts
    )

    #expect(starts.count == 1)
  }

  @Test("stress viewport lifecycle 004 cancel and start for same task both survive")
  func viewportLifecycle004CancelAndStartForSameTaskBothSurvive() {
    let task = lifecycleTask("load")
    var stableCancels: [LifecycleEvent] = []
    var structuralCancels: [LifecycleEvent] = []
    var starts: [LifecycleEvent] = []
    let identity = testIdentity("Leaf")

    appendLifecycleCancel(
      task,
      identity: identity,
      isStructural: false,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )
    appendLifecycleStart(
      task,
      identity: identity,
      stableCancels: stableCancels,
      structuralCancels: structuralCancels,
      starts: &starts
    )

    #expect(stableCancels.map(\.operation) == [.taskCancel(task)])
    #expect(starts.map(\.operation) == [.taskStart(task)])
  }

  @Test("stress viewport lifecycle 005 equal task operations keep distinct node owners")
  func viewportLifecycle005EqualTaskOperationsKeepDistinctNodeOwners() {
    let task = lifecycleTask("load")
    var stableCancels: [LifecycleEvent] = []
    var structuralCancels: [LifecycleEvent] = []
    let starts: [LifecycleEvent] = []
    let identity = testIdentity("Leaf")

    appendLifecycleCancel(
      task,
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: identity,
      isStructural: false,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )
    appendLifecycleCancel(
      task,
      viewNodeID: ViewNodeID(rawValue: 2),
      identity: identity,
      isStructural: false,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )

    #expect(stableCancels.map(\.viewNodeID) == [ViewNodeID(rawValue: 1), ViewNodeID(rawValue: 2)])
  }

  @Test("stress viewport lifecycle 006 equal task operations keep distinct identities")
  func viewportLifecycle006EqualTaskOperationsKeepDistinctIdentities() {
    let task = lifecycleTask("load")
    var stableCancels: [LifecycleEvent] = []
    var structuralCancels: [LifecycleEvent] = []
    let starts: [LifecycleEvent] = []
    let nodeID = ViewNodeID(rawValue: 1)

    appendLifecycleCancel(
      task,
      viewNodeID: nodeID,
      identity: testIdentity("A"),
      isStructural: false,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )
    appendLifecycleCancel(
      task,
      viewNodeID: nodeID,
      identity: testIdentity("B"),
      isStructural: false,
      stableCancels: &stableCancels,
      structuralCancels: &structuralCancels,
      starts: starts
    )

    #expect(stableCancels.map(\.identity) == [testIdentity("A"), testIdentity("B")])
  }

  @Test("stress viewport lifecycle 007 live distinct owner suppresses child lifecycle")
  func viewportLifecycle007LiveDistinctOwnerSuppressesChildLifecycle() {
    let child = lifecycleViewNode(1, "Child")

    let emits = ViewGraphLifecycleEventCollector.nodeEmitsOwnLifecycleEvents(
      child,
      ownerNodeID: ViewNodeID(rawValue: 2),
      ownerExists: true
    )

    #expect(!emits)
  }

  @Test("stress viewport lifecycle 008 missing owner restores child lifecycle")
  func viewportLifecycle008MissingOwnerRestoresChildLifecycle() {
    let child = lifecycleViewNode(1, "Child")

    let emits = ViewGraphLifecycleEventCollector.nodeEmitsOwnLifecycleEvents(
      child,
      ownerNodeID: ViewNodeID(rawValue: 2),
      ownerExists: false
    )

    #expect(emits)
  }

  @Test("stress viewport lifecycle 009 first visibility appears before task start")
  func viewportLifecycle009FirstVisibilityAppearsBeforeTaskStart() {
    let identity = testIdentity("Row")
    let task = lifecycleTask("load")
    let summary = lifecycleSummary(
      identity,
      metadata: .init(appearHandlerIDs: ["appear"], tasks: [task])
    )

    let plan = lifecyclePlan(visible: [summary])

    #expect(plan.events.map(\.operation) == [.appear(handlerIDs: ["appear"]), .taskStart(task)])
  }

  @Test("stress viewport lifecycle 010 tasks only visibility emits no empty appear")
  func viewportLifecycle010TasksOnlyVisibilityEmitsNoEmptyAppear() {
    let task = lifecycleTask("load")
    let summary = lifecycleSummary(testIdentity("Row"), metadata: .init(tasks: [task]))

    let plan = lifecyclePlan(visible: [summary])

    #expect(plan.events.map(\.operation) == [.taskStart(task)])
  }

  @Test("stress viewport lifecycle 011 departure cancels before disappear")
  func viewportLifecycle011DepartureCancelsBeforeDisappear() {
    let identity = testIdentity("Row")
    let nodeID = ViewNodeID(rawValue: 1)
    let task = lifecycleTask("load")
    let previous = lifecycleStateNode(
      nodeID: nodeID,
      identity: identity,
      disappear: ["disappear"],
      tasks: [task]
    )

    let plan = lifecyclePlan(
      visible: [],
      previous: [.viewNode(nodeID): previous],
      order: [.viewNode(nodeID)]
    )

    #expect(
      plan.events.map(\.operation) == [
        .taskCancel(task),
        .disappear(handlerIDs: ["disappear"]),
      ])
  }

  @Test("stress viewport lifecycle 012 simultaneous departure unwinds reverse order")
  func viewportLifecycle012SimultaneousDepartureUnwindsReverseOrder() {
    let firstID = ViewNodeID(rawValue: 1)
    let secondID = ViewNodeID(rawValue: 2)
    let firstTask = lifecycleTask("first")
    let secondTask = lifecycleTask("second")
    let first = lifecycleStateNode(
      nodeID: firstID,
      identity: testIdentity("First"),
      disappear: ["first-disappear"],
      tasks: [firstTask]
    )
    let second = lifecycleStateNode(
      nodeID: secondID,
      identity: testIdentity("Second"),
      disappear: ["second-disappear"],
      tasks: [secondTask]
    )

    let plan = lifecyclePlan(
      visible: [],
      previous: [.viewNode(firstID): first, .viewNode(secondID): second],
      order: [.viewNode(firstID), .viewNode(secondID)]
    )

    #expect(
      plan.events.map(\.identity) == [
        second.identity,
        first.identity,
        second.identity,
        first.identity,
      ])
    #expect(
      plan.events.map(\.operation) == [
        .taskCancel(secondTask),
        .taskCancel(firstTask),
        .disappear(handlerIDs: ["second-disappear"]),
        .disappear(handlerIDs: ["first-disappear"]),
      ])
  }

  @Test("stress viewport lifecycle 013 unchanged visible node emits nothing")
  func viewportLifecycle013UnchangedVisibleNodeEmitsNothing() {
    let identity = testIdentity("Row")
    let nodeID = ViewNodeID(rawValue: 1)
    let task = lifecycleTask("load")
    let metadata = LifecycleMetadata(
      appearHandlerIDs: ["appear"],
      disappearHandlerIDs: ["disappear"],
      tasks: [task]
    )
    let previous = lifecycleStateNode(
      nodeID: nodeID,
      identity: identity,
      appear: ["appear"],
      disappear: ["disappear"],
      tasks: [task]
    )

    let plan = lifecyclePlan(
      visible: [lifecycleSummary(identity, metadata: metadata)],
      previous: [.viewNode(nodeID): previous],
      order: [.viewNode(nodeID)],
      nodeIDs: [identity: nodeID]
    )

    #expect(plan.events.isEmpty)
  }

  @Test("stress viewport lifecycle 014 priority change cancels before replacement start")
  func viewportLifecycle014PriorityChangeCancelsBeforeReplacementStart() {
    let identity = testIdentity("Row")
    let nodeID = ViewNodeID(rawValue: 1)
    let oldTask = lifecycleTask("load", priority: .low)
    let newTask = lifecycleTask("load", priority: .high)
    let previous = lifecycleStateNode(nodeID: nodeID, identity: identity, tasks: [oldTask])

    let plan = lifecyclePlan(
      visible: [lifecycleSummary(identity, metadata: .init(tasks: [newTask]))],
      previous: [.viewNode(nodeID): previous],
      order: [.viewNode(nodeID)],
      nodeIDs: [identity: nodeID]
    )

    #expect(plan.events.map(\.operation) == [.taskCancel(oldTask), .taskStart(newTask)])
  }

  @Test("stress viewport lifecycle 015 partial task replacement preserves source orders")
  func viewportLifecycle015PartialTaskReplacementPreservesSourceOrders() {
    let identity = testIdentity("Row")
    let nodeID = ViewNodeID(rawValue: 1)
    let removedA = lifecycleTask("removed-a")
    let stable = lifecycleTask("stable")
    let removedB = lifecycleTask("removed-b")
    let addedB = lifecycleTask("added-b")
    let addedA = lifecycleTask("added-a")
    let previous = lifecycleStateNode(
      nodeID: nodeID,
      identity: identity,
      tasks: [removedA, stable, removedB]
    )

    let plan = lifecyclePlan(
      visible: [lifecycleSummary(identity, metadata: .init(tasks: [addedB, stable, addedA]))],
      previous: [.viewNode(nodeID): previous],
      order: [.viewNode(nodeID)],
      nodeIDs: [identity: nodeID]
    )

    #expect(
      plan.events.map(\.operation) == [
        .taskCancel(removedA),
        .taskCancel(removedB),
        .taskStart(addedB),
        .taskStart(addedA),
      ])
  }

  @Test("stress viewport lifecycle 016 appear handler replacement does not reappear")
  func viewportLifecycle016AppearHandlerReplacementDoesNotReappear() {
    let identity = testIdentity("Row")
    let nodeID = ViewNodeID(rawValue: 1)
    let previous = lifecycleStateNode(
      nodeID: nodeID,
      identity: identity,
      appear: ["old-appear"]
    )

    let plan = lifecyclePlan(
      visible: [
        lifecycleSummary(identity, metadata: .init(appearHandlerIDs: ["new-appear"]))
      ],
      previous: [.viewNode(nodeID): previous],
      order: [.viewNode(nodeID)],
      nodeIDs: [identity: nodeID]
    )

    #expect(plan.events.isEmpty)
  }

  @Test("stress viewport lifecycle 017 later departure uses current disappear handlers")
  func viewportLifecycle017LaterDepartureUsesCurrentDisappearHandlers() {
    let identity = testIdentity("Row")
    let nodeID = ViewNodeID(rawValue: 1)
    let previous = lifecycleStateNode(
      nodeID: nodeID,
      identity: identity,
      disappear: ["old-disappear"]
    )
    let refreshed = lifecyclePlan(
      visible: [
        lifecycleSummary(identity, metadata: .init(disappearHandlerIDs: ["new-disappear"]))
      ],
      previous: [.viewNode(nodeID): previous],
      order: [.viewNode(nodeID)],
      nodeIDs: [identity: nodeID]
    )

    let departed = lifecyclePlan(
      visible: [],
      previous: refreshed.viewportLifecycleNodesByKey,
      order: refreshed.viewportLifecycleOrder,
      nodeIDs: [identity: nodeID]
    )

    #expect(departed.events.map(\.operation) == [.disappear(handlerIDs: ["new-disappear"])])
  }

  @Test("stress viewport lifecycle 018 empty metadata does not enter carried state")
  func viewportLifecycle018EmptyMetadataDoesNotEnterCarriedState() {
    let summary = lifecycleSummary(testIdentity("Row"), metadata: .init())

    let plan = lifecyclePlan(visible: [summary])

    #expect(plan.events.isEmpty)
    #expect(plan.viewportLifecycleNodesByKey.isEmpty)
    #expect(plan.viewportLifecycleOrder.isEmpty)
  }

  @Test("stress viewport lifecycle 019 nested visible nodes preserve preorder")
  func viewportLifecycle019NestedVisibleNodesPreservePreorder() {
    let parentIdentity = testIdentity("Parent")
    let childIdentity = testIdentity("Parent", "Child")
    let summary = lifecycleSummary(
      parentIdentity,
      metadata: .init(appearHandlerIDs: ["parent"]),
      children: [
        lifecycleSummary(childIdentity, metadata: .init(appearHandlerIDs: ["child"]))
      ]
    )

    let plan = lifecyclePlan(visible: [summary])

    #expect(plan.events.map(\.identity) == [parentIdentity, childIdentity])
    #expect(
      plan.viewportLifecycleOrder == [
        .identity(parentIdentity),
        .identity(childIdentity),
      ])
  }

  @Test("stress viewport lifecycle 020 indexed barrier without placement emits nothing")
  func viewportLifecycle020IndexedBarrierWithoutPlacementEmitsNothing() {
    let resolved = indexedLifecycleRoot()

    let plan = ViewGraphLifecyclePlanner.plan(
      resolved: resolved,
      placed: nil,
      input: lifecycleInput()
    )

    #expect(plan.events.isEmpty)
    #expect(plan.viewportLifecycleNodesByKey.isEmpty)
  }

  @Test("stress viewport lifecycle 021 indexed barrier trusts placed only descendants")
  func viewportLifecycle021IndexedBarrierTrustsPlacedOnlyDescendants() {
    let identity = testIdentity("PlacedOnly")
    let placed = lifecycleRootSummary(
      children: [lifecycleSummary(identity, metadata: .init(appearHandlerIDs: ["appear"]))]
    )

    let plan = ViewGraphLifecyclePlanner.plan(
      resolved: indexedLifecycleRoot(),
      placed: placed,
      input: lifecycleInput()
    )

    #expect(plan.events.map(\.identity) == [identity])
    #expect(plan.events.map(\.operation) == [.appear(handlerIDs: ["appear"])])
  }

  @Test("stress viewport lifecycle 022 nonindexed tree ignores extra placed children")
  func viewportLifecycle022NonindexedTreeIgnoresExtraPlacedChildren() {
    let resolved = ResolvedNode(identity: testIdentity("Root"), kind: .root)
    let placed = lifecycleRootSummary(
      children: [
        lifecycleSummary(
          testIdentity("Extra"),
          metadata: .init(appearHandlerIDs: ["extra"])
        )
      ]
    )

    let plan = ViewGraphLifecyclePlanner.plan(
      resolved: resolved,
      placed: placed,
      input: lifecycleInput()
    )

    #expect(plan.events.isEmpty)
    #expect(plan.viewportLifecycleNodesByKey.isEmpty)
  }

  @Test("stress viewport lifecycle 023 mapped identity stamps exact node key")
  func viewportLifecycle023MappedIdentityStampsExactNodeKey() {
    let identity = testIdentity("Row")
    let nodeID = ViewNodeID(rawValue: 41)
    let summary = lifecycleSummary(identity, metadata: .init(appearHandlerIDs: ["appear"]))

    let plan = lifecyclePlan(visible: [summary], nodeIDs: [identity: nodeID])

    #expect(plan.events.map(\.viewNodeID) == [nodeID])
    #expect(plan.viewportLifecycleOrder == [.viewNode(nodeID)])
    #expect(plan.viewportLifecycleNodesByKey[.viewNode(nodeID)]?.viewNodeID == nodeID)
  }

  @Test("stress viewport lifecycle 024 unmapped identity uses fallback key")
  func viewportLifecycle024UnmappedIdentityUsesFallbackKey() {
    let identity = testIdentity("Row")
    let summary = lifecycleSummary(identity, metadata: .init(appearHandlerIDs: ["appear"]))

    let plan = lifecyclePlan(visible: [summary])

    #expect(plan.events.map(\.viewNodeID) == [nil])
    #expect(plan.viewportLifecycleOrder == [.identity(identity)])
    #expect(plan.viewportLifecycleNodesByKey[.identity(identity)]?.viewNodeID == nil)
  }

  @Test("stress viewport lifecycle 025 key migration does not synthesize reentry")
  func viewportLifecycle025KeyMigrationDoesNotSynthesizeReentry() {
    let identity = testIdentity("Row")
    let nodeID = ViewNodeID(rawValue: 41)
    let task = lifecycleTask("load")
    let metadata = LifecycleMetadata(
      appearHandlerIDs: ["appear"],
      disappearHandlerIDs: ["disappear"],
      tasks: [task]
    )
    let previous = lifecycleStateNode(
      identity: identity,
      appear: ["appear"],
      disappear: ["disappear"],
      tasks: [task]
    )

    let plan = lifecyclePlan(
      visible: [lifecycleSummary(identity, metadata: metadata)],
      previous: [.identity(identity): previous],
      order: [.identity(identity)],
      nodeIDs: [identity: nodeID]
    )

    withKnownIssue(
      "Viewport lifecycle key migration from identity to ViewNodeID synthesizes departure and re-entry"
    ) {
      #expect(plan.events.isEmpty)
    }
    #expect(plan.viewportLifecycleOrder == [.viewNode(nodeID)])
    #expect(Set(plan.viewportLifecycleNodesByKey.keys) == [.viewNode(nodeID)])
  }
}

@MainActor
private func appendLifecycleCancel(
  _ task: TaskDescriptor,
  viewNodeID: ViewNodeID? = nil,
  identity: Identity,
  isStructural: Bool,
  stableCancels: inout [LifecycleEvent],
  structuralCancels: inout [LifecycleEvent],
  starts: [LifecycleEvent]
) {
  ViewGraphLifecycleEventCollector.appendTaskCancelEvent(
    viewNodeID: viewNodeID,
    identity: identity,
    task: task,
    isStructural: isStructural,
    stableTaskCancelEvents: &stableCancels,
    structuralTaskCancelEvents: &structuralCancels,
    stableTaskStartEvents: starts
  )
}

@MainActor
private func appendLifecycleStart(
  _ task: TaskDescriptor,
  viewNodeID: ViewNodeID? = nil,
  identity: Identity,
  stableCancels: [LifecycleEvent],
  structuralCancels: [LifecycleEvent],
  starts: inout [LifecycleEvent]
) {
  ViewGraphLifecycleEventCollector.appendTaskStartEvent(
    viewNodeID: viewNodeID,
    identity: identity,
    task: task,
    stableTaskCancelEvents: stableCancels,
    structuralTaskCancelEvents: structuralCancels,
    stableTaskStartEvents: &starts
  )
}

@MainActor
private func lifecycleViewNode(
  _ rawID: UInt64,
  _ components: String...
) -> ViewNode {
  ViewNode(
    viewNodeID: ViewNodeID(rawValue: rawID),
    identity: Identity(components: components)
  )
}

private func lifecycleTask(
  _ id: String,
  priority: TaskPriority = .medium
) -> TaskDescriptor {
  TaskDescriptor(id: id, priority: priority)
}

private func lifecycleStateNode(
  nodeID: ViewNodeID? = nil,
  identity: Identity,
  appear: [String] = [],
  disappear: [String] = [],
  tasks: [TaskDescriptor] = []
) -> LifecycleStateNode {
  LifecycleStateNode(
    viewNodeID: nodeID,
    identity: identity,
    appearHandlerIDs: appear,
    disappearHandlerIDs: disappear,
    tasks: tasks
  )
}

private func lifecycleSummary(
  _ identity: Identity,
  metadata: LifecycleMetadata,
  children: [ViewportVisibilitySummary] = []
) -> ViewportVisibilitySummary {
  ViewportVisibilitySummary(
    identity: identity,
    lifecycleMetadata: metadata,
    children: children
  )
}

private func lifecycleRootSummary(
  children: [ViewportVisibilitySummary]
) -> ViewportVisibilitySummary {
  lifecycleSummary(testIdentity("Root"), metadata: .init(), children: children)
}

private func indexedLifecycleRoot() -> ResolvedNode {
  let rootIdentity = testIdentity("Root")
  return ResolvedNode(
    identity: rootIdentity,
    kind: .root,
    indexedChildSource: IndexedChildSourceSnapshot(
      identityRoot: rootIdentity,
      measurementSignature: "stress-lifecycle",
      children: []
    )
  )
}

private func lifecycleInput(
  previous: [ViewportLifecycleKey: LifecycleStateNode] = [:],
  order: [ViewportLifecycleKey] = [],
  nodeIDs: [Identity: ViewNodeID] = [:]
) -> ViewGraphLifecyclePlanningInput {
  ViewGraphLifecyclePlanningInput(
    viewportLifecycleNodesByKey: previous,
    viewportLifecycleOrder: order,
    nodeIDByIdentity: nodeIDs,
    changeHandlerIDsByIdentity: [],
    stableTaskCancelEvents: [],
    stableTaskStartEvents: [],
    structuralAppearEvents: [],
    structuralTaskCancelEvents: [],
    structuralDisappearEvents: []
  )
}

@MainActor
private func lifecyclePlan(
  visible: [ViewportVisibilitySummary],
  previous: [ViewportLifecycleKey: LifecycleStateNode] = [:],
  order: [ViewportLifecycleKey] = [],
  nodeIDs: [Identity: ViewNodeID] = [:]
) -> ViewGraphFrameLifecycleEventPlan {
  ViewGraphLifecyclePlanner.plan(
    resolved: indexedLifecycleRoot(),
    placed: lifecycleRootSummary(children: visible),
    input: lifecycleInput(previous: previous, order: order, nodeIDs: nodeIDs)
  )
}
