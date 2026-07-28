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
    let bareKey = testIdentity("Root", "KeyBare")
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
      node.recordKeyHandlerRegistration(identity: bareKey) { _ in false }
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
    #expect(inventory.keyHandlerIdentities == [bareKey, pasteKey, pressKey])
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
