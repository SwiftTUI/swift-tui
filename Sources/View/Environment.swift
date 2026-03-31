public import Core

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
      guard let boxed = storage[identifier] else {
        return K.defaultValue
      }
      guard let typed: K.Value = boxed.value(as: K.Value.self) else {
        preconditionFailure(
          "Environment type mismatch for \(String(reflecting: key)). Expected \(K.Value.self), found \(boxed.valueTypeDescription)."
        )
      }
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
    to snapshot: EnvironmentSnapshot
  ) -> EnvironmentSnapshot {
    var mergedValues = snapshot.values
    if !snapshotValues.isEmpty {
      mergedValues.merge(snapshotValues) { _, new in new }
    }
    return EnvironmentSnapshot(
      debugSignature: snapshot.debugSignature,
      values: mergedValues,
      style: StyleEnvironmentSnapshot(
        appearance: terminalAppearance,
        themeOverride: themeOverride,
        foregroundStyle: foregroundStyle,
        tintStyle: tintStyle,
        preferredColorScheme: preferredColorScheme,
        chromePreset: chromePreset,
        isEnabled: isEnabled
      )
    )
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.snapshotValues == rhs.snapshotValues
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
  public var invalidatedIdentities: Set<Identity>
  package var resolveReuseSession: ResolveReuseSession?
  package var localActionRegistry: LocalActionRegistry?
  package var localPointerHandlerRegistry: LocalPointerHandlerRegistry?
  package var localFocusBindingRegistry: LocalFocusBindingRegistry?
  package var localFocusedValuesRegistry: LocalFocusedValuesRegistry?
  package var localPreferenceObservationRegistry: LocalPreferenceObservationRegistry?
  package var localKeyHandlerRegistry: LocalKeyHandlerRegistry?
  package var localLifecycleRegistry: LocalLifecycleRegistry?
  package var localTaskRegistry: LocalTaskRegistry?
  package var dynamicStateStore: DynamicStateStore?
  package var observationBridge: ObservationBridge?
  package var imageAssetResolver: ImageAssetResolver?

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
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: false
    )
    childContext.localPointerHandlerRegistry = localPointerHandlerRegistry
    childContext.localFocusBindingRegistry = localFocusBindingRegistry
    childContext.localFocusedValuesRegistry = localFocusedValuesRegistry
    childContext.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    childContext.dynamicStateStore = dynamicStateStore
    childContext.observationBridge = observationBridge
    childContext.resolveReuseSession = resolveReuseSession
    childContext.focusedValues = focusedValues
    childContext.imageAssetResolver = imageAssetResolver
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
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: false
    )
    replacedContext.localPointerHandlerRegistry = localPointerHandlerRegistry
    replacedContext.localFocusBindingRegistry = localFocusBindingRegistry
    replacedContext.localFocusedValuesRegistry = localFocusedValuesRegistry
    replacedContext.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    replacedContext.dynamicStateStore = dynamicStateStore
    replacedContext.observationBridge = observationBridge
    replacedContext.resolveReuseSession = resolveReuseSession
    replacedContext.focusedValues = focusedValues
    replacedContext.imageAssetResolver = imageAssetResolver
    return replacedContext
  }

  package func settingEnvironment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    to value: Value
  ) -> Self {
    var copy = self
    copy.environmentValues[keyPath: keyPath] = value
    copy.environment = copy.environmentValues.applying(to: copy.environment)
    return copy
  }

  package func transformingEnvironment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    transform: (inout Value) -> Void
  ) -> Self {
    var copy = self
    transform(&copy.environmentValues[keyPath: keyPath])
    copy.environment = copy.environmentValues.applying(to: copy.environment)
    return copy
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
    return invalidatedIdentities.contains { invalidatedIdentity in
      invalidatedIdentity.isDescendant(of: targetIdentity)
        || targetIdentity.isDescendant(of: invalidatedIdentity)
    }
  }

  @MainActor
  package func reusedResolvedSubtreeIfAvailable() -> ResolvedNode? {
    resolveReuseSession?.reusedResolvedSubtree(for: self)
  }

  @MainActor
  package func recordResolvedComputation(
    count: Int = 1
  ) {
    resolveReuseSession?.workMetrics.resolvedNodesComputed += max(0, count)
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
    resolveReuseSession = nil
    self.localActionRegistry = localActionRegistry
    self.localPointerHandlerRegistry = nil
    self.localFocusBindingRegistry = nil
    self.localFocusedValuesRegistry = localFocusedValuesRegistry
    localPreferenceObservationRegistry = nil
    self.localKeyHandlerRegistry = localKeyHandlerRegistry
    self.localLifecycleRegistry = localLifecycleRegistry
    self.localTaskRegistry = localTaskRegistry
    dynamicStateStore = nil
    observationBridge = nil
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
      && lhs.dynamicStateStore == rhs.dynamicStateStore
      && lhs.observationBridge == rhs.observationBridge
  }
}

// SAFETY: Created per-frame and exclusively accessed on @MainActor during the resolve phase.
// Contains RetainedResolveFrame (non-Sendable due to closure storage) and mutable workMetrics.
// Never shared across isolation domains.
@MainActor
package final class ResolveReuseSession: @unchecked Sendable {
  package let invalidatedIdentities: Set<Identity>
  private let previousFrame: RetainedResolveFrame?
  package var workMetrics = ResolveWorkMetrics()

  package init(
    previousFrame: RetainedResolveFrame?,
    invalidatedIdentities: Set<Identity>
  ) {
    self.previousFrame = previousFrame
    self.invalidatedIdentities = invalidatedIdentities
  }

  package func reusedResolvedSubtree(
    for context: ResolveContext
  ) -> ResolvedNode? {
    guard let previousFrame,
      let candidate = previousFrame.resolvedTreeIndex.resolvedNode(
        for: context.identity
      ),
      canReuse(candidate, for: context)
    else {
      return nil
    }

    workMetrics.resolvedNodesReused +=
      previousFrame.resolvedTreeIndex.subtreeNodeCount(
        for: context.identity
      ) ?? candidate.subtreeNodeCount
    replayRegistrations(for: context.identity, into: context)
    return candidate
  }

  private func canReuse(
    _ node: ResolvedNode,
    for context: ResolveContext
  ) -> Bool {
    guard !invalidatedIdentities.isEmpty else {
      return false
    }
    guard node.supportsRetainedReuse else {
      return false
    }
    guard !hasInvalidatedSelfOrAncestor(context.identity) else {
      return false
    }
    guard !invalidatedIdentities.contains(context.identity) else {
      return false
    }
    guard !subtreeContainsInvalidatedIdentity(context.identity) else {
      return false
    }
    return node.environmentSnapshot == context.environment
      && node.transactionSnapshot == context.transaction
  }

  private func hasInvalidatedSelfOrAncestor(
    _ identity: Identity
  ) -> Bool {
    if let previousFrame {
      return invalidatedIdentities.contains { invalidatedIdentity in
        previousFrame.resolvedTreeIndex.contains(
          identity,
          inSubtreeOf: invalidatedIdentity
        )
          || identity.isDescendant(of: invalidatedIdentity)
      }
    }

    return invalidatedIdentities.contains { invalidatedIdentity in
      identity.isDescendant(of: invalidatedIdentity)
    }
  }

  private func subtreeContainsInvalidatedIdentity(
    _ subtreeIdentity: Identity
  ) -> Bool {
    if let previousFrame {
      return invalidatedIdentities.contains { invalidatedIdentity in
        previousFrame.resolvedTreeIndex.contains(
          invalidatedIdentity,
          inSubtreeOf: subtreeIdentity
        ) || invalidatedIdentity.isDescendant(of: subtreeIdentity)
      }
    }

    return invalidatedIdentities.contains { invalidatedIdentity in
      invalidatedIdentity.isDescendant(of: subtreeIdentity)
    }
  }

  private func replayRegistrations(
    for subtreeIdentity: Identity,
    into context: ResolveContext
  ) {
    guard let previousFrame else {
      return
    }

    guard
      let subtreeIdentities = previousFrame.resolvedTreeIndex.subtreeIdentities(
        for: subtreeIdentity
      )
    else {
      return
    }

    for identity in subtreeIdentities {
      if let actionRegistry = context.localActionRegistry,
        let registration = previousFrame.actionHandlers[identity]
      {
        actionRegistry.register(
          identity: identity,
          handler: registration.handler,
          followUpInvalidationIdentity: registration.followUpInvalidationIdentity
        )
      }
      if let keyHandlerRegistry = context.localKeyHandlerRegistry,
        let handler = previousFrame.keyHandlers[identity]
      {
        keyHandlerRegistry.register(identity: identity, handler: handler)
      }
      if let taskRegistry = context.localTaskRegistry,
        let registration = previousFrame.taskRegistrations[identity]
      {
        taskRegistry.register(identity: identity, registration: registration)
      }
    }

    if let pointerHandlerRegistry = context.localPointerHandlerRegistry {
      for (routeID, handler) in previousFrame.pointerHandlers
      where previousFrame.resolvedTreeIndex.contains(
        routeID.identity,
        inSubtreeOf: subtreeIdentity
      ) {
        pointerHandlerRegistry.register(routeID: routeID, handler: handler)
      }
    }

    if let focusBindingRegistry = context.localFocusBindingRegistry {
      focusBindingRegistry.restore(
        previousFrame.focusBindings.filter { snapshot in
          previousFrame.resolvedTreeIndex.contains(
            snapshot.identity,
            inSubtreeOf: subtreeIdentity
          )
        }
      )
    }
    if let focusedValuesRegistry = context.localFocusedValuesRegistry {
      focusedValuesRegistry.restore(
        previousFrame.focusedValues.filter { snapshot in
          previousFrame.resolvedTreeIndex.contains(
            snapshot.identity,
            inSubtreeOf: subtreeIdentity
          )
        }
      )
    }
    if let preferenceObservationRegistry = context.localPreferenceObservationRegistry {
      preferenceObservationRegistry.restore(
        previousFrame.preferenceObservations.filter { snapshot in
          previousFrame.resolvedTreeIndex.contains(
            snapshot.identity,
            inSubtreeOf: subtreeIdentity
          )
        }
      )
    }

    guard let lifecycleRegistry = context.localLifecycleRegistry else {
      return
    }

    var appearIDs: [String] = []
    var disappearIDs: [String] = []
    for identity in subtreeIdentities {
      guard
        let lifecycleMetadata = previousFrame.resolvedTreeIndex.resolvedNode(
          for: identity
        )?.lifecycleMetadata
      else {
        continue
      }
      appearIDs.append(contentsOf: lifecycleMetadata.appearHandlerIDs)
      disappearIDs.append(contentsOf: lifecycleMetadata.disappearHandlerIDs)
    }

    lifecycleRegistry.restore(
      .init(
        appearHandlers: Dictionary(
          uniqueKeysWithValues: appearIDs.compactMap { handlerID in
            previousFrame.lifecycleHandlers.appearHandlers[handlerID].map { (handlerID, $0) }
          }
        ),
        disappearHandlers: Dictionary(
          uniqueKeysWithValues: disappearIDs.compactMap { handlerID in
            previousFrame.lifecycleHandlers.disappearHandlers[handlerID].map { (handlerID, $0) }
          }
        )
      )
    )
  }
}
/// Reads an environment value and maps it into authored content.
public struct EnvironmentReader<Value, Content: View>: View, ResolvableView {
  private let keyPath: KeyPath<EnvironmentValues, Value>
  private let content: (Value) -> Content
  private let authoringScope: DynamicPropertyScope?

  public init(
    _ keyPath: KeyPath<EnvironmentValues, Value>,
    @ViewBuilder content: @escaping (Value) -> Content
  ) {
    self.keyPath = keyPath
    self.content = content
    authoringScope = currentDynamicPropertyScope()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let view = withDynamicPropertyScope(authoringScope) {
      context.trackingObservableAccess {
        content(context.environmentValues[keyPath: keyPath])
      }
    }
    return view.resolveElements(in: context)
  }
}
