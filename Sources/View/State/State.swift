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

  func stateKey(for sourceLocation: String) -> String {
    "\(viewIdentity.path)#State[\(sourceLocation)]"
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
  let sourceLocation: String
  private var seedValue: Value
  private var boundLocation: DynamicStateLocation<Value>?

  init(
    seedValue: Value,
    sourceLocation: String
  ) {
    self.sourceLocation = sourceLocation
    self.seedValue = seedValue
    boundLocation = nil
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
}

@propertyWrapper
@MainActor
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
  @MainActor
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
