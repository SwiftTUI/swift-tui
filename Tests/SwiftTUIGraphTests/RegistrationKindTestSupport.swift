import Testing

@testable import SwiftTUIGraph

/// Per-kind registration driver shared by the registry totality and lifecycle
/// suites: records one representative registration of each
/// `RuntimeRegistrationKind` on a capture-session node, mirroring how
/// resolve-time registration reaches `NodeHandlers`. Adding a kind fails the
/// exhaustive switch here until the new family gains a probe registration.
@MainActor
enum RegistrationKindDriver {
  static func makeRecordingNode(identity: Identity) -> ViewNode {
    let graph = ViewGraph()
    graph.beginFrame()
    return graph.beginEvaluation(identity: identity, invalidator: nil)
  }

  /// Multiple recording nodes minted by ONE graph, so their `viewNodeID`s are
  /// distinct the way production nodes are. Two separate `ViewGraph`s mint
  /// identical raw IDs (each graph's counter starts at the same seed), which
  /// makes ownerNodeID-keyed families (lifecycle) collide in ways impossible
  /// in a real tree.
  static func makeRecordingNodes(identities: [Identity]) -> [ViewNode] {
    let graph = ViewGraph()
    graph.beginFrame()
    return identities.map { identity in
      graph.beginEvaluation(identity: identity, invalidator: nil)
    }
  }

  /// Records one representative registration of `kind` on `node`, mirroring
  /// how resolve-time registration reaches `NodeHandlers`. Callers must wrap
  /// the call(s) in ONE `ViewNodeContext.withValue(node)` capture session —
  /// entering a session resets the node's recorded registrations. Exhaustive
  /// over the kind list so a new family must define its seeding before the
  /// totality suite compiles.
  static func record(
    _ kind: RuntimeRegistrationKind,
    on node: ViewNode,
    identity: Identity
  ) {
    switch kind {
    case .action:
      node.recordActionRegistration(
        identity: identity,
        handler: { false },
        followUpInvalidationIdentity: nil
      )
    case .keyHandler:
      node.recordKeyHandlerRegistration(identity: identity) { _ in false }
      node.recordKeyPressHandlerRegistration(identity: identity, ordinal: 0) { _ in false }
      node.recordPasteHandlerRegistration(identity: identity, ordinal: 0) { _ in false }
    case .termination:
      node.recordTerminationHandlerRegistration(identity: identity) { _ in .allow }
    case .pointerHandler:
      let routeID = RouteID(identity: identity)
      node.recordPointerHandlerRegistration(routeID: routeID) { _ in false }
      node.recordPointerHoverHandlerRegistration(routeID: routeID) { _ in }
    case .gesture:
      node.recordGestureRegistration(
        identity: identity,
        recognizer: AnyGestureRecognizer(TotalityProbeGesture())
      )
    case .gestureState:
      node.recordGestureStateBinding(
        identity: identity,
        binding: AnyGestureStateBinding(
          valueType: Int.self,
          setValue: { _ in },
          reset: {}
        )
      )
    case .defaultFocus:
      let namespace = MatchedGeometryNamespace(0)
      node.recordDefaultFocus(
        DefaultFocusScopeRegistrationSnapshot(namespace: namespace, identity: identity)
      )
      node.recordDefaultFocus(
        DefaultFocusCandidateRegistrationSnapshot(namespace: namespace, identity: identity)
      )
    case .focusBinding:
      node.recordFocusBindingRegistration(
        FocusBindingRegistrationSnapshot(
          identity: identity,
          bindingID: "binding-\(identity.path)",
          hasPendingRequest: false,
          isSelected: false,
          applyRuntimeFocus: { _ in false }
        )
      )
    case .focusedValues:
      var values = FocusedValues()
      values[TotalityProbeFocusedValueKey.self] = "probe"
      node.recordFocusedValuesRegistration(
        FocusedValuesRegistrationSnapshot(
          identity: identity,
          descendantIdentities: [identity],
          values: values
        )
      )
    case .scrollPosition:
      node.recordScrollPositionRegistration(
        ScrollPositionRegistrationSnapshot(
          identity: identity,
          currentOffset: { ScrollOffset(x: 0, y: 0) },
          applyOffset: { _ in }
        )
      )
    case .lifecycle:
      node.recordLifecycleAppearRegistration(
        RegistrationKindDriver.lifecycleRegistration(identity: identity, node: node, suffix: .appear(ordinal: 0))
      )
      node.recordLifecycleDisappearRegistration(
        RegistrationKindDriver.lifecycleRegistration(identity: identity, node: node, suffix: .disappear(ordinal: 0))
      )
      node.recordLifecycleChangeRegistration(
        RegistrationKindDriver.lifecycleRegistration(identity: identity, node: node, suffix: .change(ordinal: 0))
      )
    case .task:
      node.recordTaskRegistration(
        identity: identity,
        registration: TaskRegistration(
          descriptor: TaskDescriptor(id: "task-probe", priority: .medium),
          operation: {}
        )
      )
    case .preferenceObservation:
      // Registering against a throwaway registry mirrors the snapshot into
      // the current node context; the snapshot's observation box is not
      // constructible outside its file.
      let registry = LocalPreferenceObservationRegistry()
      registry.register(
        identity: identity,
        key: TotalityProbePreferenceKey.self,
        value: 0,
        action: { _ in }
      )
    case .command:
      let binding = KeyBinding(key: .character("r"), modifiers: [.ctrl])
      node.recordCommandRegistration(
        CommandRegistrySnapshot(
          keyCommandsByScope: [
            identity: [
              binding: RegisteredKeyCommand(
                binding: binding,
                description: "probe",
                isEnabled: true,
                action: {}
              )
            ]
          ],
          ownersByScope: [identity: .current(identity: identity)]
        )
      )
    case .dropDestination:
      node.recordDropDestinationRegistration(
        DropDestinationRegistrySnapshot(
          handlersByScope: [identity: { _, _ in false }],
          ownersByScope: [identity: .current(identity: identity)]
        )
      )
    }
  }

  static func lifecycleRegistration(
    identity: Identity,
    node: ViewNode,
    suffix: LifecycleHandlerKeySuffix
  ) -> LifecycleHandlerRegistration {
    LifecycleHandlerRegistration(
      identity: identity,
      key: LifecycleHandlerKey(ownerNodeID: node.viewNodeID, suffix: suffix),
      handlerID: "\(identity.path)#\(suffix)",
      handler: {}
    )
  }

  static func fingerprintNamespaces(_ fingerprint: [String: Int]) -> Set<String> {
    Set(
      fingerprint.keys.map { key in
        String(key.prefix(while: { $0 != "|" }))
      })
  }
}

enum TotalityProbePreferenceKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(
    value: inout Int,
    nextValue: () -> Int
  ) {
    value = nextValue()
  }
}

enum TotalityProbeFocusedValueKey: FocusedValueKey {
  typealias Value = String
}

@MainActor
final class TotalityProbeGesture: GestureRecognizer {
  typealias Value = String

  var phase: GestureRecognizerPhase { .possible }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    .ignored
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    false
  }

  func currentValue() -> String? {
    "probe"
  }

  func tearDown() {}

  func reArm() {}
}
