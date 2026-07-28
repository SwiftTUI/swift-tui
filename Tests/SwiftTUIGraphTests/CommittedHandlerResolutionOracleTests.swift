import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Committed handler resolution oracle", .serialized)
struct CommittedHandlerResolutionOracleTests {
  @Test(
    "sampled publication checks hollow records against committed root and child currency"
  )
  func sampledPublicationUsesCommittedCurrencyForRootAndChild() throws {
    try withRestoredProbeState {
      let graph = ViewGraph()
      let rootIdentity = testIdentity("Root")
      let childIdentity = testIdentity("Root", "Child")
      let rootAction = testIdentity("Root", "Action")
      let childAction = testIdentity("Root", "Child", "Action")
      _ = graph.applySnapshot(
        ResolvedNode(
          identity: rootIdentity,
          kind: .root,
          children: [
            ResolvedNode(identity: childIdentity, kind: .view("Child"))
          ]
        )
      )
      let rootNode = try #require(graph.nodeIfExists(for: rootIdentity))
      let childNode = try #require(graph.nodeIfExists(for: childIdentity))

      // Retained artifacts can carry authored handler currency independently
      // of the closure-bearing records on the current runtime nodes. Keep the
      // records deliberately hollow so rebuilding from registeredHandlers
      // would launder the exact defect this oracle must report.
      var childCommitted = childNode.snapshot()
      childCommitted.handlerInventory = CommittedHandlerInventory(
        actionIdentities: [childAction]
      )
      childNode.applyRetainedSnapshot(childCommitted)

      var rootCommitted = graph.snapshot(rootIdentity: rootIdentity)
      rootCommitted.handlerInventory = CommittedHandlerInventory(
        actionIdentities: [rootAction]
      )
      rootNode.applyRetainedSnapshot(rootCommitted)
      #expect(rootNode.registeredHandlers.action.registrations.isEmpty)
      #expect(childNode.registeredHandlers.action.registrations.isEmpty)

      let resolved = graph.snapshot(rootIdentity: rootIdentity)
      _ = graph.finalizeFrame(
        rootIdentity: rootIdentity,
        resolved: resolved,
        placed: nil
      )

      let finalized = try #require(graph.committedRootSnapshotIfAvailable())
      #expect(finalized.handlerInventory.actionIdentities == [rootAction])
      #expect(finalized.children[0].handlerInventory.actionIdentities == [childAction])

      let liveRegistrations = RuntimeRegistrationSet.scratch()
      let draft = ViewGraphFrameDraft(
        liveRegistrations: liveRegistrations,
        checkpoint: nil
      )
      draft.recordDirtyEvaluationPlan(nil)
      let before = SoundnessCounterSnapshot.current()

      _ = draft.commitRuntimeRegistrations(from: graph)

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.actionResolutionViolationCount
          == before.actionResolutionViolationCount + 1
      )
      let detail = after.lastViolationDetailByKind["handler-resolution-action"]
      #expect(detail?.contains(rootAction.path) == true)
      #expect(detail?.contains(childAction.path) == true)
    }
  }

  @Test("action inventory resolves live, then reports one bounded family finding after reset")
  func actionResolutionAfterReset() {
    withRestoredProbeState {
      let identity = testIdentity("Root", "Branch", "Action")
      let registrations = RuntimeRegistrationSet.scratch()
      registrations.actionRegistry?.register(identity: identity) { false }
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(actionIdentities: [identity])
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: registrations)
      #expect(
        SoundnessCounterSnapshot.current().actionResolutionViolationCount
          == before.actionResolutionViolationCount
      )

      registrations.actionRegistry?.reset()
      inspectSampled(root, registrations: registrations)

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.actionResolutionViolationCount
          == before.actionResolutionViolationCount + 1
      )
      #expect(
        after.lastViolationDetailByKind["handler-resolution-action"]
          == resolutionDetail(family: .action, findings: [identity.path])
      )
      expectOnlyFamilyGrowth(.action, before: before, after: after)
    }
  }

  @Test("paste handler satisfies key inventory, then reset reports the key family")
  func keyResolutionAfterReset() {
    withRestoredProbeState {
      let identity = testIdentity("Root", "Branch", "Paste")
      let registrations = RuntimeRegistrationSet.scratch()
      registrations.keyHandlerRegistry?.register(
        identity: identity,
        pasteHandler: { _ in false }
      )
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(keyHandlerIdentities: [identity])
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: registrations)
      #expect(
        SoundnessCounterSnapshot.current().keyHandlerResolutionViolationCount
          == before.keyHandlerResolutionViolationCount
      )

      registrations.keyHandlerRegistry?.reset()
      inspectSampled(root, registrations: registrations)

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.keyHandlerResolutionViolationCount
          == before.keyHandlerResolutionViolationCount + 1
      )
      #expect(
        after.lastViolationDetailByKind["handler-resolution-key"]
          == resolutionDetail(family: .key, findings: [identity.path])
      )
      expectOnlyFamilyGrowth(.key, before: before, after: after)
    }
  }

  @Test("command scope resolves live, then reset reports the command family")
  func commandResolutionAfterReset() {
    withRestoredProbeState {
      let identity = testIdentity("Root", "Branch", "Command")
      let registrations = RuntimeRegistrationSet.scratch()
      let binding = KeyBinding(key: .character("k"), modifiers: [.ctrl])
      registrations.commandRegistry?.registerKeyCommand(
        at: identity,
        binding: binding,
        description: "test",
        isEnabled: true
      ) {}
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(commandScopes: [identity])
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: registrations)
      #expect(
        SoundnessCounterSnapshot.current().commandScopeResolutionViolationCount
          == before.commandScopeResolutionViolationCount
      )

      registrations.commandRegistry?.reset()
      inspectSampled(root, registrations: registrations)

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.commandScopeResolutionViolationCount
          == before.commandScopeResolutionViolationCount + 1
      )
      #expect(
        after.lastViolationDetailByKind["handler-resolution-command"]
          == resolutionDetail(family: .command, findings: [identity.path])
      )
      expectOnlyFamilyGrowth(.command, before: before, after: after)
    }
  }

  @Test("drop scope resolves live, then reset reports the drop family")
  func dropResolutionAfterReset() {
    withRestoredProbeState {
      let identity = testIdentity("Root", "Branch", "Drop")
      let registrations = RuntimeRegistrationSet.scratch()
      registrations.dropDestinationRegistry?.register(at: identity) { _, _ in false }
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(dropScopes: [identity])
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: registrations)
      #expect(
        SoundnessCounterSnapshot.current().dropScopeResolutionViolationCount
          == before.dropScopeResolutionViolationCount
      )

      registrations.dropDestinationRegistry?.reset()
      inspectSampled(root, registrations: registrations)

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.dropScopeResolutionViolationCount
          == before.dropScopeResolutionViolationCount + 1
      )
      #expect(
        after.lastViolationDetailByKind["handler-resolution-drop"]
          == resolutionDetail(family: .drop, findings: [identity.path])
      )
      expectOnlyFamilyGrowth(.drop, before: before, after: after)
    }
  }

  @Test("gesture reports a missing paired pointer independently")
  func gestureMissingPointerAfterReset() {
    withRestoredProbeState {
      let identity = testIdentity("Root", "Branch", "Gesture")
      let registrations = RuntimeRegistrationSet.scratch()
      registerGesture(identity, in: registrations)
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(gestureRouteIdentities: [identity])
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: registrations)
      #expect(
        SoundnessCounterSnapshot.current().gestureRouteResolutionViolationCount
          == before.gestureRouteResolutionViolationCount
      )

      registrations.pointerHandlerRegistry?.reset()
      inspectSampled(root, registrations: registrations)

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.gestureRouteResolutionViolationCount
          == before.gestureRouteResolutionViolationCount + 1
      )
      #expect(
        after.lastViolationDetailByKind["handler-resolution-gesture"]
          == resolutionDetail(
            family: .gesture,
            findings: ["\(identity.path)(missing=pointer)"]
          )
      )
      expectOnlyFamilyGrowth(.gesture, before: before, after: after)
    }
  }

  @Test("gesture reports a missing recognizer independently")
  func gestureMissingRecognizerAfterReset() {
    withRestoredProbeState {
      let identity = testIdentity("Root", "Branch", "Gesture")
      let registrations = RuntimeRegistrationSet.scratch()
      registerGesture(identity, in: registrations)
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(gestureRouteIdentities: [identity])
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: registrations)
      #expect(
        SoundnessCounterSnapshot.current().gestureRouteResolutionViolationCount
          == before.gestureRouteResolutionViolationCount
      )

      registrations.gestureRegistry?.reset()
      inspectSampled(root, registrations: registrations)

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.gestureRouteResolutionViolationCount
          == before.gestureRouteResolutionViolationCount + 1
      )
      #expect(
        after.lastViolationDetailByKind["handler-resolution-gesture"]
          == resolutionDetail(
            family: .gesture,
            findings: ["\(identity.path)(missing=recognizer)"]
          )
      )
      expectOnlyFamilyGrowth(.gesture, before: before, after: after)
    }
  }

  @Test("all five live families leave every resolution counter clean")
  func allFamiliesPresent() {
    withRestoredProbeState {
      let action = testIdentity("Root", "Branch", "Action")
      let key = testIdentity("Root", "Branch", "Key")
      let command = testIdentity("Root", "Branch", "Command")
      let drop = testIdentity("Root", "Branch", "Drop")
      let gesture = testIdentity("Root", "Branch", "Gesture")
      let registrations = RuntimeRegistrationSet.scratch()
      registrations.actionRegistry?.register(identity: action) { false }
      registrations.keyHandlerRegistry?.register(
        identity: key,
        handler: { _ in false }
      )
      registrations.commandRegistry?.registerKeyCommand(
        at: command,
        binding: KeyBinding(key: .character("k"), modifiers: [.ctrl]),
        description: "test",
        isEnabled: true
      ) {}
      registrations.dropDestinationRegistry?.register(at: drop) { _, _ in false }
      registerGesture(gesture, in: registrations)
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(
          actionIdentities: [action],
          keyHandlerIdentities: [key],
          commandScopes: [command],
          dropScopes: [drop],
          gestureRouteIdentities: [gesture]
        )
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: registrations)

      let after = SoundnessCounterSnapshot.current()
      #expect(after.actionResolutionViolationCount == before.actionResolutionViolationCount)
      #expect(
        after.keyHandlerResolutionViolationCount == before.keyHandlerResolutionViolationCount
      )
      #expect(
        after.commandScopeResolutionViolationCount == before.commandScopeResolutionViolationCount
      )
      #expect(after.dropScopeResolutionViolationCount == before.dropScopeResolutionViolationCount)
      #expect(
        after.gestureRouteResolutionViolationCount
          == before.gestureRouteResolutionViolationCount
      )
    }
  }

  @Test("owner-reminted pointer route satisfies gesture pairing")
  func ownerRemintedPointerRouteIsPresent() {
    withRestoredProbeState {
      let identity = testIdentity("Root", "Branch", "Gesture")
      let registrations = RuntimeRegistrationSet.scratch()
      registrations.gestureRegistry?.register(
        identity: identity,
        recognizer: AnyGestureRecognizer(TotalityProbeGesture())
      )
      registrations.pointerHandlerRegistry?.register(
        routeID: RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 41))
      ) { _ in .ignored }
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(gestureRouteIdentities: [identity])
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: registrations)

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.gestureRouteResolutionViolationCount
          == before.gestureRouteResolutionViolationCount
      )
      #expect(
        registrations.pointerHandlerRegistry?.hasHandler(routeID: RouteID(identity: identity))
          == false)
    }
  }

  @Test("absent optional registries leave their families outside oracle scope")
  func absentOptionalRegistriesAreSkipped() {
    withRestoredProbeState {
      let actions = (0..<6).map { testIdentity("Root", "Branch", "Action\($0)") }
      let keys = (0..<2).map { testIdentity("Root", "Branch", "Key\($0)") }
      let commands = (0..<2).map { testIdentity("Root", "Branch", "Command\($0)") }
      let drops = (0..<2).map { testIdentity("Root", "Branch", "Drop\($0)") }
      let gestures = (0..<2).map { testIdentity("Root", "Branch", "Gesture\($0)") }
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(
          actionIdentities: actions,
          keyHandlerIdentities: keys,
          commandScopes: commands,
          dropScopes: drops,
          gestureRouteIdentities: gestures
        )
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(root, registrations: RuntimeRegistrationSet())

      let after = SoundnessCounterSnapshot.current()
      #expect(after.actionResolutionViolationCount == before.actionResolutionViolationCount)
      #expect(
        after.keyHandlerResolutionViolationCount
          == before.keyHandlerResolutionViolationCount
      )
      #expect(
        after.commandScopeResolutionViolationCount
          == before.commandScopeResolutionViolationCount
      )
      #expect(
        after.dropScopeResolutionViolationCount
          == before.dropScopeResolutionViolationCount
      )
      #expect(
        after.gestureRouteResolutionViolationCount
          == before.gestureRouteResolutionViolationCount
      )
    }
  }

  @Test("a present empty family registry reports once and caps detail at four identities")
  func presentEmptyRegistryCapsFindings() {
    withRestoredProbeState {
      let actions = (0..<6).map { testIdentity("Root", "Branch", "Action\($0)") }
      let root = nestedRoot(
        inventory: CommittedHandlerInventory(actionIdentities: actions)
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(
        root,
        registrations: RuntimeRegistrationSet(actionRegistry: LocalActionRegistry())
      )

      let after = SoundnessCounterSnapshot.current()
      #expect(after.actionResolutionViolationCount == before.actionResolutionViolationCount + 1)
      #expect(
        after.lastViolationDetailByKind["handler-resolution-action"]
          == resolutionDetail(family: .action, findings: actions.prefix(4).map(\.path))
      )
    }
  }

  @Test("legacy lifecycle finding remains in the same sampled walk")
  func lifecycleFindingRemains() {
    withRestoredProbeState {
      SoundnessProbeConfiguration.isEnabled = false
      let root = nestedRoot(
        lifecycleMetadata: LifecycleMetadata(
          appearHandlerIDs: ["appear-leaf"],
          disappearHandlerIDs: ["disappear-leaf"]
        )
      )
      let before = SoundnessCounterSnapshot.current()

      inspectSampled(
        root,
        registrations: RuntimeRegistrationSet(lifecycleRegistry: LocalLifecycleRegistry())
      )

      let after = SoundnessCounterSnapshot.current()
      #expect(
        after.committedHandlerResolutionViolationCount
          == before.committedHandlerResolutionViolationCount + 1
      )
      #expect(
        after.lastViolationDetailByKind["committed-handler-resolution"]
          == """
          committed handler resolution: committed tree names handlers absent \
          from the published lifecycle registry: appear:appear-leaf, disappear:disappear-leaf \
          [mode=test roots=1]
          """
      )
    }
  }

  @Test("action dispatch miss records only a failed lookup")
  func actionDispatchMissRecordsFailedLookupOnly() {
    withRestoredProbeState {
      let identity = testIdentity("Root", "Branch", "Action")
      let registry = LocalActionRegistry()
      registry.register(identity: identity) { false }
      let before = SoundnessCounterSnapshot.current()

      #expect(!registry.dispatch(identity: identity))
      #expect(
        SoundnessCounterSnapshot.current().actionDispatchMissCount
          == before.actionDispatchMissCount
      )

      registry.reset()
      #expect(!registry.dispatch(identity: identity))

      let after = SoundnessCounterSnapshot.current()
      #expect(after.actionDispatchMissCount == before.actionDispatchMissCount + 1)
      #expect(
        after.lastViolationDetailByKind["action-dispatch-miss"]
          == "action dispatch: no published handler for \(identity.path)"
      )
      #expect(
        after.violationGrowth(since: before) == [
          SoundnessCounterGrowth(
            kind: "action-dispatch-miss",
            count: 1,
            detail: "action dispatch: no published handler for \(identity.path)"
          )
        ]
      )
    }
  }

  private func inspectSampled(
    _ root: ResolvedNode,
    registrations: RuntimeRegistrationSet
  ) {
    guard SoundnessProbeConfiguration.isSampledFrame else {
      return
    }
    CommittedHandlerResolutionOracle.inspect(
      committedRoot: root,
      registrations: registrations,
      publicationModeName: "test",
      publicationSubtreeRootCount: 1
    )
  }

  private func nestedRoot(
    inventory: CommittedHandlerInventory = .init(),
    lifecycleMetadata: LifecycleMetadata = .init()
  ) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          identity: testIdentity("Root", "Branch"),
          kind: .view("Branch"),
          children: [
            ResolvedNode(
              identity: testIdentity("Root", "Branch", "Leaf"),
              kind: .view("Leaf"),
              lifecycleMetadata: lifecycleMetadata,
              handlerInventory: inventory
            )
          ]
        )
      ]
    )
  }

  private func registerGesture(
    _ identity: Identity,
    in registrations: RuntimeRegistrationSet
  ) {
    registrations.gestureRegistry?.register(
      identity: identity,
      recognizer: AnyGestureRecognizer(TotalityProbeGesture())
    )
    registrations.pointerHandlerRegistry?.register(
      routeID: RouteID(identity: identity)
    ) { _ in .ignored }
  }

  private func resolutionDetail(
    family: InteractiveHandlerResolutionFamily,
    findings: [String]
  ) -> String {
    """
    committed handler resolution: committed tree names \(family.rawValue) handlers absent \
    from the published registry: \(findings.joined(separator: ", ")) \
    [mode=test roots=1]
    """
  }

  private func expectOnlyFamilyGrowth(
    _ family: InteractiveHandlerResolutionFamily,
    before: SoundnessCounterSnapshot,
    after: SoundnessCounterSnapshot
  ) {
    #expect(
      after.actionResolutionViolationCount - before.actionResolutionViolationCount
        == (family == .action ? 1 : 0)
    )
    #expect(
      after.keyHandlerResolutionViolationCount - before.keyHandlerResolutionViolationCount
        == (family == .key ? 1 : 0)
    )
    #expect(
      after.commandScopeResolutionViolationCount - before.commandScopeResolutionViolationCount
        == (family == .command ? 1 : 0)
    )
    #expect(
      after.dropScopeResolutionViolationCount - before.dropScopeResolutionViolationCount
        == (family == .drop ? 1 : 0)
    )
    #expect(
      after.gestureRouteResolutionViolationCount - before.gestureRouteResolutionViolationCount
        == (family == .gesture ? 1 : 0)
    )
    #expect(
      after.violationGrowth(since: before) == [
        SoundnessCounterGrowth(
          kind: family.traceKind,
          count: 1,
          detail: after.lastViolationDetailByKind[family.traceKind]
        )
      ]
    )
  }

  private func withRestoredProbeState(_ body: () throws -> Void) rethrows {
    let state = OracleProbeState.capture()
    defer { state.restore() }
    SoundnessProbeConfiguration.isSampledFrame = true
    SoundnessProbeConfiguration.isTraceEnabled = false
    try body()
  }
}

@MainActor
private struct OracleProbeState {
  let isEnabled: Bool
  let isSampledFrame: Bool
  let isTraceEnabled: Bool
  let committedHandlerResolutionViolationCount: Int
  let actionResolutionViolationCount: Int
  let keyHandlerResolutionViolationCount: Int
  let commandScopeResolutionViolationCount: Int
  let dropScopeResolutionViolationCount: Int
  let gestureRouteResolutionViolationCount: Int
  let actionDispatchMissCount: Int
  let lastViolationDetail: String?
  let lastViolationDetailByKind: [String: String]

  static func capture() -> Self {
    Self(
      isEnabled: SoundnessProbeConfiguration.isEnabled,
      isSampledFrame: SoundnessProbeConfiguration.isSampledFrame,
      isTraceEnabled: SoundnessProbeConfiguration.isTraceEnabled,
      committedHandlerResolutionViolationCount:
        SoundnessProbeConfiguration.committedHandlerResolutionViolationCount,
      actionResolutionViolationCount: SoundnessProbeConfiguration.actionResolutionViolationCount,
      keyHandlerResolutionViolationCount:
        SoundnessProbeConfiguration.keyHandlerResolutionViolationCount,
      commandScopeResolutionViolationCount:
        SoundnessProbeConfiguration.commandScopeResolutionViolationCount,
      dropScopeResolutionViolationCount:
        SoundnessProbeConfiguration.dropScopeResolutionViolationCount,
      gestureRouteResolutionViolationCount:
        SoundnessProbeConfiguration.gestureRouteResolutionViolationCount,
      actionDispatchMissCount: SoundnessProbeConfiguration.actionDispatchMissCount,
      lastViolationDetail: SoundnessProbeConfiguration.lastViolationDetail,
      lastViolationDetailByKind: SoundnessProbeConfiguration.lastViolationDetailByKind
    )
  }

  func restore() {
    SoundnessProbeConfiguration.isEnabled = isEnabled
    SoundnessProbeConfiguration.isSampledFrame = isSampledFrame
    SoundnessProbeConfiguration.isTraceEnabled = isTraceEnabled
    SoundnessProbeConfiguration.committedHandlerResolutionViolationCount =
      committedHandlerResolutionViolationCount
    SoundnessProbeConfiguration.actionResolutionViolationCount = actionResolutionViolationCount
    SoundnessProbeConfiguration.keyHandlerResolutionViolationCount =
      keyHandlerResolutionViolationCount
    SoundnessProbeConfiguration.commandScopeResolutionViolationCount =
      commandScopeResolutionViolationCount
    SoundnessProbeConfiguration.dropScopeResolutionViolationCount =
      dropScopeResolutionViolationCount
    SoundnessProbeConfiguration.gestureRouteResolutionViolationCount =
      gestureRouteResolutionViolationCount
    SoundnessProbeConfiguration.actionDispatchMissCount = actionDispatchMissCount
    SoundnessProbeConfiguration.lastViolationDetail = lastViolationDetail
    SoundnessProbeConfiguration.lastViolationDetailByKind = lastViolationDetailByKind
  }
}
