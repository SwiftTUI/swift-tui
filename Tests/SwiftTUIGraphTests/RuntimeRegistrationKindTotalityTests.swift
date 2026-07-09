import Testing

@testable import SwiftTUIGraph

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
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    ViewNodeContext.withValue(node) {
      RegistrationKindDriver.record(kind, on: node, identity: identity)
    }
    #expect(node.registeredHandlers.hasRuntimeRegistrations)

    let set = RuntimeRegistrationSet.scratch()
    set.restore(from: node.registeredHandlers)

    let namespaces = RegistrationKindDriver.fingerprintNamespaces(set.publicationOracleFingerprint())
    #expect(namespaces == Self.expectedFingerprintNamespaces(for: kind))
    #expect(set.frameDropEligibilityBlockers() == [Self.expectedBlocker(for: kind)])
  }

  @Test("absorbAdopted carries every family's registrations")
  func absorbAdoptedCarriesEveryFamily() {
    let identity = testIdentity("Root", "Leaf")
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    // One capture session: each `ViewNodeContext.withValue` entry RESETS the
    // node's recorded registrations (publication replaces, not accumulates —
    // see `ViewNode.beginRegistrationCapture`), so per-kind sessions would
    // leave only the last family recorded and the equality below would pass
    // vacuously.
    ViewNodeContext.withValue(node) {
      for kind in RuntimeRegistrationKind.allCases {
        RegistrationKindDriver.record(kind, on: node, identity: identity)
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
    #expect(RegistrationKindDriver.fingerprintNamespaces(directFingerprint) == allNamespaces)
    #expect(absorbed.publicationOracleFingerprint() == directFingerprint)
  }

  @Test("effect restore covers exactly the effect registries")
  func effectRestoreCoversExactlyTheEffectRegistries() {
    let identity = testIdentity("Root", "Leaf")
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    ViewNodeContext.withValue(node) {
      for kind in RuntimeRegistrationKind.allCases {
        RegistrationKindDriver.record(kind, on: node, identity: identity)
      }
    }

    let set = RuntimeRegistrationSet.scratch()
    set.restoreEffectRegistrations(from: node.registeredHandlers)

    let effectNamespaces = Set(
      RuntimeRegistrationKind.allCases
        .filter(Self.isEffectKind)
        .flatMap(Self.expectedFingerprintNamespaces)
    )
    #expect(RegistrationKindDriver.fingerprintNamespaces(set.publicationOracleFingerprint()) == effectNamespaces)
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
      let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
      ViewNodeContext.withValue(node) {
        RegistrationKindDriver.record(kind, on: node, identity: identity)
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
  ) -> FrameDropBlocker {
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

}

