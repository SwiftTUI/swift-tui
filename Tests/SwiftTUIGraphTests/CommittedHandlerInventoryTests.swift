import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Committed handler inventory")
struct CommittedHandlerInventoryTests {
  @Test("initializer canonicalizes every identity family")
  func initializerCanonicalizesEveryFamily() {
    let alpha = testIdentity("Root", "Alpha")
    let beta = testIdentity("Root", "Beta")
    let inventory = CommittedHandlerInventory(
      actionIdentities: [beta, alpha, beta],
      keyHandlerIdentities: [beta, alpha, beta],
      commandScopes: [beta, alpha, beta],
      dropScopes: [beta, alpha, beta],
      gestureRouteIdentities: [beta, alpha, beta]
    )

    #expect(inventory.actionIdentities == [alpha, beta])
    #expect(inventory.keyHandlerIdentities == [alpha, beta])
    #expect(inventory.commandScopes == [alpha, beta])
    #expect(inventory.dropScopes == [alpha, beta])
    #expect(inventory.gestureRouteIdentities == [alpha, beta])
    #expect(CommittedHandlerInventory() == .init())
  }

  @Test("apply stamps all five families from NodeHandlers")
  func applyStampsAllFiveFamilies() {
    let root = testIdentity("Root")
    let actionAlpha = testIdentity("Root", "ActionAlpha")
    let actionBeta = testIdentity("Root", "ActionBeta")
    let pasteKey = testIdentity("Root", "KeyPaste")
    let pressKey = testIdentity("Root", "KeyPress")
    let commandScope = testIdentity("Root", "Command")
    let emptyCommandScope = testIdentity("Root", "EmptyCommand")
    let dropScope = testIdentity("Root", "Drop")
    let gesture = testIdentity("Root", "Gesture")
    let pointerOnly = testIdentity("Root", "PointerOnly")
    let hoverOnly = testIdentity("Root", "HoverOnly")
    let node = RegistrationKindDriver.makeRecordingNode(identity: root)

    ViewNodeContext.withValue(node) {
      node.recordActionRegistration(
        identity: actionBeta,
        handler: { false },
        followUpInvalidationIdentity: nil
      )
      node.recordActionRegistration(
        identity: actionAlpha,
        handler: { false },
        followUpInvalidationIdentity: nil
      )
      node.recordKeyPressHandlerRegistration(identity: pressKey, ordinal: 0) { _ in false }
      node.recordPasteHandlerRegistration(identity: pasteKey, ordinal: 0) { _ in false }
      node.recordCommandRegistration(
        commandSnapshot(scope: commandScope)
      )
      node.recordCommandRegistration(
        CommandRegistrySnapshot(
          keyCommandsByScope: [emptyCommandScope: [:]],
          ownersByScope: [emptyCommandScope: .current(identity: emptyCommandScope)]
        )
      )
      node.recordDropDestinationRegistration(
        DropDestinationRegistrySnapshot(
          handlersByScope: [dropScope: { _, _ in false }],
          ownersByScope: [dropScope: .current(identity: dropScope)]
        )
      )
      node.recordGestureRegistration(
        identity: gesture,
        recognizer: AnyGestureRecognizer(TotalityProbeGesture())
      )
      // The gesture's coupled pointer route is present, but the inventory
      // currency comes from the recognizer key rather than pointer storage.
      node.recordPointerHandlerRegistration(
        routeID: RouteID(identity: gesture)
      ) { _ in .ignored }
      node.recordPointerHandlerRegistration(
        routeID: RouteID(identity: pointerOnly)
      ) { _ in .ignored }
      node.recordPointerHoverHandlerRegistration(
        routeID: RouteID(identity: hoverOnly)
      ) { _ in }
    }

    node.apply(
      resolved: ResolvedNode(
        identity: root,
        kind: .root,
        handlerInventory: CommittedHandlerInventory(
          actionIdentities: [testIdentity("CallerSupplied")]
        )
      ),
      children: []
    )

    let inventory = node.snapshot().handlerInventory
    #expect(inventory.actionIdentities == [actionAlpha, actionBeta])
    #expect(inventory.keyHandlerIdentities == [pasteKey, pressKey])
    #expect(inventory.commandScopes == [commandScope])
    #expect(inventory.dropScopes == [dropScope])
    #expect(inventory.gestureRouteIdentities == [gesture])
  }

  @Test("out-of-capture refresh and adoption keep committed projection exact")
  func refreshAndAdoptionKeepProjectionExact() {
    let root = testIdentity("Root")
    let refreshedAction = testIdentity("Root", "RefreshedAction")
    let adoptedPaste = testIdentity("Root", "AdoptedPaste")
    let nodes = RegistrationKindDriver.makeRecordingNodes(
      identities: [root, testIdentity("Root", "Departing")]
    )
    let absorber = nodes[0]
    let departing = nodes[1]

    absorber.apply(
      resolved: ResolvedNode(identity: root, kind: .root),
      children: []
    )
    absorber.recordActionRegistration(
      identity: refreshedAction,
      handler: { false },
      followUpInvalidationIdentity: nil
    )
    #expect(absorber.snapshot().handlerInventory.actionIdentities == [refreshedAction])

    ViewNodeContext.withValue(departing) {
      departing.recordPasteHandlerRegistration(
        identity: adoptedPaste,
        ordinal: 0
      ) { _ in false }
    }
    departing.apply(
      resolved: ResolvedNode(identity: departing.identity, kind: .view("Departing")),
      children: []
    )
    absorber.adoptRuntimeRegistrations(from: departing)

    let inventory = absorber.snapshot().handlerInventory
    #expect(inventory.actionIdentities == [refreshedAction])
    #expect(inventory.keyHandlerIdentities == [adoptedPaste])
  }

  @Test("an empty replacement capture clears committed inventory without an apply")
  func emptyReplacementCaptureClearsInventoryWithoutApply() {
    let root = testIdentity("Root")
    let action = testIdentity("Root", "Action")
    let node = RegistrationKindDriver.makeRecordingNode(identity: root)

    ViewNodeContext.withValue(node) {
      node.recordActionRegistration(
        identity: action,
        handler: { false },
        followUpInvalidationIdentity: nil
      )
    }
    node.apply(
      resolved: ResolvedNode(identity: root, kind: .root),
      children: []
    )
    #expect(node.snapshot().handlerInventory.actionIdentities == [action])

    // Group/AnyView normalization and capture-host splicing can re-evaluate a
    // recording node without applying a resolved value back onto that same
    // node. Ending the empty capture must still publish the reset projection.
    ViewNodeContext.withValue(node) {}

    #expect(node.registeredHandlers.action.registrations.isEmpty)
    #expect(node.snapshot().handlerInventory.actionIdentities.isEmpty)
  }

  @Test("finalize clears inventory from a lazily rewired departed child value")
  func finalizeClearsInventoryFromDepartedChildValue() throws {
    let graph = ViewGraph()
    let root = testIdentity("Root")
    let child = testIdentity("Root", "Child")
    let action = testIdentity("Root", "Child", "Action")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: root,
        kind: .root,
        children: [
          ResolvedNode(identity: child, kind: .view("Child"))
        ]
      )
    )

    let childNode = try #require(graph.nodeIfExists(for: child))
    childNode.recordActionRegistration(
      identity: action,
      handler: { false },
      followUpInvalidationIdentity: nil
    )
    let inventoried = graph.snapshot(rootIdentity: root)
    #expect(inventoried.children[0].handlerInventory.actionIdentities == [action])

    // The accepted frame's order joins the committed live set during finalize.
    // Canonicalization must run after that union or it would erase a newly
    // accepted handler before the oracle can inspect it.
    graph.liveNodeIDs = []
    _ = graph.finalizeFrame(
      rootIdentity: root,
      resolved: inventoried,
      placed: nil
    )
    let live = try #require(graph.committedRootSnapshotIfAvailable())
    #expect(live.children[0].handlerInventory.actionIdentities == [action])

    // Teardown removes the runtime owner immediately but intentionally leaves
    // the ancestor's committed child value to rewire on its next apply.
    graph.removeSubtree(rootedAt: childNode)
    let stale = try #require(graph.committedRootSnapshotIfAvailable())
    #expect(stale.children[0].handlerInventory.actionIdentities == [action])
    #expect(graph.nodeIfExists(for: child) == nil)

    _ = graph.finalizeFrame(
      rootIdentity: root,
      resolved: ResolvedNode(identity: root, kind: .root),
      placed: nil
    )

    let reconciled = try #require(graph.committedRootSnapshotIfAvailable())
    #expect(reconciled.children.count == 1)
    #expect(reconciled.children[0].handlerInventory.actionIdentities.isEmpty)
  }

  @Test("reconciliation is stack safe across a deep lazy committed chain")
  func reconciliationIsStackSafeAcrossDeepLazyCommittedChain() {
    let depth = 8_192
    let action = testIdentity("Deep", "Action")
    let inventory = CommittedHandlerInventory(actionIdentities: [action])
    var chain = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: testIdentity("Deep", "0"),
      kind: .view("Depth"),
      handlerInventory: inventory
    )
    for index in 1..<depth {
      chain = ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: UInt64(index + 1)),
        identity: testIdentity("Deep", "\(index)"),
        kind: .view("Depth"),
        children: [chain],
        handlerInventory: inventory
      )
    }

    chain.reconcileCommittedHandlerInventory { _ in nil }

    var visited = 0
    var stack = [chain]
    while let node = stack.popLast() {
      visited += 1
      #expect(node.handlerInventory == .init())
      stack.append(contentsOf: node.children)
    }
    #expect(visited == depth)
  }

  @Test("canonical reconciliation leaves an exact committed tree unchanged")
  func canonicalReconciliationLeavesExactCommittedTreeUnchanged() {
    let action = testIdentity("Exact", "Action")
    let inventory = CommittedHandlerInventory(actionIdentities: [action])
    let leafID = ViewNodeID(rawValue: 1)
    let rootID = ViewNodeID(rawValue: 2)
    var exact = ResolvedNode(
      viewNodeID: rootID,
      identity: testIdentity("Exact"),
      kind: .root,
      children: [
        ResolvedNode(
          viewNodeID: leafID,
          identity: testIdentity("Exact", "Leaf"),
          kind: .view("Leaf"),
          handlerInventory: inventory
        )
      ]
    )
    let original = exact
    var lookupCount = 0

    exact.reconcileCommittedHandlerInventory { viewNodeID in
      lookupCount += 1
      return viewNodeID == leafID ? inventory : .init()
    }

    #expect(lookupCount == 2)
    #expect(exact == original)
  }

  @Test("equality observes inventory while geometry and content alarms exclude it")
  func equalityAndComparatorClassification() {
    let identity = testIdentity("Root")
    let action = testIdentity("Root", "Action")
    let base = ResolvedNode(identity: identity, kind: .root)
    var inventoried = base
    inventoried.handlerInventory = CommittedHandlerInventory(
      actionIdentities: [action]
    )

    #expect(base != inventoried)
    #expect(!base.memoReuseEquivalent(to: inventoried))
    #expect(base.memoUnsoundContentDivergence(from: inventoried) == nil)
    #expect(base.memoFirstDifferingField(from: inventoried) == "handlerInventory")
    #expect(base.isEquivalentForMeasurement(to: inventoried))
    #expect(base.isEquivalentForPlacement(to: inventoried))
    switch base.placementEquivalence(to: inventoried) {
    case .identical:
      break
    case .divergent, .geometryReusable:
      Issue.record("handler inventory must be invisible to placement equivalence")
    }
  }

  private func commandSnapshot(scope: Identity) -> CommandRegistrySnapshot {
    let binding = KeyBinding(key: .character("i"), modifiers: [.ctrl])
    return CommandRegistrySnapshot(
      keyCommandsByScope: [
        scope: [
          binding: RegisteredKeyCommand(
            binding: binding,
            description: "inventory probe",
            isEnabled: true,
            action: {}
          )
        ]
      ],
      ownersByScope: [scope: .current(identity: scope)]
    )
  }
}
