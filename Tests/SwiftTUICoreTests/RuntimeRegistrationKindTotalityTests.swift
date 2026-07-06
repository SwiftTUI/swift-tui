import Testing

@testable import SwiftTUICore

/// Totality guards for the unified registry lifecycle (F17). The bulk
/// operations on `RuntimeRegistrationSet` are loops over `allRegistries`
/// through the `RuntimeRegistry` contract, so the properties these tests pin
/// are what "every fan-out covers every family by construction" means:
/// membership (every kind present exactly once), oracle visibility (every
/// family projects fingerprint buckets — the F62 gap), frame-drop blocking,
/// node-record round-tripping, and absorb-adoption totality. Adding a
/// `RuntimeRegistrationKind` case fails these tests (and the exhaustive
/// switches below) until the new family is wired everywhere.
@MainActor
@Suite
struct RuntimeRegistrationKindTotalityTests {
  @Test("scratch set covers every registration kind exactly once")
  func scratchSetCoversEveryKindExactlyOnce() {
    let kinds = RuntimeRegistrationSet.scratch().allRegistries.map { registry in
      type(of: registry).kind
    }
    #expect(kinds.count == RuntimeRegistrationKind.allCases.count)
    #expect(Set(kinds) == Set(RuntimeRegistrationKind.allCases))
  }

  @Test(
    "each family round-trips node record -> restore -> fingerprint and raises its blocker",
    arguments: RuntimeRegistrationKind.allCases
  )
  func familyRoundTripsThroughRestoreAndFingerprint(_ kind: RuntimeRegistrationKind) {
    let identity = testIdentity("Root", "Leaf")
    let node = makeRecordingNode(identity: identity)
    ViewNodeContext.withValue(node) {
      record(kind, on: node, identity: identity)
    }
    #expect(node.registeredHandlers.hasRuntimeRegistrations)

    let set = RuntimeRegistrationSet.scratch()
    set.restore(from: node.registeredHandlers)

    let namespaces = fingerprintNamespaces(set.publicationOracleFingerprint())
    #expect(namespaces == Self.expectedFingerprintNamespaces(for: kind))
    #expect(set.frameDropEligibilityBlockers() == [Self.expectedBlocker(for: kind)])
  }

  @Test("absorbAdopted carries every family's registrations")
  func absorbAdoptedCarriesEveryFamily() {
    let identity = testIdentity("Root", "Leaf")
    let node = makeRecordingNode(identity: identity)
    // One capture session: each `ViewNodeContext.withValue` entry RESETS the
    // node's recorded registrations (publication replaces, not accumulates —
    // see `ViewNode.beginRegistrationCapture`), so per-kind sessions would
    // leave only the last family recorded and the equality below would pass
    // vacuously.
    ViewNodeContext.withValue(node) {
      for kind in RuntimeRegistrationKind.allCases {
        record(kind, on: node, identity: identity)
      }
    }

    let direct = RuntimeRegistrationSet.scratch()
    direct.restore(from: node.registeredHandlers)

    var absorber = NodeHandlers()
    absorber.absorbAdopted(node.registeredHandlers)
    let absorbed = RuntimeRegistrationSet.scratch()
    absorbed.restore(from: absorber)

    // Non-vacuity anchor: the direct restore must project EVERY family's
    // namespaces before the absorb-equality comparison means anything.
    let directFingerprint = direct.publicationOracleFingerprint()
    let allNamespaces = Set(
      RuntimeRegistrationKind.allCases.flatMap(Self.expectedFingerprintNamespaces)
    )
    #expect(fingerprintNamespaces(directFingerprint) == allNamespaces)
    #expect(absorbed.publicationOracleFingerprint() == directFingerprint)
  }

  @Test("effect restore covers exactly the effect registries")
  func effectRestoreCoversExactlyTheEffectRegistries() {
    let identity = testIdentity("Root", "Leaf")
    let node = makeRecordingNode(identity: identity)
    ViewNodeContext.withValue(node) {
      for kind in RuntimeRegistrationKind.allCases {
        record(kind, on: node, identity: identity)
      }
    }

    let set = RuntimeRegistrationSet.scratch()
    set.restoreEffectRegistrations(from: node.registeredHandlers)

    let effectNamespaces = Set(
      RuntimeRegistrationKind.allCases
        .filter(Self.isEffectKind)
        .flatMap(Self.expectedFingerprintNamespaces)
    )
    #expect(fingerprintNamespaces(set.publicationOracleFingerprint()) == effectNamespaces)
  }

  @Test("hasEffectRegistrations agrees with the effect-kind classification")
  func hasEffectRegistrationsAgreesWithEffectKinds() {
    // The effect-republication walk skips nodes where
    // `hasEffectRegistrations` is false (F63), so the disjunction must cover
    // exactly the effect families: a kind classified as effect here whose
    // family is missing from `hasEffectRegistrations` would make the walk
    // silently drop that family's live handlers.
    for kind in RuntimeRegistrationKind.allCases {
      let identity = testIdentity("Root", "Leaf")
      let node = makeRecordingNode(identity: identity)
      ViewNodeContext.withValue(node) {
        record(kind, on: node, identity: identity)
      }
      #expect(
        node.registeredHandlers.hasEffectRegistrations == Self.isEffectKind(kind),
        "kind \(kind) hasEffectRegistrations mismatch"
      )
    }
  }

  // MARK: - Per-kind expectations

  /// The `registry|key` namespaces one recorded registration of this family
  /// must project into the publication-oracle fingerprint. Exhaustive: a new
  /// kind does not compile until it declares its oracle projection here.
  private static func expectedFingerprintNamespaces(
    for kind: RuntimeRegistrationKind
  ) -> Set<String> {
    switch kind {
    case .action:
      ["action"]
    case .keyHandler:
      ["keyHandler", "keyPress", "paste"]
    case .termination:
      ["termination"]
    case .pointerHandler:
      ["pointer", "hover"]
    case .gesture:
      ["gesture"]
    case .gestureState:
      ["gestureState"]
    case .defaultFocus:
      ["defaultFocusScope", "defaultFocusCandidate"]
    case .focusBinding:
      ["focusBinding"]
    case .focusedValues:
      ["focusedValues"]
    case .scrollPosition:
      ["scrollPosition"]
    case .lifecycle:
      ["lifecycleAppear", "lifecycleDisappear", "lifecycleChange"]
    case .task:
      ["task"]
    case .preferenceObservation:
      ["preferenceObservation"]
    case .command:
      ["command"]
    case .dropDestination:
      ["dropDestination"]
    }
  }

  private static func expectedBlocker(
    for kind: RuntimeRegistrationKind
  ) -> FrameDropEligibility.Blocker {
    switch kind {
    case .action, .keyHandler, .termination, .pointerHandler, .gesture,
      .gestureState, .command, .dropDestination:
      .handlerInstallations
    case .defaultFocus, .focusBinding:
      .focusBindingSync
    case .focusedValues:
      .focusedValueSync
    case .scrollPosition:
      .scrollSync
    case .lifecycle:
      .lifecycleChange
    case .task:
      .taskStart
    case .preferenceObservation:
      .preferenceObservationDelta
    }
  }

  private static func isEffectKind(_ kind: RuntimeRegistrationKind) -> Bool {
    switch kind {
    case .lifecycle, .task, .preferenceObservation:
      true
    case .action, .keyHandler, .termination, .pointerHandler, .gesture,
      .gestureState, .defaultFocus, .focusBinding, .focusedValues,
      .scrollPosition, .command, .dropDestination:
      false
    }
  }

  // MARK: - Recording

  private func makeRecordingNode(identity: Identity) -> ViewNode {
    let graph = ViewGraph()
    graph.beginFrame()
    return graph.beginEvaluation(identity: identity, invalidator: nil)
  }

  /// Records one representative registration of `kind` on `node`, mirroring
  /// how resolve-time registration reaches `NodeHandlers`. Callers must wrap
  /// the call(s) in ONE `ViewNodeContext.withValue(node)` capture session —
  /// entering a session resets the node's recorded registrations. Exhaustive
  /// over the kind list so a new family must define its seeding before the
  /// totality suite compiles.
  private func record(
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
        lifecycleRegistration(identity: identity, node: node, suffix: .appear(ordinal: 0))
      )
      node.recordLifecycleDisappearRegistration(
        lifecycleRegistration(identity: identity, node: node, suffix: .disappear(ordinal: 0))
      )
      node.recordLifecycleChangeRegistration(
        lifecycleRegistration(identity: identity, node: node, suffix: .change(ordinal: 0))
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

  private func lifecycleRegistration(
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

  private func fingerprintNamespaces(_ fingerprint: [String: Int]) -> Set<String> {
    Set(
      fingerprint.keys.map { key in
        String(key.prefix(while: { $0 != "|" }))
      })
  }
}

private enum TotalityProbePreferenceKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(
    value: inout Int,
    nextValue: () -> Int
  ) {
    value = nextValue()
  }
}

private enum TotalityProbeFocusedValueKey: FocusedValueKey {
  typealias Value = String
}

@MainActor
private final class TotalityProbeGesture: GestureRecognizer {
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
}
