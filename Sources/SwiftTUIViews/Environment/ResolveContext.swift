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
  /// True exactly while a non-transparent host (an `AnyView` payload, a
  /// captured-subview/scoped-content boundary) resolves foreign content through
  /// its own node. Such a host must never be entity-collapsed with the content
  /// it hosts: a host-escaping entity route (``ExactIdentityModifier``'s
  /// wholesale identity replacement) claimed at the host's `beginEvaluation`
  /// would route the entity back to the host from an interior position and wire
  /// the node into its own subtree. Deliberately *not* in
  /// ``PropagatedRegistries``: `child` / `replacingIdentity` derivations rebuild
  /// the context and drop it, so the signal is one-shot — visible to the hosted
  /// chain's own modifier resolution, reset for every structural descendant.
  /// Host-*descending* routes (``IDModifier``'s appended explicit id) are not
  /// suppressed; adopting the prior entity node as the host-content node is the
  /// entity-routing collapse that keeps `@State` alive across wrapper toggles.
  package var entityHosting: Bool = false
  package var localActionRegistry: LocalActionRegistry?
  package var localKeyHandlerRegistry: LocalKeyHandlerRegistry?
  package var localLifecycleRegistry: LocalLifecycleRegistry?
  package var localTaskRegistry: LocalTaskRegistry?

  /// Runtime registries and lowering seams propagated unchanged from a parent
  /// context to its `child` / `replacingIdentity` derivations. Grouping them in
  /// one value type lets those builders copy the whole set with a single
  /// memberwise assignment instead of restating each field, removing the
  /// parallel-list drift hazard. Members are surfaced as computed forwarding
  /// properties below so call sites continue to read `context.viewGraph`, etc.
  package var propagated: PropagatedRegistries

  package var resolveWorkTracker: ResolveWorkTracker? {
    get { propagated.resolveWorkTracker }
    set { propagated.resolveWorkTracker = newValue }
  }
  package var localGestureRegistry: LocalGestureRegistry? {
    get { propagated.localGestureRegistry }
    set { propagated.localGestureRegistry = newValue }
  }
  package var localGestureStateRegistry: LocalGestureStateRegistry? {
    get { propagated.localGestureStateRegistry }
    set { propagated.localGestureStateRegistry = newValue }
  }
  package var localPointerHandlerRegistry: LocalPointerHandlerRegistry? {
    get { propagated.localPointerHandlerRegistry }
    set { propagated.localPointerHandlerRegistry = newValue }
  }
  package var localTerminationRegistry: LocalTerminationRegistry? {
    get { propagated.localTerminationRegistry }
    set { propagated.localTerminationRegistry = newValue }
  }
  package var localDefaultFocusRegistry: LocalDefaultFocusRegistry? {
    get { propagated.localDefaultFocusRegistry }
    set { propagated.localDefaultFocusRegistry = newValue }
  }
  package var localFocusBindingRegistry: LocalFocusBindingRegistry? {
    get { propagated.localFocusBindingRegistry }
    set { propagated.localFocusBindingRegistry = newValue }
  }
  package var localFocusedValuesRegistry: LocalFocusedValuesRegistry? {
    get { propagated.localFocusedValuesRegistry }
    set { propagated.localFocusedValuesRegistry = newValue }
  }
  package var localScrollPositionRegistry: LocalScrollPositionRegistry? {
    get { propagated.localScrollPositionRegistry }
    set { propagated.localScrollPositionRegistry = newValue }
  }
  /// The registry that receives committed scroll geometry and published
  /// registrations — the pre-draft ("live") instance, surviving the frame
  /// head's draft-registry replacement the way `invalidationProxy` does.
  ///
  /// Imperative scroll *commands* (`ScrollViewReader` proxies, the scroll
  /// key handlers) must bind this instance: a resolve may run under a stored
  /// evaluator context whose draft registries belong to a long-dead frame,
  /// and a command bound to such a draft consults geometry that is never
  /// updated again. Registration *writes* stay on
  /// ``localScrollPositionRegistry`` so a discarded frame cannot mutate live
  /// state; the record/publish machinery re-homes them at commit.
  package var liveScrollPositionRegistry: LocalScrollPositionRegistry? {
    get { propagated.liveScrollPositionRegistry }
    set { propagated.liveScrollPositionRegistry = newValue }
  }
  /// The registry imperative scroll commands should consult.
  package var scrollCommandRegistry: LocalScrollPositionRegistry? {
    liveScrollPositionRegistry ?? localScrollPositionRegistry
  }
  /// The pre-draft ("live") focus-binding registry, surviving the frame
  /// head's draft-registry replacement like ``liveScrollPositionRegistry``.
  /// Default-focus ARRIVAL records must reach the instance focus-sync
  /// arbitrates — the frame-head draft is discarded, and arrivals are
  /// deliberately not node-recorded (a retained-subtree restore must never
  /// replay a consumed arrival). Registration writes stay on
  /// ``localFocusBindingRegistry``.
  package var liveFocusBindingRegistry: LocalFocusBindingRegistry? {
    get { propagated.liveFocusBindingRegistry }
    set { propagated.liveFocusBindingRegistry = newValue }
  }
  /// The registry default-focus arrivals should be recorded into.
  package var focusArrivalRegistry: LocalFocusBindingRegistry? {
    liveFocusBindingRegistry ?? localFocusBindingRegistry
  }
  package var localPreferenceObservationRegistry: LocalPreferenceObservationRegistry? {
    get { propagated.localPreferenceObservationRegistry }
    set { propagated.localPreferenceObservationRegistry = newValue }
  }
  package var commandRegistry: CommandRegistry? {
    get { propagated.commandRegistry }
    set { propagated.commandRegistry = newValue }
  }
  package var dropDestinationRegistry: DropDestinationRegistry? {
    get { propagated.dropDestinationRegistry }
    set { propagated.dropDestinationRegistry = newValue }
  }
  package var invalidationProxy: ResolveInvalidationProxy? {
    get { propagated.invalidationProxy }
    set { propagated.invalidationProxy = newValue }
  }
  package var observationBridge: ObservationBridge? {
    get { propagated.observationBridge }
    set { propagated.observationBridge = newValue }
  }
  package var viewGraph: ViewGraph? {
    get { propagated.viewGraph }
    set { propagated.viewGraph = newValue }
  }
  package var imageAssetResolver: ImageAssetResolver? {
    get { propagated.imageAssetResolver }
    set { propagated.imageAssetResolver = newValue }
  }
  package var frameInputs: FrameResolveInputBox? {
    get { propagated.frameInputs }
    set { propagated.frameInputs = newValue }
  }
  package var suppressesStructuralLifecycle: Bool {
    get { propagated.suppressesStructuralLifecycle }
    set { propagated.suppressesStructuralLifecycle = newValue }
  }
  package var withinChurnedSubtree: Bool {
    get { propagated.withinChurnedSubtree }
    set { propagated.withinChurnedSubtree = newValue }
  }
  package var requestDeadline: (@MainActor @Sendable (MonotonicInstant) -> Void)? {
    get { propagated.requestDeadline }
    set { propagated.requestDeadline = newValue }
  }
  package var presentationTriggerObserver: PresentationTriggerObservationLog? {
    get { propagated.presentationTriggerObserver }
    set { propagated.presentationTriggerObserver = newValue }
  }

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
    childContext.propagated = propagated
    childContext.focusedValues = focusedValues
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
    replacedContext.propagated = propagated
    replacedContext.focusedValues = focusedValues
    return replacedContext
  }

  package func suppressingStructuralLifecycle() -> Self {
    var context = self
    context.suppressesStructuralLifecycle = true
    return context
  }

  /// Marks this context as resolving content through a non-transparent host's
  /// own node. See ``entityHosting``.
  package func asEntityHost() -> Self {
    var context = self
    context.entityHosting = true
    return context
  }

  /// Returns this context resolving under `values` as its inherited authored
  /// environment while keeping the frame-level runtime focus/press state this
  /// context already carries.
  ///
  /// Portal-hosted presentation content resolves under the portal host's
  /// context rather than the presenting declaration's, so the presenter's
  /// authored environment (`.disabled`, `.environment` writes, styles) never
  /// reaches the overlay on its own; overlay entry composition applies the
  /// declaration-captured values through this builder. The focus/press side
  /// fields and the collected `focusedValues` belong to the resolving frame —
  /// adopting the capture's would replay the presenter's focus into the
  /// overlay.
  package func replacingEnvironmentValues(
    _ values: EnvironmentValues
  ) -> Self {
    var copy = self
    var replaced = values
    // Raw side-field access: infrastructure carry-over, not a runtime-focus
    // read attributable to the evaluating node.
    replaced._focusedIdentity = environmentValues._focusedIdentity
    replaced._pressedIdentity = environmentValues._pressedIdentity
    replaced._isFocused = environmentValues._isFocused
    replaced.focusedValues = focusedValues
    copy.environmentValues = replaced
    copy.environment = replaced.applying(to: environment)
    return copy
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
    copy.propagated.authoredFocusPressOverrides.formUnion(
      Self.focusPressOverrides(writtenBy: keyPath)
    )
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
    // A transform rooted above the two keys (e.g. `\.self`) can write them
    // without naming them, so value changes count as authored writes too.
    // Raw side-field access: infrastructure comparisons must not record a
    // runtime-focus read on the evaluating node.
    var overrides = Self.focusPressOverrides(writtenBy: keyPath)
    if copy.environmentValues._focusedIdentity != environmentValues._focusedIdentity {
      overrides.insert(.focusedIdentity)
    }
    if copy.environmentValues._pressedIdentity != environmentValues._pressedIdentity {
      overrides.insert(.pressedIdentity)
    }
    copy.propagated.authoredFocusPressOverrides.formUnion(overrides)
    return copy
  }

  private static func focusPressOverrides<Value>(
    writtenBy keyPath: WritableKeyPath<EnvironmentValues, Value>
  ) -> AuthoredFocusPressOverrides {
    let erased: AnyKeyPath = keyPath
    if erased == \EnvironmentValues.focusedIdentity {
      return .focusedIdentity
    }
    if erased == \EnvironmentValues.pressedIdentity {
      return .pressedIdentity
    }
    return []
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
    // Focus/press refresh keeps re-run evaluator closures — whose captured
    // context predates the current frame — in sync with the frame-level focus
    // and press state, which is what lets finite suppression scopes replace
    // root-forced evaluation. An authored `.environment` write must still win
    // below its modifier, so keys the authoring surface owns in this scope are
    // exempt: for them the captured value IS the current value.
    var environmentValues = refreshed.environmentValues
    let authoredOverrides = propagated.authoredFocusPressOverrides
    if !authoredOverrides.contains(.focusedIdentity) {
      environmentValues._focusedIdentity = inputs.environmentValues._focusedIdentity
    }
    if !authoredOverrides.contains(.pressedIdentity) {
      environmentValues._pressedIdentity = inputs.environmentValues._pressedIdentity
    }
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
  /// active animation cones, with a conservative full-suppression fallback for
  /// identity-agnostic animation work. Focus/press members honor
  /// focus-presentation-inert slot declarations recorded on the member's own
  /// graph node (a `TabView`'s content slot), so a near-root focused container
  /// does not put its whole content subtree into the recompute cone.
  @MainActor
  package func effectiveSuppressesRetainedReuse(
    at identity: Identity
  ) -> Bool {
    guard
      let scope = effectiveFrameResolveInputs?.retainedReuseSuppressionScope
    else {
      return false
    }
    return scope.suppresses(identity: identity) { member, identity in
      viewGraph?.focusPresentationInertSlotExempts(
        member: member,
        identity: identity
      ) ?? false
    }
  }

  /// Like ``effectiveSuppressesRetainedReuse(at:)`` but for the *memoized*
  /// (value-verified) reuse layer: descendant-only matches below a
  /// focus-presentation **value-verified** slot the matched member itself
  /// declared are additionally exempt. A value-verified slot's handed-down
  /// value may flip with the member's focus presentation, so value-blind
  /// Layer-A reuse must stay denied there — but the memo layer proves the
  /// value unchanged before reusing, which covers exactly that hazard.
  /// Ancestor-of-member and exact-member matches are never exempted: a
  /// wholesale focus reader (`isFocused` bake / `@Environment` wrapper)
  /// inside a slot is a scope member in its own right, and its ancestors must
  /// keep recomputing.
  @MainActor
  package func effectiveSuppressesValueVerifiedReuse(
    at identity: Identity
  ) -> Bool {
    guard
      let scope = effectiveFrameResolveInputs?.retainedReuseSuppressionScope
    else {
      return false
    }
    return scope.suppresses(identity: identity) { member, identity in
      guard let viewGraph else {
        return false
      }
      return viewGraph.focusPresentationInertSlotExempts(
        member: member,
        identity: identity
      )
        || viewGraph.focusPresentationValueVerifiedSlotExempts(
          member: member,
          identity: identity
        )
    }
  }

  /// Whether this frame's forced evaluation is fully named by a FINITE
  /// retained-reuse suppression scope. Such frames (pure focus moves,
  /// non-property animation ticks, pending stranded-batch drains) carry no
  /// ordinary invalidation, but every identity that must recompute is in the
  /// scope — including the named-EMPTY drain case, where that set is empty —
  /// so a node that already passed the suppression check may take retained
  /// reuse even though the frame's invalidation set is empty.
  @MainActor
  package var effectiveFiniteSuppressionScopeNamesForcedEvaluation: Bool {
    guard
      let scope = effectiveFrameResolveInputs?.retainedReuseSuppressionScope
    else {
      return false
    }
    return !scope.suppressesAll && (!scope.isEmpty || scope.namesForcedEvaluation)
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
    // The per-node focus-cone bake. Raw side-field access: this runs for
    // every child context, so reading through the recording getter would
    // flag every node as a runtime-focus reader and defeat the chrome-only
    // member narrowing.
    var resolvedEnvironmentValues = environmentValues
    resolvedEnvironmentValues._isFocused =
      environmentValues._focusedIdentity.map { focusedIdentity in
        identity == focusedIdentity
          || focusedIdentity.isDescendant(of: identity)
          || identity.isDescendant(of: focusedIdentity)
      } ?? false
    return resolvedEnvironmentValues
  }
}

extension ResolveContext {
  /// The runtime registries and lowering seams that `child` / `replacingIdentity`
  /// carry forward unchanged from a parent context. Holding them in one value
  /// type lets those builders propagate the whole set with a single memberwise
  /// copy; `ResolveContext` exposes each member as a forwarding property so call
  /// sites continue to use the flat names.
  package struct PropagatedRegistries: Sendable {
    package var resolveWorkTracker: ResolveWorkTracker?
    package var localGestureRegistry: LocalGestureRegistry?
    package var localGestureStateRegistry: LocalGestureStateRegistry?
    package var localPointerHandlerRegistry: LocalPointerHandlerRegistry?
    package var localTerminationRegistry: LocalTerminationRegistry?
    package var localDefaultFocusRegistry: LocalDefaultFocusRegistry?
    package var localFocusBindingRegistry: LocalFocusBindingRegistry?
    package var localFocusedValuesRegistry: LocalFocusedValuesRegistry?
    package var localScrollPositionRegistry: LocalScrollPositionRegistry?
    /// See ``ResolveContext/liveScrollPositionRegistry``. Deliberately NOT a
    /// member of ``RuntimeRegistrationSet``: `replacingRuntimeRegistrations`
    /// must leave it untouched so it survives frame-draft replacement.
    package var liveScrollPositionRegistry: LocalScrollPositionRegistry?
    /// See ``ResolveContext/liveFocusBindingRegistry``. Same draft-survival
    /// contract as `liveScrollPositionRegistry`.
    package var liveFocusBindingRegistry: LocalFocusBindingRegistry?
    package var localPreferenceObservationRegistry: LocalPreferenceObservationRegistry?
    package var commandRegistry: CommandRegistry?
    package var dropDestinationRegistry: DropDestinationRegistry?
    package var invalidationProxy: ResolveInvalidationProxy?
    package var observationBridge: ObservationBridge?
    package var viewGraph: ViewGraph?
    package var imageAssetResolver: ImageAssetResolver?
    package var frameInputs: FrameResolveInputBox?
    package var suppressesStructuralLifecycle: Bool
    /// True while resolving inside a subtree whose owning `.id(_:)` re-rooted its
    /// resolved identity this frame (an identity churn). Set by
    /// ``ExactIdentityModifier`` at the churn point and inherited by every
    /// derived (`child` / `replacingIdentity`) context, so it rides the resolve
    /// tree downward regardless of how many identity/structural re-rooting layers
    /// (`.id`, `AnyView`, captured-subview scopes) sit between the churned owner
    /// and a descendant. Reuse (retained + memo) is suppressed for such
    /// descendants so they re-resolve fresh — the committed reuse-containment
    /// checks key on identity/structural ancestry, which a re-rooted descendant
    /// escapes.
    package var withinChurnedSubtree: Bool
    /// Focus/press environment keys written by an authored `.environment` /
    /// `.transformEnvironment` modifier in this context's scope. Set by
    /// `settingEnvironment` / `transformingEnvironment` at the write point and
    /// inherited by every derived context (like `withinChurnedSubtree`), so
    /// captured evaluator contexts below the modifier keep the marker across
    /// frames. `applyingCurrentFrameResolveInputs` refreshes frame-level
    /// focus/press into captured contexts; keys marked here are exempt because
    /// the authored value must keep winning below its modifier.
    package var authoredFocusPressOverrides: AuthoredFocusPressOverrides
    /// Forwards deadline requests to the frame scheduler.
    /// Stored as a closure to avoid Sendable constraints on `FrameScheduling`.
    package var requestDeadline: (@MainActor @Sendable (MonotonicInstant) -> Void)?
    /// Frame-scoped sink for presentation declaration-emitter observations
    /// (the portal force-queue narrowing's escalation signal). Points at the
    /// stable live-state log, so evaluator closures captured on earlier
    /// frames keep reporting into the current frame's log.
    package var presentationTriggerObserver: PresentationTriggerObservationLog?

    package init(
      resolveWorkTracker: ResolveWorkTracker? = nil,
      localGestureRegistry: LocalGestureRegistry? = nil,
      localGestureStateRegistry: LocalGestureStateRegistry? = nil,
      localPointerHandlerRegistry: LocalPointerHandlerRegistry? = nil,
      localTerminationRegistry: LocalTerminationRegistry? = nil,
      localDefaultFocusRegistry: LocalDefaultFocusRegistry? = nil,
      localFocusBindingRegistry: LocalFocusBindingRegistry? = nil,
      localFocusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
      localScrollPositionRegistry: LocalScrollPositionRegistry? = nil,
      localPreferenceObservationRegistry: LocalPreferenceObservationRegistry? = nil,
      commandRegistry: CommandRegistry? = nil,
      dropDestinationRegistry: DropDestinationRegistry? = nil,
      invalidationProxy: ResolveInvalidationProxy? = nil,
      observationBridge: ObservationBridge? = nil,
      viewGraph: ViewGraph? = nil,
      imageAssetResolver: ImageAssetResolver? = nil,
      frameInputs: FrameResolveInputBox? = nil,
      suppressesStructuralLifecycle: Bool = false,
      withinChurnedSubtree: Bool = false,
      authoredFocusPressOverrides: AuthoredFocusPressOverrides = [],
      requestDeadline: (@MainActor @Sendable (MonotonicInstant) -> Void)? = nil
    ) {
      self.resolveWorkTracker = resolveWorkTracker
      self.localGestureRegistry = localGestureRegistry
      self.localGestureStateRegistry = localGestureStateRegistry
      self.localPointerHandlerRegistry = localPointerHandlerRegistry
      self.localTerminationRegistry = localTerminationRegistry
      self.localDefaultFocusRegistry = localDefaultFocusRegistry
      self.localFocusBindingRegistry = localFocusBindingRegistry
      self.localFocusedValuesRegistry = localFocusedValuesRegistry
      self.localScrollPositionRegistry = localScrollPositionRegistry
      self.localPreferenceObservationRegistry = localPreferenceObservationRegistry
      self.commandRegistry = commandRegistry
      self.dropDestinationRegistry = dropDestinationRegistry
      self.invalidationProxy = invalidationProxy
      self.observationBridge = observationBridge
      self.viewGraph = viewGraph
      self.imageAssetResolver = imageAssetResolver
      self.frameInputs = frameInputs
      self.suppressesStructuralLifecycle = suppressesStructuralLifecycle
      self.withinChurnedSubtree = withinChurnedSubtree
      self.authoredFocusPressOverrides = authoredFocusPressOverrides
      self.requestDeadline = requestDeadline
    }
  }

  /// Environment keys whose in-scope values are owned by an authored
  /// `.environment` / `.transformEnvironment` write. See
  /// ``PropagatedRegistries/authoredFocusPressOverrides``.
  package struct AuthoredFocusPressOverrides: OptionSet, Equatable, Sendable {
    package let rawValue: UInt8

    package init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    package static let focusedIdentity = Self(rawValue: 1 << 0)
    package static let pressedIdentity = Self(rawValue: 1 << 1)
  }

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
    self.localActionRegistry = localActionRegistry
    self.localKeyHandlerRegistry = localKeyHandlerRegistry
    self.localLifecycleRegistry = localLifecycleRegistry
    self.localTaskRegistry = localTaskRegistry
    self.propagated = PropagatedRegistries(
      resolveWorkTracker: .init(),
      localFocusedValuesRegistry: localFocusedValuesRegistry
    )
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
      && lhs.liveScrollPositionRegistry == rhs.liveScrollPositionRegistry
      && lhs.liveFocusBindingRegistry == rhs.liveFocusBindingRegistry
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
