package import Core

@MainActor
package final class DynamicStateStore: Equatable {
  private var entries: [String: any DynamicStateEntryBox] = [:]
  package weak var invalidator: (any Invalidating)?
  package let invalidationIdentities: Set<Identity>

  package init(
    invalidationIdentities: Set<Identity> = [
      .init(components: [] as [IdentityComponent])
    ]
  ) {
    self.invalidationIdentities = invalidationIdentities
  }

  nonisolated package static func == (
    lhs: DynamicStateStore,
    rhs: DynamicStateStore
  ) -> Bool {
    lhs === rhs
  }

  package func value<Value>(
    for key: String,
    seedValue: @autoclosure () -> Value
  ) -> Value {
    if let existing = entries[key] {
      guard let typed: Value = existing.value(as: Value.self) else {
        fatalError(
          "State type mismatch for key \(key). Expected \(Value.self), found \(existing.valueType)."
        )
      }
      return typed
    }

    let initialValue = seedValue()
    entries[key] = DynamicStateEntry(initialValue)
    return initialValue
  }

  package func set<Value>(
    _ value: Value,
    for key: String,
    invalidationIdentity: Identity? = nil
  ) {
    if let existing = entries[key] {
      existing.set(value)
    } else {
      entries[key] = DynamicStateEntry(value)
    }
    let identities =
      invalidationIdentity.map { Set([$0]) }
      ?? invalidationIdentities
    invalidator?.requestInvalidation(of: identities)
  }
}

@MainActor
private protocol DynamicStateEntryBox: AnyObject {
  var valueType: Any.Type { get }

  func value<Value>(as type: Value.Type) -> Value?
  func set<Value>(_ value: Value)
}

@MainActor
private final class DynamicStateEntry<StoredValue>: DynamicStateEntryBox {
  private var storedValue: StoredValue
  let valueType: Any.Type = StoredValue.self

  init(_ value: StoredValue) {
    storedValue = value
  }

  func value<Value>(as type: Value.Type) -> Value? {
    guard self.valueType == type else {
      return nil
    }
    return storedValue as? Value
  }

  func set<Value>(_ value: Value) {
    guard self.valueType == Value.self, let typed = value as? StoredValue else {
      fatalError(
        "State type mismatch for entry. Expected \(self.valueType), received \(Value.self)."
      )
    }
    storedValue = typed
  }
}

@MainActor
package struct DynamicPropertyScope {
  var viewIdentity: Identity
  var stateStore: DynamicStateStore?
  var environmentValues: EnvironmentValues?
  var focusedValues: FocusedValues
  var viewNode: Core.ViewNode?
  var ordinalTracker: DynamicPropertyOrdinalTracker = .init()

  func stateKey(for ordinal: Int) -> String {
    "\(viewIdentity.path)#State[\(ordinal)]"
  }
}

package enum DynamicPropertyScopeStorage {
  @TaskLocal static var current: DynamicPropertyScope?
}

@MainActor
package func currentDynamicPropertyScope() -> DynamicPropertyScope? {
  DynamicPropertyScopeStorage.current
}

@MainActor
package func makeDynamicPropertyScope(
  for context: ResolveContext,
  viewNode: Core.ViewNode? = ViewNodeContext.current
) -> DynamicPropertyScope {
  DynamicPropertyScope(
    viewIdentity: context.identity,
    stateStore: context.dynamicStateStore,
    environmentValues: context.environmentValues,
    focusedValues: context.focusedValues,
    viewNode: viewNode,
    ordinalTracker: .init()
  )
}

@MainActor
package func withDynamicPropertyScope<Result>(
  _ scope: DynamicPropertyScope?,
  _ apply: () -> Result
) -> Result {
  DynamicPropertyScopeStorage.$current.withValue(scope) {
    apply()
  }
}

@MainActor
package func withDynamicPropertyScope<Result>(
  _ scope: DynamicPropertyScope?,
  _ apply: () async -> Result
) async -> Result {
  await DynamicPropertyScopeStorage.$current.withValue(scope) {
    await apply()
  }
}

@MainActor
package final class DynamicPropertyOrdinalTracker {
  private(set) var nextOrdinal = 0

  package init() {}

  package func claimOrdinal() -> Int {
    defer {
      nextOrdinal += 1
    }
    return nextOrdinal
  }
}

@MainActor
private struct DynamicStateLocation<Value> {
  var getValue: @MainActor () -> Value
  var setValue: @MainActor (Value) -> Void

  var binding: Binding<Value> {
    Binding(
      mainActorGet: getValue,
      set: setValue
    )
  }
}

@MainActor
private final class StateBox<Value> {
  private var ordinal: Int?
  private var seedValue: Value
  private var boundLocation: DynamicStateLocation<Value>?
  private var retainedValuesByIdentity: [Identity: Value]

  init(seedValue: Value) {
    self.seedValue = seedValue
    boundLocation = nil
    retainedValuesByIdentity = [:]
  }

  func currentSeedValue() -> Value {
    seedValue
  }

  func updateSeedValue(_ newValue: Value) {
    seedValue = newValue
  }

  func remember(_ location: DynamicStateLocation<Value>) {
    boundLocation = location
  }

  func currentLocation() -> DynamicStateLocation<Value>? {
    boundLocation
  }

  func retainedValue(
    for identity: Identity
  ) -> Value? {
    retainedValuesByIdentity[identity]
  }

  func storeRetainedValue(
    _ value: Value,
    for identity: Identity
  ) {
    retainedValuesByIdentity[identity] = value
  }

  func currentOrdinal(
    for scope: DynamicPropertyScope?
  ) -> Int? {
    if let ordinal {
      return ordinal
    }
    guard let scope else {
      return nil
    }
    let ordinal = scope.ordinalTracker.claimOrdinal()
    self.ordinal = ordinal
    return ordinal
  }
}

@propertyWrapper
@MainActor
/// Local value storage owned by a view identity.
///
/// `@State` persistence is keyed by the view's identity path plus ordinal
/// access order within that view.
public struct State<Value> {
  private let box: StateBox<Value>

  /// Creates state with the supplied initial wrapped value.
  public init(wrappedValue: Value) {
    box = StateBox(seedValue: wrappedValue)
  }

  public init(initialValue: Value) {
    box = StateBox(seedValue: initialValue)
  }

  public var wrappedValue: Value {
    get {
      activeLocation()?.getValue() ?? box.currentSeedValue()
    }
    nonmutating set {
      if let location = activeLocation() {
        location.setValue(newValue)
      } else {
        box.updateSeedValue(newValue)
      }
    }
  }

  public var projectedValue: Binding<Value> {
    activeLocation()?.binding
      ?? Binding(
        mainActorGet: { wrappedValue },
        set: { wrappedValue = $0 }
      )
  }

  private func activeLocation() -> DynamicStateLocation<Value>? {
    if let scope = DynamicPropertyScopeStorage.current {
      let location = makeLocation(for: scope)
      box.remember(location)
      _ = location.getValue()
      return location
    }

    return box.currentLocation()
  }

  private func makeLocation(
    for scope: DynamicPropertyScope
  ) -> DynamicStateLocation<Value> {
    guard let ordinal = box.currentOrdinal(for: scope) else {
      return DynamicStateLocation(
        getValue: { box.currentSeedValue() },
        setValue: { newValue in
          box.updateSeedValue(newValue)
        }
      )
    }

    let retainedSeed = box.retainedValue(for: scope.viewIdentity) ?? box.currentSeedValue()

    if let stateStore = scope.stateStore {
      let stateKey = scope.stateKey(for: ordinal)
      return DynamicStateLocation(
        getValue: {
          stateStore.value(
            for: stateKey,
            seedValue: retainedSeed
          )
        },
        setValue: { newValue in
          stateStore.set(
            newValue,
            for: stateKey,
            invalidationIdentity: scope.viewIdentity
          )
          box.storeRetainedValue(newValue, for: scope.viewIdentity)
        }
      )
    }

    if let viewNode = scope.viewNode {
      return DynamicStateLocation(
        getValue: {
          viewNode.stateSlot(
            ordinal: ordinal,
            seed: retainedSeed
          )
        },
        setValue: { newValue in
          viewNode.setStateSlot(ordinal: ordinal, value: newValue)
          box.storeRetainedValue(newValue, for: scope.viewIdentity)
        }
      )
    }

    return DynamicStateLocation(
      getValue: { box.currentSeedValue() },
      setValue: { newValue in
        box.updateSeedValue(newValue)
      }
    )
  }
}

extension View {
  @MainActor
  func resolveBody(
    in context: ResolveContext,
    body makeBody: () -> Body
  ) -> [ResolvedNode] {
    if let scope = currentDynamicPropertyScope() {
      let body = context.trackingObservableAccess {
        makeBody()
      }
      return withDynamicPropertyScope(scope) {
        body.resolveElements(in: context)
      }
    }

    let dynamicPropertyScope = makeDynamicPropertyScope(for: context)
    return withDynamicPropertyScope(dynamicPropertyScope) {
      let body = context.trackingObservableAccess {
        makeBody()
      }
      return body.resolveElements(in: context)
    }
  }
}
