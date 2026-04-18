public import Core
import Observation
import Synchronization

/// Declares a typed environment value.
public protocol EnvironmentKey {
  associatedtype Value: Sendable
  static var defaultValue: Value { get }
}

private protocol EnvironmentValueBox: Sendable {
  var snapshotValue: String { get }
  var valueTypeDescription: String { get }

  func value<Value>(as type: Value.Type) -> Value?
}

private struct TypedEnvironmentValueBox<Value: Sendable>: EnvironmentValueBox {
  let base: Value

  var snapshotValue: String {
    String(reflecting: base)
  }

  var valueTypeDescription: String {
    String(reflecting: Value.self)
  }

  func value<T>(as type: T.Type) -> T? {
    base as? T
  }
}

/// A semantic action that attempts to open a link destination.
public struct OpenLinkAction: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  package let isPlaceholder: Bool
  private let handler: @MainActor @Sendable (LinkDestination) -> Bool

  public init(
    _ handler: @escaping @MainActor @Sendable (LinkDestination) -> Bool
  ) {
    snapshotLabel = "OpenLinkAction.custom"
    isPlaceholder = false
    self.handler = handler
  }

  @discardableResult
  @MainActor
  public func callAsFunction(
    _ destination: LinkDestination
  ) -> Bool {
    handler(destination)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  package init(
    snapshotLabel: String,
    isPlaceholder: Bool,
    handler: @escaping @MainActor @Sendable (LinkDestination) -> Bool
  ) {
    self.snapshotLabel = snapshotLabel
    self.isPlaceholder = isPlaceholder
    self.handler = handler
  }

  package static let placeholder = Self(
    snapshotLabel: "OpenLinkAction.default",
    isPlaceholder: true,
    handler: { _ in false }
  )
}

private enum OpenLinkActionKey: EnvironmentKey {
  static let defaultValue = OpenLinkAction.placeholder
}

private enum StackAxisKey: EnvironmentKey {
  static let defaultValue: Core.Axis? = nil
}

/// The inherited environment available while resolving a view subtree.
public struct EnvironmentValues: Equatable, Sendable {
  private var storage: [ObjectIdentifier: any EnvironmentValueBox]
  private var snapshotValues: [String: String]
  package var _focusedIdentity: Identity?
  package var _pressedIdentity: Identity?

  /// Creates an empty environment container.
  public init() {
    storage = [:]
    snapshotValues = [:]
    _focusedIdentity = nil
    _pressedIdentity = nil
  }

  public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
    get {
      let identifier = ObjectIdentifier(key)
      MainActor.assumeIsolated {
        ViewNodeContext.current?.recordEnvironmentRead(identifier)
      }
      guard let boxed = storage[identifier] else {
        let defaultValue = K.defaultValue
        recordObservableEnvironmentRead(defaultValue)
        return defaultValue
      }
      guard let typed: K.Value = boxed.value(as: K.Value.self) else {
        preconditionFailure(
          "Environment type mismatch for \(String(reflecting: key)). Expected \(K.Value.self), found \(boxed.valueTypeDescription)."
        )
      }
      recordObservableEnvironmentRead(typed)
      return typed
    }
    set {
      let identifier = ObjectIdentifier(key)
      let box = TypedEnvironmentValueBox(base: newValue)
      storage[identifier] = box
      snapshotValues[String(reflecting: key)] = box.snapshotValue
    }
  }

  fileprivate func applying(
    to snapshot: EnvironmentSnapshot,
    reuseStyle: Bool = false
  ) -> EnvironmentSnapshot {
    var mergedValues = snapshot.values
    if !snapshotValues.isEmpty {
      mergedValues.merge(snapshotValues) { _, new in new }
    }
    let style: StyleEnvironmentSnapshot
    if reuseStyle {
      // Non-style keypath changed: reuse heavy fields, update lightweight ones.
      style = StyleEnvironmentSnapshot(
        heavyFields: snapshot.style.heavyFields,
        foregroundStyle: foregroundStyle,
        tintStyle: tintStyle,
        isEnabled: isEnabled
      )
    } else {
      style = StyleEnvironmentSnapshot(
        appearance: terminalAppearance,
        theme: theme,
        foregroundStyle: foregroundStyle,
        tintStyle: tintStyle,
        isEnabled: isEnabled
      )
    }
    return EnvironmentSnapshot(
      debugSignature: snapshot.debugSignature,
      values: mergedValues,
      style: style
    )
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.snapshotValues == rhs.snapshotValues
  }

  private func recordObservableEnvironmentRead<Value>(
    _ value: Value
  ) {
    guard let observable = value as? any Observable & AnyObject else {
      return
    }
    let observableID = ObjectIdentifier(observable)
    MainActor.assumeIsolated {
      ViewNodeContext.current?.recordObservableRead(observableID)
    }
  }
}

extension EnvironmentValues {
  package var stackAxis: Core.Axis? {
    get { self[StackAxisKey.self] }
    set { self[StackAxisKey.self] = newValue }
  }
}

/// Public configuration for resolving a view subtree.
///
/// `ResolveContext` exposes the authored identity, environment, transaction,
/// and invalidation scope that affect a resolve pass. Runtime registries and
/// other lowering seams remain package-only.
public struct ResolveContext: Equatable, Sendable {
  public var identity: Identity
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
  package var resolveWorkTracker: ResolveWorkTracker?
  package var localActionRegistry: LocalActionRegistry?
  package var localGestureRegistry: LocalGestureRegistry?
  package var localGestureStateRegistry: LocalGestureStateRegistry?
  package var localPointerHandlerRegistry: LocalPointerHandlerRegistry?
  package var localFocusBindingRegistry: LocalFocusBindingRegistry?
  package var localFocusedValuesRegistry: LocalFocusedValuesRegistry?
  package var localPreferenceObservationRegistry: LocalPreferenceObservationRegistry?
  package var localKeyHandlerRegistry: LocalKeyHandlerRegistry?
  package var localLifecycleRegistry: LocalLifecycleRegistry?
  package var localTaskRegistry: LocalTaskRegistry?
  package var commandRegistry: CommandRegistry?
  package var invalidationProxy: ResolveInvalidationProxy?
  package var observationBridge: ObservationBridge?
  package var viewGraph: ViewGraph?
  package var imageAssetResolver: ImageAssetResolver?
  package var frameState: FrameResolveState?

  @MainActor
  package var runtimeRegistrations: RuntimeRegistrationSet {
    RuntimeRegistrationSet(
      actionRegistry: localActionRegistry,
      keyHandlerRegistry: localKeyHandlerRegistry,
      pointerHandlerRegistry: localPointerHandlerRegistry,
      gestureRegistry: localGestureRegistry,
      gestureStateRegistry: localGestureStateRegistry,
      focusBindingRegistry: localFocusBindingRegistry,
      focusedValuesRegistry: localFocusedValuesRegistry,
      lifecycleRegistry: localLifecycleRegistry,
      taskRegistry: localTaskRegistry,
      preferenceObservationRegistry: localPreferenceObservationRegistry,
      commandRegistry: commandRegistry
    )
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
      identity: identity.child(component),
      environment: environment,
      environmentValues: environmentValues,
      transaction: transaction,
      invalidatedIdentities: invalidatedIdentities,
      invalidationSummary: invalidationSummary,
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: false
    )
    childContext.localGestureRegistry = localGestureRegistry
    childContext.localGestureStateRegistry = localGestureStateRegistry
    childContext.localPointerHandlerRegistry = localPointerHandlerRegistry
    childContext.localFocusBindingRegistry = localFocusBindingRegistry
    childContext.localFocusedValuesRegistry = localFocusedValuesRegistry
    childContext.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    childContext.commandRegistry = commandRegistry
    childContext.invalidationProxy = invalidationProxy
    childContext.observationBridge = observationBridge
    childContext.viewGraph = viewGraph
    childContext.resolveWorkTracker = resolveWorkTracker
    childContext.focusedValues = focusedValues
    childContext.imageAssetResolver = imageAssetResolver
    childContext.frameState = frameState
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
      identity: identity,
      environment: environment,
      environmentValues: environmentValues,
      transaction: transaction,
      invalidatedIdentities: invalidatedIdentities,
      invalidationSummary: invalidationSummary,
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: false
    )
    replacedContext.localGestureRegistry = localGestureRegistry
    replacedContext.localGestureStateRegistry = localGestureStateRegistry
    replacedContext.localPointerHandlerRegistry = localPointerHandlerRegistry
    replacedContext.localFocusBindingRegistry = localFocusBindingRegistry
    replacedContext.localFocusedValuesRegistry = localFocusedValuesRegistry
    replacedContext.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    replacedContext.commandRegistry = commandRegistry
    replacedContext.invalidationProxy = invalidationProxy
    replacedContext.observationBridge = observationBridge
    replacedContext.viewGraph = viewGraph
    replacedContext.resolveWorkTracker = resolveWorkTracker
    replacedContext.focusedValues = focusedValues
    replacedContext.imageAssetResolver = imageAssetResolver
    replacedContext.frameState = frameState
    return replacedContext
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

  /// Returns the effective per-frame invalidation set, preferring the shared
  /// ``FrameResolveState`` when available (updated each frame by the renderer).
  @MainActor
  package var effectiveInvalidatedIdentities: Set<Identity> {
    frameState?.invalidatedIdentities ?? invalidatedIdentities
  }

  @MainActor
  package var effectiveInvalidationSummary: InvalidationSummary {
    frameState?.invalidationSummary ?? invalidationSummary
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
    observationBridge?.track(identity: identity, apply) ?? apply()
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
    resolveWorkTracker = .init()
    self.localActionRegistry = localActionRegistry
    self.localGestureRegistry = nil
    self.localGestureStateRegistry = nil
    self.localPointerHandlerRegistry = nil
    self.localFocusBindingRegistry = nil
    self.localFocusedValuesRegistry = localFocusedValuesRegistry
    localPreferenceObservationRegistry = nil
    self.localKeyHandlerRegistry = localKeyHandlerRegistry
    self.localLifecycleRegistry = localLifecycleRegistry
    self.localTaskRegistry = localTaskRegistry
    commandRegistry = nil
    invalidationProxy = nil
    observationBridge = nil
    viewGraph = nil
    imageAssetResolver = nil
  }
}

extension EnvironmentValues {
  public var openLinkAction: OpenLinkAction {
    get { self[OpenLinkActionKey.self] }
    set { self[OpenLinkActionKey.self] = newValue }
  }
}

extension ResolveContext {
  public static func == (
    lhs: ResolveContext,
    rhs: ResolveContext
  ) -> Bool {
    lhs.identity == rhs.identity
      && lhs.environment == rhs.environment
      && lhs.environmentValues == rhs.environmentValues
      && lhs.transaction == rhs.transaction
      && lhs.invalidatedIdentities == rhs.invalidatedIdentities
      && lhs.localActionRegistry == rhs.localActionRegistry
      && lhs.localFocusBindingRegistry == rhs.localFocusBindingRegistry
      && lhs.localFocusedValuesRegistry == rhs.localFocusedValuesRegistry
      && lhs.localPreferenceObservationRegistry == rhs.localPreferenceObservationRegistry
      && lhs.localKeyHandlerRegistry == rhs.localKeyHandlerRegistry
      && lhs.localLifecycleRegistry == rhs.localLifecycleRegistry
      && lhs.localTaskRegistry == rhs.localTaskRegistry
      && lhs.commandRegistry == rhs.commandRegistry
      && lhs.observationBridge == rhs.observationBridge
  }
}

package final class ResolveWorkTracker: Sendable {
  private let workMetrics: Mutex<ResolveWorkMetrics>

  package init(
    workMetrics: ResolveWorkMetrics = .init()
  ) {
    self.workMetrics = Mutex(workMetrics)
  }

  package func recordResolvedComputation(
    count: Int = 1
  ) {
    workMetrics.withLock { workMetrics in
      workMetrics.resolvedNodesComputed += max(0, count)
    }
  }

  package func recordResolvedReuse(
    count: Int = 1
  ) {
    workMetrics.withLock { workMetrics in
      workMetrics.resolvedNodesReused += max(0, count)
    }
  }

  package var snapshot: ResolveWorkMetrics {
    workMetrics.withLock { $0 }
  }
}

@MainActor
package final class ResolveInvalidationProxy {
  package weak var invalidator: (any Invalidating)?

  package init(
    invalidator: (any Invalidating)? = nil
  ) {
    self.invalidator = invalidator
  }
}

/// Reads an environment value and maps it into authored content.
public struct EnvironmentReader<Value, Content: View>: View, ResolvableView {
  private let keyPath: KeyPath<EnvironmentValues, Value>
  private let content: (Value) -> Content
  private let authoringContext: AuthoringContext?

  public init(
    _ keyPath: KeyPath<EnvironmentValues, Value>,
    @ViewBuilder content: @escaping (Value) -> Content
  ) {
    self.keyPath = keyPath
    self.content = content
    authoringContext = currentAuthoringContext()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let view = withAuthoringContext(authoringContext) {
      context.trackingObservableAccess {
        content(context.environmentValues[keyPath: keyPath])
      }
    }
    return view.resolveElements(in: context)
  }
}
