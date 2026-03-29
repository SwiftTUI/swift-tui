import Core

// SAFETY: Mutable state is protected by OSAllocatedUnfairLock. The @unchecked is needed because
// Storage contains `any DynamicStateEntryBox` existentials and the `invalidator` weak reference
// is a non-Sendable existential. The weak `invalidator` is only accessed on @MainActor.
package final class DynamicStateStore: @unchecked Sendable, Equatable {
  private struct Storage {
    var entries: [String: any DynamicStateEntryBox] = [:]
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package weak var invalidator: (any Invalidating)?
  package let invalidationIdentities: Set<Identity>

  package init(invalidationIdentities: Set<Identity> = [.init(components: [])]) {
    self.invalidationIdentities = invalidationIdentities
  }

  package static func == (
    lhs: DynamicStateStore,
    rhs: DynamicStateStore
  ) -> Bool {
    lhs === rhs
  }

  package func value<Value>(
    for key: String,
    seedValue: @autoclosure () -> Value
  ) -> Value {
    storage.withLockUnchecked { storage in
      if let existing = storage.entries[key] {
        guard let typed: Value = existing.value(as: Value.self) else {
          fatalError(
            "State type mismatch for key \(key). Expected \(Value.self), found \(existing.valueType)."
          )
        }
        return typed
      }

      let initialValue = seedValue()
      storage.entries[key] = DynamicStateEntry(initialValue)
      return initialValue
    }
  }

  package func set<Value>(
    _ value: Value,
    for key: String,
    invalidationIdentity: Identity? = nil
  ) {
    storage.withLockUnchecked { storage in
      if let existing = storage.entries[key] {
        existing.set(value)
      } else {
        storage.entries[key] = DynamicStateEntry(value)
      }
    }
    let identities =
      invalidationIdentity.map { Set([$0]) }
      ?? invalidationIdentities
    invalidator?.requestInvalidation(of: identities)
  }
}

private protocol DynamicStateEntryBox: AnyObject {
  var valueType: Any.Type { get }

  func value<Value>(as type: Value.Type) -> Value?
  func set<Value>(_ value: Value)
}

private final class DynamicStateEntry<StoredValue>: DynamicStateEntryBox {
  private let storage: OSAllocatedUnfairLock<StoredValue>
  let valueType: Any.Type = StoredValue.self

  init(_ value: StoredValue) {
    storage = OSAllocatedUnfairLock(uncheckedState: value)
  }

  func value<Value>(as type: Value.Type) -> Value? {
    guard self.valueType == type else {
      return nil
    }
    return storage.withLockUnchecked { value in
      value as? Value
    }
  }

  func set<Value>(_ value: Value) {
    guard self.valueType == Value.self, let typed = value as? StoredValue else {
      fatalError(
        "State type mismatch for entry. Expected \(self.valueType), received \(Value.self)."
      )
    }
    storage.withLockUnchecked { value in
      value = typed
    }
  }
}

package struct DynamicPropertyScope: Sendable {
  var viewIdentity: Identity
  var stateStore: DynamicStateStore?
  var environmentValues: EnvironmentValues?
  var focusedValues: FocusedValues

  func stateKey(for sourceLocation: String) -> String {
    "\(viewIdentity.path)#State[\(sourceLocation)]"
  }
}

package enum DynamicPropertyScopeStorage {
  @TaskLocal static var current: DynamicPropertyScope?
}

package func currentDynamicPropertyScope() -> DynamicPropertyScope? {
  DynamicPropertyScopeStorage.current
}

package func withDynamicPropertyScope<Result>(
  _ scope: DynamicPropertyScope?,
  _ apply: () -> Result
) -> Result {
  DynamicPropertyScopeStorage.$current.withValue(scope) {
    apply()
  }
}

package func withDynamicPropertyScope<Result>(
  _ scope: DynamicPropertyScope?,
  _ apply: () async -> Result
) async -> Result {
  await DynamicPropertyScopeStorage.$current.withValue(scope) {
    await apply()
  }
}

private struct DynamicStateLocation<Value> {
  var getValue: () -> Value
  var setValue: (Value) -> Void

  var binding: Binding<Value> {
    Binding(
      get: getValue,
      set: setValue
    )
  }
}

private final class StateBox<Value> {
  let sourceLocation: String
  private struct Storage {
    var seedValue: Value
    var boundLocation: DynamicStateLocation<Value>?
  }

  private let storage: OSAllocatedUnfairLock<Storage>

  init(
    seedValue: Value,
    sourceLocation: String
  ) {
    self.sourceLocation = sourceLocation
    storage = OSAllocatedUnfairLock(
      uncheckedState:
        Storage(
          seedValue: seedValue,
          boundLocation: nil
        )
    )
  }

  func currentSeedValue() -> Value {
    storage.withLockUnchecked { storage in
      storage.seedValue
    }
  }

  func updateSeedValue(_ newValue: Value) {
    storage.withLockUnchecked { storage in
      storage.seedValue = newValue
    }
  }

  func remember(_ location: DynamicStateLocation<Value>) {
    storage.withLockUnchecked { storage in
      storage.boundLocation = location
    }
  }

  func currentLocation() -> DynamicStateLocation<Value>? {
    storage.withLockUnchecked { storage in
      storage.boundLocation
    }
  }
}

@propertyWrapper
/// Local value storage owned by a view identity.
///
/// `@State` persistence is keyed by the view's identity path plus source
/// location, which keeps state attached to authored structure rather than to
/// reference identity.
public struct State<Value> {
  private let box: StateBox<Value>

  /// Creates state with the supplied initial wrapped value.
  public init(
    wrappedValue: Value,
    fileID: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: wrappedValue,
      sourceLocation: "\(fileID):\(line):\(column)"
    )
  }

  public init(
    initialValue: Value,
    fileID: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: initialValue,
      sourceLocation: "\(fileID):\(line):\(column)"
    )
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
        get: { wrappedValue },
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
    if let stateStore = scope.stateStore {
      let stateKey = scope.stateKey(for: box.sourceLocation)
      return DynamicStateLocation(
        getValue: {
          stateStore.value(
            for: stateKey,
            seedValue: box.currentSeedValue()
          )
        },
        setValue: { newValue in
          stateStore.set(
            newValue,
            for: stateKey,
            invalidationIdentity: scope.viewIdentity
          )
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
  func resolveBody(
    in context: ResolveContext,
    body makeBody: () -> Body
  ) -> [ResolvedNode] {
    DynamicPropertyScopeStorage.$current.withValue(
      .init(
        viewIdentity: context.identity,
        stateStore: context.dynamicStateStore,
        environmentValues: context.environmentValues,
        focusedValues: context.focusedValues
      )
    ) {
      let body = context.trackingObservableAccess {
        makeBody()
      }
      return body.resolveElements(in: context)
    }
  }
}
