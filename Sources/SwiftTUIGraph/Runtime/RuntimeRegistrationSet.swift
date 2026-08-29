public struct RuntimeRegistrationDiagnostics: Equatable, Sendable {
  public var pointerHandlerCount: Int
  public var pointerHoverHandlerCount: Int
  public var gestureRecognizerCount: Int
  public var gestureStateBindingCount: Int
  private var publicationStorage: RuntimeRegistrationPublicationDiagnosticsStorage
  package var publication: RuntimeRegistrationPublicationDiagnostics {
    get {
      publicationStorage.value
    }
    set {
      publicationStorage.value = newValue
    }
  }

  public init(
    pointerHandlerCount: Int = 0,
    pointerHoverHandlerCount: Int = 0,
    gestureRecognizerCount: Int = 0,
    gestureStateBindingCount: Int = 0
  ) {
    self.pointerHandlerCount = pointerHandlerCount
    self.pointerHoverHandlerCount = pointerHoverHandlerCount
    self.gestureRecognizerCount = gestureRecognizerCount
    self.gestureStateBindingCount = gestureStateBindingCount
    self.publicationStorage = .init(value: .init())
  }
}

// Keep package-only publication diagnostics out of the public synthesized
// `RuntimeRegistrationDiagnostics` equality contract.
private struct RuntimeRegistrationPublicationDiagnosticsStorage: Equatable, Sendable {
  var value: RuntimeRegistrationPublicationDiagnostics

  static func == (
    lhs: RuntimeRegistrationPublicationDiagnosticsStorage,
    rhs: RuntimeRegistrationPublicationDiagnosticsStorage
  ) -> Bool {
    true
  }
}

/// Identity of one concrete runtime-registration publication target.
///
/// A `RuntimeRegistrationSet` is a value aggregate over reference-typed member
/// registries. Lifetime-safe member tokens, in the aggregate's canonical
/// fan-out order, distinguish the persistent target a committed fingerprint
/// describes from a fresh ResolveContext set that starts empty. Tokens remain
/// unique after their weakly held registry referents are released.
package struct RuntimeRegistrationTargetIdentity: Equatable, Sendable {
  private let memberTokens: [RuntimeRegistryIdentityToken]

  @MainActor
  fileprivate init(registries: [any RuntimeRegistry]) {
    memberTokens = RuntimeRegistryIdentityTokenTable.shared.tokens(for: registries)
  }
}

struct RuntimeRegistryIdentityToken: Equatable, Sendable {
  let rawValue: UInt64
}

@MainActor
final class RuntimeRegistryIdentityTokenTable {
  fileprivate static let shared = RuntimeRegistryIdentityTokenTable()

  private final class WeakEntry {
    weak var registry: (any RuntimeRegistry)?
    let token: RuntimeRegistryIdentityToken

    init(
      registry: any RuntimeRegistry,
      token: RuntimeRegistryIdentityToken
    ) {
      self.registry = registry
      self.token = token
    }
  }

  private var entriesByLookupKey: [ObjectIdentifier: WeakEntry] = [:]
  private var nextTokenRawValue: UInt64 = 0

  init() {}

  fileprivate func tokens(
    for registries: [any RuntimeRegistry]
  ) -> [RuntimeRegistryIdentityToken] {
    entriesByLookupKey = entriesByLookupKey.filter { $0.value.registry != nil }
    return registries.map { token(for: $0) }
  }

  private func token(for registry: any RuntimeRegistry) -> RuntimeRegistryIdentityToken {
    token(for: registry, lookupKey: ObjectIdentifier(registry))
  }

  func token(
    for registry: any RuntimeRegistry,
    lookupKey: ObjectIdentifier
  ) -> RuntimeRegistryIdentityToken {
    if let entry = entriesByLookupKey[lookupKey],
      let priorRegistry = entry.registry,
      priorRegistry === registry
    {
      return entry.token
    }

    precondition(
      nextTokenRawValue != UInt64.max,
      "runtime registry identity token space exhausted"
    )
    nextTokenRawValue += 1
    let token = RuntimeRegistryIdentityToken(rawValue: nextTokenRawValue)
    entriesByLookupKey[lookupKey] = WeakEntry(registry: registry, token: token)
    return token
  }
}

@MainActor
package struct RuntimeRegistrationSet {
  package let actionRegistry: LocalActionRegistry?
  package let keyHandlerRegistry: LocalKeyHandlerRegistry?
  package let terminationRegistry: LocalTerminationRegistry?
  package let pointerHandlerRegistry: LocalPointerHandlerRegistry?
  package let gestureRegistry: LocalGestureRegistry?
  package let gestureStateRegistry: LocalGestureStateRegistry?
  package let defaultFocusRegistry: LocalDefaultFocusRegistry?
  package let focusBindingRegistry: LocalFocusBindingRegistry?
  package let focusedValuesRegistry: LocalFocusedValuesRegistry?
  package let scrollPositionRegistry: LocalScrollPositionRegistry?
  package let lifecycleRegistry: LocalLifecycleRegistry?
  package let taskRegistry: LocalTaskRegistry?
  package let preferenceObservationRegistry: LocalPreferenceObservationRegistry?
  package let commandRegistry: CommandRegistry?
  package let dropDestinationRegistry: DropDestinationRegistry?

  /// Every present member registry in canonical fan-out order. All bulk
  /// lifecycle operations (reset, subtree removal, restore, fingerprinting,
  /// frame-drop blockers) iterate this list, so a member participates in
  /// every fan-out by construction. `RuntimeRegistrationKindTotalityTests`
  /// asserts the list covers every ``RuntimeRegistrationKind`` exactly once
  /// for a `scratch()` set.
  package let allRegistries: [any RuntimeRegistry]

  /// The `isEffectRegistry` subset of ``allRegistries``, precomputed so the
  /// per-node effect-republication walk (every live node, every commit) does
  /// not re-filter the full registry list per node (F63).
  package let effectRegistries: [any RuntimeRegistry]

  package init(
    actionRegistry: LocalActionRegistry? = nil,
    keyHandlerRegistry: LocalKeyHandlerRegistry? = nil,
    terminationRegistry: LocalTerminationRegistry? = nil,
    pointerHandlerRegistry: LocalPointerHandlerRegistry? = nil,
    gestureRegistry: LocalGestureRegistry? = nil,
    gestureStateRegistry: LocalGestureStateRegistry? = nil,
    defaultFocusRegistry: LocalDefaultFocusRegistry? = nil,
    focusBindingRegistry: LocalFocusBindingRegistry? = nil,
    focusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
    scrollPositionRegistry: LocalScrollPositionRegistry? = nil,
    lifecycleRegistry: LocalLifecycleRegistry? = nil,
    taskRegistry: LocalTaskRegistry? = nil,
    preferenceObservationRegistry: LocalPreferenceObservationRegistry? = nil,
    commandRegistry: CommandRegistry? = nil,
    dropDestinationRegistry: DropDestinationRegistry? = nil
  ) {
    self.actionRegistry = actionRegistry
    self.keyHandlerRegistry = keyHandlerRegistry
    self.terminationRegistry = terminationRegistry
    self.pointerHandlerRegistry = pointerHandlerRegistry
    self.gestureRegistry = gestureRegistry
    self.gestureStateRegistry = gestureStateRegistry
    self.defaultFocusRegistry = defaultFocusRegistry
    self.focusBindingRegistry = focusBindingRegistry
    self.focusedValuesRegistry = focusedValuesRegistry
    self.scrollPositionRegistry = scrollPositionRegistry
    self.lifecycleRegistry = lifecycleRegistry
    self.taskRegistry = taskRegistry
    self.preferenceObservationRegistry = preferenceObservationRegistry
    self.commandRegistry = commandRegistry
    self.dropDestinationRegistry = dropDestinationRegistry
    let members: [(any RuntimeRegistry)?] = [
      actionRegistry,
      keyHandlerRegistry,
      terminationRegistry,
      pointerHandlerRegistry,
      gestureRegistry,
      gestureStateRegistry,
      defaultFocusRegistry,
      focusBindingRegistry,
      focusedValuesRegistry,
      scrollPositionRegistry,
      lifecycleRegistry,
      taskRegistry,
      preferenceObservationRegistry,
      commandRegistry,
      dropDestinationRegistry,
    ]
    allRegistries = members.compactMap { $0 }
    effectRegistries = allRegistries.filter(\.isEffectRegistry)
  }

  @MainActor
  package static func scratch() -> RuntimeRegistrationSet {
    RuntimeRegistrationSet(
      actionRegistry: LocalActionRegistry(),
      keyHandlerRegistry: LocalKeyHandlerRegistry(),
      terminationRegistry: LocalTerminationRegistry(),
      pointerHandlerRegistry: LocalPointerHandlerRegistry(),
      gestureRegistry: LocalGestureRegistry(),
      gestureStateRegistry: LocalGestureStateRegistry(),
      defaultFocusRegistry: LocalDefaultFocusRegistry(),
      focusBindingRegistry: LocalFocusBindingRegistry(),
      focusedValuesRegistry: LocalFocusedValuesRegistry(),
      scrollPositionRegistry: LocalScrollPositionRegistry(),
      lifecycleRegistry: LocalLifecycleRegistry(),
      taskRegistry: LocalTaskRegistry(),
      preferenceObservationRegistry: LocalPreferenceObservationRegistry(),
      commandRegistry: CommandRegistry(),
      dropDestinationRegistry: DropDestinationRegistry()
    )
  }

  /// A scratch whose member shape mirrors `target`: a member is present here
  /// exactly where `target` has one.
  ///
  /// The publication oracle compares a scoped restore against a scratch full
  /// rebuild, and that comparison is only meaningful over registries the live
  /// target actually has. Members are optional — a host installs the
  /// registries it needs, and a bare `ResolveContext` (every `DefaultRenderer`
  /// stress render) installs none — while ``scratch()`` always builds all
  /// fifteen. Comparing a sparse target against a full scratch reports every
  /// registration of every absent kind as `live=0 rebuilt=1`, which is not a
  /// publication defect: publishing into a registry the target does not have
  /// is a no-op by construction, so a scoped restore cannot diverge there.
  /// Mirroring the membership keeps the oracle strict over the registries that
  /// exist and silent about the ones that cannot.
  @MainActor
  package static func scratch(
    mirroringMembershipOf target: RuntimeRegistrationSet
  ) -> RuntimeRegistrationSet {
    RuntimeRegistrationSet(
      actionRegistry: target.actionRegistry.map { _ in LocalActionRegistry() },
      keyHandlerRegistry: target.keyHandlerRegistry.map { _ in LocalKeyHandlerRegistry() },
      terminationRegistry: target.terminationRegistry.map { _ in LocalTerminationRegistry() },
      pointerHandlerRegistry: target.pointerHandlerRegistry.map { _ in
        LocalPointerHandlerRegistry()
      },
      gestureRegistry: target.gestureRegistry.map { _ in LocalGestureRegistry() },
      gestureStateRegistry: target.gestureStateRegistry.map { _ in LocalGestureStateRegistry() },
      defaultFocusRegistry: target.defaultFocusRegistry.map { _ in LocalDefaultFocusRegistry() },
      focusBindingRegistry: target.focusBindingRegistry.map { _ in LocalFocusBindingRegistry() },
      focusedValuesRegistry: target.focusedValuesRegistry.map { _ in LocalFocusedValuesRegistry() },
      scrollPositionRegistry: target.scrollPositionRegistry.map { _ in
        LocalScrollPositionRegistry()
      },
      lifecycleRegistry: target.lifecycleRegistry.map { _ in LocalLifecycleRegistry() },
      taskRegistry: target.taskRegistry.map { _ in LocalTaskRegistry() },
      preferenceObservationRegistry: target.preferenceObservationRegistry.map { _ in
        LocalPreferenceObservationRegistry()
      },
      commandRegistry: target.commandRegistry.map { _ in CommandRegistry() },
      dropDestinationRegistry: target.dropDestinationRegistry.map { _ in DropDestinationRegistry() }
    )
  }

  package var targetIdentity: RuntimeRegistrationTargetIdentity {
    RuntimeRegistrationTargetIdentity(registries: allRegistries)
  }
}
