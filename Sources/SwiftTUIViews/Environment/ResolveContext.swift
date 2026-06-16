public import SwiftTUICore

// The resolve context.
//
// `ResolveContext` is the per-pass configuration threaded through view
// resolution. Its public face is small — authored identity, environment,
// transaction, and invalidation scope — while the bulk of its surface is
// `package`: the runtime registries and lowering seams that the framework
// populates and reads while resolving a subtree. The `child`, `indexedChild`,
// and `replacingIdentity` builders derive the context for nested views; the
// `settingEnvironment` / `transformingEnvironment` builders fold environment
// edits back into the resolved snapshot.
//
// Split out of `Environment.swift` so that file stays focused on the
// environment value types (`EnvironmentKey`, `EnvironmentValues`,
// `Environment`, `EnvironmentReader`). `ResolveContext`'s own `private static`
// helpers travel with it; the only cross-file dependency is
// `EnvironmentValues.applying(to:reuseStyle:)`, which was widened from
// `fileprivate` to `package` so this file can reach it.

/// Public configuration for resolving a view subtree.
///
/// `ResolveContext` exposes the authored identity, environment, transaction,
/// and invalidation scope that affect a resolve pass. Runtime registries and
/// other lowering seams remain package-only.
public struct ResolveContext: Equatable, Sendable {
  public var identity: Identity
  package var structuralPath: StructuralPath
  public var environment: EnvironmentSnapshot
  public var environmentValues: EnvironmentValues
  package var focusedValues: FocusedValues
  public var transaction: TransactionSnapshot
  public var invalidatedIdentities: Set<Identity> {
    didSet {
      invalidationSummary = .init(
        invalidatedIdentities: invalidatedIdentities
      )
    }
  }
  package var invalidationSummary: InvalidationSummary
  package var forceRootEvaluation: Bool
  package var resolveWorkTracker: ResolveWorkTracker?
  package var localActionRegistry: LocalActionRegistry?
  package var localGestureRegistry: LocalGestureRegistry?
  package var localGestureStateRegistry: LocalGestureStateRegistry?
  package var localPointerHandlerRegistry: LocalPointerHandlerRegistry?
  package var localTerminationRegistry: LocalTerminationRegistry?
  package var localDefaultFocusRegistry: LocalDefaultFocusRegistry?
  package var localFocusBindingRegistry: LocalFocusBindingRegistry?
  package var localFocusedValuesRegistry: LocalFocusedValuesRegistry?
  package var localScrollPositionRegistry: LocalScrollPositionRegistry?
  package var localPreferenceObservationRegistry: LocalPreferenceObservationRegistry?
  package var localKeyHandlerRegistry: LocalKeyHandlerRegistry?
  package var localLifecycleRegistry: LocalLifecycleRegistry?
  package var localTaskRegistry: LocalTaskRegistry?
  package var commandRegistry: CommandRegistry?
  package var dropDestinationRegistry: DropDestinationRegistry?
  package var invalidationProxy: ResolveInvalidationProxy?
  package var observationBridge: ObservationBridge?
  package var viewGraph: ViewGraph?
  package var imageAssetResolver: ImageAssetResolver?
  package var frameInputs: FrameResolveInputBox?
  package var suppressesStructuralLifecycle: Bool
  /// Forwards deadline requests to the frame scheduler.
  /// Stored as a closure to avoid Sendable constraints on `FrameScheduling`.
  package var requestDeadline: (@MainActor @Sendable (MonotonicInstant) -> Void)?

  @MainActor
  package var runtimeRegistrations: RuntimeRegistrationSet {
    RuntimeRegistrationSet(
      actionRegistry: localActionRegistry,
      keyHandlerRegistry: localKeyHandlerRegistry,
      terminationRegistry: localTerminationRegistry,
      pointerHandlerRegistry: localPointerHandlerRegistry,
      gestureRegistry: localGestureRegistry,
      gestureStateRegistry: localGestureStateRegistry,
      defaultFocusRegistry: localDefaultFocusRegistry,
      focusBindingRegistry: localFocusBindingRegistry,
      focusedValuesRegistry: localFocusedValuesRegistry,
      scrollPositionRegistry: localScrollPositionRegistry,
      lifecycleRegistry: localLifecycleRegistry,
      taskRegistry: localTaskRegistry,
      preferenceObservationRegistry: localPreferenceObservationRegistry,
      commandRegistry: commandRegistry,
      dropDestinationRegistry: dropDestinationRegistry
    )
  }

  @MainActor
  package func replacingRuntimeRegistrations(
    _ registrations: RuntimeRegistrationSet
  ) -> Self {
    var replaced = self
    replaced.localActionRegistry = registrations.actionRegistry
    replaced.localKeyHandlerRegistry = registrations.keyHandlerRegistry
    replaced.localTerminationRegistry = registrations.terminationRegistry
    replaced.localPointerHandlerRegistry = registrations.pointerHandlerRegistry
    replaced.localGestureRegistry = registrations.gestureRegistry
    replaced.localGestureStateRegistry = registrations.gestureStateRegistry
    replaced.localDefaultFocusRegistry = registrations.defaultFocusRegistry
    replaced.localFocusBindingRegistry = registrations.focusBindingRegistry
    replaced.localFocusedValuesRegistry = registrations.focusedValuesRegistry
    replaced.localScrollPositionRegistry = registrations.scrollPositionRegistry
    replaced.localLifecycleRegistry = registrations.lifecycleRegistry
    replaced.localTaskRegistry = registrations.taskRegistry
    replaced.localPreferenceObservationRegistry = registrations.preferenceObservationRegistry
    replaced.commandRegistry = registrations.commandRegistry
    replaced.dropDestinationRegistry = registrations.dropDestinationRegistry
    return replaced
  }

  /// Creates a public resolve context from authored configuration only.
  public init(
    identity: Identity = .init(components: [] as [IdentityComponent]),
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    transaction: TransactionSnapshot = .init(),
    invalidatedIdentities: Set<Identity> = []
  ) {
    self.init(
      identity: identity,
      environment: environment,
      environmentValues: environmentValues,
      transaction: transaction,
      invalidatedIdentities: invalidatedIdentities,
      localActionRegistry: nil,
      localKeyHandlerRegistry: nil,
      localLifecycleRegistry: nil,
      localTaskRegistry: nil,
      applyEnvironmentValues: true
    )
  }

  package func child(component: IdentityComponent) -> Self {
    var childContext = Self(
      structuralIdentity: identity.child(component),
      structuralPath: structuralPath.appending(component),
      environment: environment,
      environmentValues: environmentValues,
      transaction: transaction,
      invalidatedIdentities: invalidatedIdentities,
      invalidationSummary: invalidationSummary,
      forceRootEvaluation: forceRootEvaluation,
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: false
    )
    childContext.localTerminationRegistry = localTerminationRegistry
    childContext.localGestureRegistry = localGestureRegistry
    childContext.localGestureStateRegistry = localGestureStateRegistry
    childContext.localPointerHandlerRegistry = localPointerHandlerRegistry
    childContext.localDefaultFocusRegistry = localDefaultFocusRegistry
    childContext.localFocusBindingRegistry = localFocusBindingRegistry
    childContext.localFocusedValuesRegistry = localFocusedValuesRegistry
    childContext.localScrollPositionRegistry = localScrollPositionRegistry
    childContext.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    childContext.commandRegistry = commandRegistry
    childContext.dropDestinationRegistry = dropDestinationRegistry
    childContext.invalidationProxy = invalidationProxy
    childContext.observationBridge = observationBridge
    childContext.viewGraph = viewGraph
    childContext.resolveWorkTracker = resolveWorkTracker
    childContext.focusedValues = focusedValues
    childContext.imageAssetResolver = imageAssetResolver
    childContext.frameInputs = frameInputs
    childContext.suppressesStructuralLifecycle = suppressesStructuralLifecycle
    childContext.requestDeadline = requestDeadline
    return childContext
  }

  package func indexedChild(kind: IdentityComponent, index: Int) -> Self {
    child(
      component: .init(
        rawValue: "\(kind.rawValue)[\(index)]"
      )
    )
  }

  package func replacingIdentity(with identity: Identity) -> Self {
    var replacedContext = Self(
      structuralIdentity: identity,
      structuralPath: structuralPath,
      environment: environment,
      environmentValues: environmentValues,
      transaction: transaction,
      invalidatedIdentities: invalidatedIdentities,
      invalidationSummary: invalidationSummary,
      forceRootEvaluation: forceRootEvaluation,
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: false
    )
    replacedContext.localTerminationRegistry = localTerminationRegistry
    replacedContext.localGestureRegistry = localGestureRegistry
    replacedContext.localGestureStateRegistry = localGestureStateRegistry
    replacedContext.localPointerHandlerRegistry = localPointerHandlerRegistry
    replacedContext.localDefaultFocusRegistry = localDefaultFocusRegistry
    replacedContext.localFocusBindingRegistry = localFocusBindingRegistry
    replacedContext.localFocusedValuesRegistry = localFocusedValuesRegistry
    replacedContext.localScrollPositionRegistry = localScrollPositionRegistry
    replacedContext.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    replacedContext.commandRegistry = commandRegistry
    replacedContext.dropDestinationRegistry = dropDestinationRegistry
    replacedContext.invalidationProxy = invalidationProxy
    replacedContext.observationBridge = observationBridge
    replacedContext.viewGraph = viewGraph
    replacedContext.resolveWorkTracker = resolveWorkTracker
    replacedContext.focusedValues = focusedValues
    replacedContext.imageAssetResolver = imageAssetResolver
    replacedContext.frameInputs = frameInputs
    replacedContext.suppressesStructuralLifecycle = suppressesStructuralLifecycle
    replacedContext.requestDeadline = requestDeadline
    return replacedContext
  }

  package func suppressingStructuralLifecycle() -> Self {
    var context = self
    context.suppressesStructuralLifecycle = true
    return context
  }

  package func settingEnvironment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    to value: Value
  ) -> Self {
    var copy = self
    copy.environmentValues[keyPath: keyPath] = value
    let reuseStyle = !Self.isStyleKeyPath(keyPath)
    copy.environment = copy.environmentValues.applying(
      to: copy.environment, reuseStyle: reuseStyle)
    return copy
  }

  package func transformingEnvironment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    transform: (inout Value) -> Void
  ) -> Self {
    var copy = self
    transform(&copy.environmentValues[keyPath: keyPath])
    let reuseStyle = !Self.isStyleKeyPath(keyPath)
    copy.environment = copy.environmentValues.applying(
      to: copy.environment, reuseStyle: reuseStyle)
    return copy
  }

  private static func isStyleKeyPath<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>
  ) -> Bool {
    let erased: AnyKeyPath = keyPath
    return erased == \EnvironmentValues.terminalAppearance
      || erased == \EnvironmentValues.theme
      || erased == \EnvironmentValues.foregroundStyle
      || erased == \EnvironmentValues.tintStyle
      || erased == \EnvironmentValues.isEnabled
  }

  /// Returns the current-frame resolve inputs when the renderer supplied them.
  @MainActor
  package var effectiveFrameResolveInputs: FrameResolveInputs? {
    frameInputs?.inputs
  }

  /// Returns this context refreshed with current-frame resolve inputs.
  @MainActor
  package func applyingCurrentFrameResolveInputs() -> Self {
    guard let inputs = effectiveFrameResolveInputs else {
      return self
    }
    var refreshed = self
    refreshed.invalidatedIdentities = inputs.invalidatedIdentities
    refreshed.invalidationSummary = inputs.invalidationSummary
    var environmentValues = refreshed.environmentValues
    environmentValues.focusedIdentity = inputs.environmentValues.focusedIdentity
    environmentValues.pressedIdentity = inputs.environmentValues.pressedIdentity
    refreshed.environmentValues = Self.contextualEnvironmentValues(
      environmentValues,
      for: refreshed.identity
    )
    refreshed.focusedValues = inputs.focusedValues
    refreshed.transaction = inputs.transaction
    refreshed.resolveWorkTracker = inputs.resolveWorkTracker
    return refreshed
  }

  /// Returns the effective per-frame invalidation set, preferring renderer-owned
  /// frame inputs when available.
  @MainActor
  package var effectiveInvalidatedIdentities: Set<Identity> {
    effectiveFrameResolveInputs?.invalidatedIdentities ?? invalidatedIdentities
  }

  /// Returns whether retained reuse is suppressed for `identity` in this frame.
  /// Suppressed identities recompute even when disjoint from ordinary
  /// invalidation. The run loop scopes this to focus/press runtime readers and
  /// active property-animation identities, with a conservative full-suppression
  /// fallback for identity-agnostic animation work.
  @MainActor
  package func effectiveSuppressesRetainedReuse(
    at identity: Identity
  ) -> Bool {
    effectiveFrameResolveInputs?.retainedReuseSuppressionScope
      .suppresses(identity: identity) ?? false
  }

  @MainActor
  package var effectiveInvalidationSummary: InvalidationSummary {
    effectiveFrameResolveInputs?.invalidationSummary ?? invalidationSummary
  }

  @MainActor
  package var effectiveProposal: ProposedSize {
    effectiveFrameResolveInputs?.proposal ?? .unspecified
  }

  /// Returns whether `identity` is directly invalidated in this context.
  public func isInvalidated(_ identity: Identity) -> Bool {
    invalidatedIdentities.contains(identity)
  }

  /// Returns whether the invalidation set intersects the subtree rooted at
  /// `identity`.
  public func invalidationAffectsSubtree(
    at identity: Identity? = nil
  ) -> Bool {
    let targetIdentity = identity ?? self.identity
    return invalidationSummary.intersectsSubtree(at: targetIdentity)
  }

  @MainActor
  package func recordResolvedComputation(
    count: Int = 1
  ) {
    resolveWorkTracker?.recordResolvedComputation(count: count)
  }

  @MainActor
  package func recordResolvedReuse(
    count: Int = 1
  ) {
    resolveWorkTracker?.recordResolvedReuse(count: count)
  }

  @MainActor
  package func trackingObservableAccess<T>(
    _ apply: () -> T
  ) -> T {
    EnvironmentValuesStorage.$current.withValue(environmentValues) {
      observationBridge?.track(identity: identity, apply) ?? apply()
    }
  }

  private static func contextualEnvironmentValues(
    _ environmentValues: EnvironmentValues,
    for identity: Identity
  ) -> EnvironmentValues {
    var resolvedEnvironmentValues = environmentValues
    resolvedEnvironmentValues.isFocused =
      environmentValues.focusedIdentity.map { focusedIdentity in
        identity == focusedIdentity
          || focusedIdentity.isDescendant(of: identity)
          || identity.isDescendant(of: focusedIdentity)
      } ?? false
    return resolvedEnvironmentValues
  }
}

extension ResolveContext {
  package init(
    identity: Identity = .init(components: [] as [IdentityComponent]),
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    transaction: TransactionSnapshot = .init(),
    invalidatedIdentities: Set<Identity> = [],
    invalidationSummary: InvalidationSummary? = nil,
    forceRootEvaluation: Bool = false,
    localActionRegistry: LocalActionRegistry? = nil,
    localFocusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
    localKeyHandlerRegistry: LocalKeyHandlerRegistry? = nil,
    localLifecycleRegistry: LocalLifecycleRegistry? = nil,
    localTaskRegistry: LocalTaskRegistry? = nil,
    applyEnvironmentValues: Bool
  ) {
    self.init(
      structuralIdentity: identity,
      structuralPath: nil,
      environment: environment,
      environmentValues: environmentValues,
      transaction: transaction,
      invalidatedIdentities: invalidatedIdentities,
      invalidationSummary: invalidationSummary,
      forceRootEvaluation: forceRootEvaluation,
      localActionRegistry: localActionRegistry,
      localFocusedValuesRegistry: localFocusedValuesRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: applyEnvironmentValues
    )
  }

  private init(
    structuralIdentity identity: Identity,
    structuralPath: StructuralPath?,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    transaction: TransactionSnapshot = .init(),
    invalidatedIdentities: Set<Identity> = [],
    invalidationSummary: InvalidationSummary? = nil,
    forceRootEvaluation: Bool = false,
    localActionRegistry: LocalActionRegistry? = nil,
    localFocusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
    localKeyHandlerRegistry: LocalKeyHandlerRegistry? = nil,
    localLifecycleRegistry: LocalLifecycleRegistry? = nil,
    localTaskRegistry: LocalTaskRegistry? = nil,
    applyEnvironmentValues: Bool
  ) {
    let resolvedEnvironmentValues = Self.contextualEnvironmentValues(
      environmentValues,
      for: identity
    )
    self.identity = identity
    self.structuralPath = structuralPath ?? StructuralPath(identity: identity)
    self.environmentValues = resolvedEnvironmentValues
    focusedValues = resolvedEnvironmentValues.focusedValues
    self.environment =
      applyEnvironmentValues
      ? resolvedEnvironmentValues.applying(to: environment)
      : environment
    self.transaction = transaction
    self.invalidatedIdentities = invalidatedIdentities
    self.invalidationSummary =
      invalidationSummary
      ?? .init(invalidatedIdentities: invalidatedIdentities)
    self.forceRootEvaluation = forceRootEvaluation
    resolveWorkTracker = .init()
    self.localActionRegistry = localActionRegistry
    self.localGestureRegistry = nil
    self.localGestureStateRegistry = nil
    self.localPointerHandlerRegistry = nil
    localTerminationRegistry = nil
    localDefaultFocusRegistry = nil
    self.localFocusBindingRegistry = nil
    self.localFocusedValuesRegistry = localFocusedValuesRegistry
    localScrollPositionRegistry = nil
    localPreferenceObservationRegistry = nil
    self.localKeyHandlerRegistry = localKeyHandlerRegistry
    self.localLifecycleRegistry = localLifecycleRegistry
    self.localTaskRegistry = localTaskRegistry
    commandRegistry = nil
    dropDestinationRegistry = nil
    invalidationProxy = nil
    observationBridge = nil
    viewGraph = nil
    imageAssetResolver = nil
    frameInputs = nil
    suppressesStructuralLifecycle = false
    requestDeadline = nil
  }
}

extension ResolveContext {
  public static func == (
    lhs: ResolveContext,
    rhs: ResolveContext
  ) -> Bool {
    lhs.identity == rhs.identity
      && lhs.structuralPath == rhs.structuralPath
      && lhs.environment == rhs.environment
      && lhs.environmentValues == rhs.environmentValues
      && lhs.transaction == rhs.transaction
      && lhs.invalidatedIdentities == rhs.invalidatedIdentities
      && lhs.forceRootEvaluation == rhs.forceRootEvaluation
      && lhs.localActionRegistry == rhs.localActionRegistry
      && lhs.localDefaultFocusRegistry == rhs.localDefaultFocusRegistry
      && lhs.localFocusBindingRegistry == rhs.localFocusBindingRegistry
      && lhs.localFocusedValuesRegistry == rhs.localFocusedValuesRegistry
      && lhs.localScrollPositionRegistry == rhs.localScrollPositionRegistry
      && lhs.localPreferenceObservationRegistry == rhs.localPreferenceObservationRegistry
      && lhs.localKeyHandlerRegistry == rhs.localKeyHandlerRegistry
      && lhs.localLifecycleRegistry == rhs.localLifecycleRegistry
      && lhs.localTaskRegistry == rhs.localTaskRegistry
      && lhs.commandRegistry == rhs.commandRegistry
      && lhs.dropDestinationRegistry == rhs.dropDestinationRegistry
      && lhs.observationBridge == rhs.observationBridge
      && lhs.suppressesStructuralLifecycle == rhs.suppressesStructuralLifecycle
  }
}
