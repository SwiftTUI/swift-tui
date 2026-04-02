import Core

private struct FocusStateSnapshot<Value: Equatable> {
  var value: Value
  var hasPendingRequest: Bool
}

@MainActor
private final class FocusStateStorage<Value: Equatable>: @unchecked Sendable {
  private let snapshot: OSAllocatedUnfairLock<FocusStateSnapshot<Value>>

  init(
    value: Value,
    hasPendingRequest: Bool = false
  ) {
    snapshot = OSAllocatedUnfairLock(
      uncheckedState:
        .init(
          value: value,
          hasPendingRequest: hasPendingRequest
        )
    )
  }

  func currentSnapshot() -> FocusStateSnapshot<Value> {
    snapshot.withLockUnchecked { snapshot in
      snapshot
    }
  }

  func requestValue(_ newValue: Value) {
    snapshot.withLockUnchecked { snapshot in
      snapshot.value = newValue
      snapshot.hasPendingRequest = true
    }
  }

  @discardableResult
  func applyRuntimeValue(_ newValue: Value) -> Bool {
    snapshot.withLockUnchecked { snapshot in
      let didChange = snapshot.value != newValue
      snapshot.value = newValue
      snapshot.hasPendingRequest = false
      return didChange
    }
  }
}

@MainActor
private struct FocusStateLocation<Value: Equatable> {
  var bindingID: String
  var snapshot: () -> FocusStateSnapshot<Value>
  var requestValue: (Value) -> Void
  var applyRuntimeValue: (Value) -> Bool
}

@MainActor
private final class FocusStateBox<Value: Equatable> {
  private var ordinal: Int?

  private struct Storage {
    var localStorage: FocusStateStorage<Value>
    var boundLocation: FocusStateLocation<Value>?
  }

  private let storage: OSAllocatedUnfairLock<Storage>

  init(seedValue: Value) {
    storage = OSAllocatedUnfairLock(
      uncheckedState:
        Storage(
          localStorage: .init(value: seedValue),
          boundLocation: nil
        )
    )
  }

  func currentLocalSnapshot() -> FocusStateSnapshot<Value> {
    let localStorage = storage.withLockUnchecked { storage in
      storage.localStorage
    }
    return localStorage.currentSnapshot()
  }

  func requestLocalValue(_ newValue: Value) {
    let localStorage = storage.withLockUnchecked { storage in
      storage.localStorage
    }
    localStorage.requestValue(newValue)
  }

  @discardableResult
  func applyRuntimeLocalValue(_ newValue: Value) -> Bool {
    let localStorage = storage.withLockUnchecked { storage in
      storage.localStorage
    }
    return localStorage.applyRuntimeValue(newValue)
  }

  func remember(_ location: FocusStateLocation<Value>) {
    storage.withLockUnchecked { storage in
      storage.boundLocation = location
    }
  }

  func currentLocation() -> FocusStateLocation<Value>? {
    storage.withLockUnchecked { storage in
      storage.boundLocation
    }
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

extension DynamicPropertyScope {
  fileprivate func focusStateKey(
    for ordinal: Int
  ) -> String {
    "\(viewIdentity.path)#FocusState[\(ordinal)]"
  }
}

@propertyWrapper
@MainActor
/// A focus-owned value synchronized with the runtime focus system.
public struct FocusState<Value: Equatable> {
  /// A projection used by `.focused(...)` modifiers.
  public struct Binding {
    private let location: FocusStateLocation<Value>

    fileprivate init(
      location: FocusStateLocation<Value>
    ) {
      self.location = location
    }

    /// The current authored focus value.
    @MainActor
    public var wrappedValue: Value {
      get { location.snapshot().value }
      nonmutating set { location.requestValue(newValue) }
    }

    public var projectedValue: Self {
      self
    }
  }

  private let box: FocusStateBox<Value>

  private init(seedValue: Value) {
    box = FocusStateBox(seedValue: seedValue)
  }

  /// Creates a boolean focus state with a default value of `false`.
  public init() where Value == Bool {
    self.init(seedValue: false)
  }

  /// Creates an optional focus state with a default value of `nil`.
  public init<Wrapped: Hashable>() where Value == Wrapped? {
    self.init(seedValue: nil)
  }

  public var wrappedValue: Value {
    get {
      activeLocation()?.snapshot().value ?? box.currentLocalSnapshot().value
    }
    nonmutating set {
      if let location = activeLocation() {
        location.requestValue(newValue)
      } else {
        box.requestLocalValue(newValue)
      }
    }
  }

  public var projectedValue: Binding {
    Binding(location: activeLocation() ?? localLocation())
  }

  private func activeLocation() -> FocusStateLocation<Value>? {
    if let scope = currentDynamicPropertyScope() {
      let location = makeLocation(for: scope)
      box.remember(location)
      _ = location.snapshot()
      return location
    }

    return box.currentLocation()
  }

  private func makeLocation(
    for scope: DynamicPropertyScope
  ) -> FocusStateLocation<Value> {
    guard let ordinal = box.currentOrdinal(for: scope) else {
      return localLocation()
    }

    let seedSnapshot = box.currentLocalSnapshot()

    if let viewNode = scope.viewNode {
      let bindingID = "\(viewNode.identity.path)#FocusState[\(ordinal)]"
      let storage = viewNode.stateSlot(
        ordinal: ordinal,
        seed: FocusStateStorage(
          value: seedSnapshot.value,
          hasPendingRequest: seedSnapshot.hasPendingRequest
        )
      )

      return FocusStateLocation(
        bindingID: bindingID,
        snapshot: {
          storage.currentSnapshot()
        },
        requestValue: { newValue in
          storage.requestValue(newValue)
          viewNode.requestInvalidation()
        },
        applyRuntimeValue: { newValue in
          let didChange = storage.applyRuntimeValue(newValue)
          if didChange {
            viewNode.requestInvalidation()
          }
          return didChange
        }
      )
    }

    if let stateStore = scope.stateStore {
      let stateKey = scope.focusStateKey(for: ordinal)
      let storage = stateStore.value(
        for: stateKey,
        seedValue: FocusStateStorage(
          value: seedSnapshot.value,
          hasPendingRequest: seedSnapshot.hasPendingRequest
        )
      )

      return FocusStateLocation(
        bindingID: stateKey,
        snapshot: {
          storage.currentSnapshot()
        },
        requestValue: { newValue in
          storage.requestValue(newValue)
          stateStore.set(
            storage,
            for: stateKey,
            invalidationIdentity: scope.viewIdentity
          )
        },
        applyRuntimeValue: { newValue in
          let didChange = storage.applyRuntimeValue(newValue)
          if didChange {
            stateStore.set(
              storage,
              for: stateKey,
              invalidationIdentity: scope.viewIdentity
            )
          }
          return didChange
        }
      )
    }

    return localLocation()
  }

  private func localLocation() -> FocusStateLocation<Value> {
    FocusStateLocation(
      bindingID: "FocusState.local[\(ObjectIdentifier(box))]",
      snapshot: {
        box.currentLocalSnapshot()
      },
      requestValue: { newValue in
        box.requestLocalValue(newValue)
      },
      applyRuntimeValue: { newValue in
        box.applyRuntimeLocalValue(newValue)
      }
    )
  }
}

@MainActor
extension FocusState.Binding {
  package var bindingID: String {
    location.bindingID
  }

  package var hasPendingRequest: Bool {
    location.snapshot().hasPendingRequest
  }

  package func applyRuntimeValue(_ newValue: Value) -> Bool {
    location.applyRuntimeValue(newValue)
  }
}

extension View {
  public func focused(
    _ binding: FocusState<Bool>.Binding
  ) -> some View {
    BoolFocusBindingModifier(content: self, binding: binding)
  }

  public func focused<Value: Hashable>(
    _ binding: FocusState<Value?>.Binding,
    equals value: Value
  ) -> some View {
    OptionalFocusBindingModifier(
      content: self,
      binding: binding,
      value: value
    )
  }
}

@MainActor
private struct BoolFocusBindingModifier<Content: View>: View, ResolvableView {
  var content: Content
  var binding: FocusState<Bool>.Binding

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    context.localFocusBindingRegistry?.register(
      identity: node.identity,
      bindingID: binding.bindingID,
      hasPendingRequest: binding.hasPendingRequest,
      isSelected: binding.wrappedValue,
      applyRuntimeFocus: { isFocused in
        binding.applyRuntimeValue(isFocused)
      }
    )
    return [node]
  }
}

@MainActor
private struct OptionalFocusBindingModifier<Content: View, Value: Hashable>: View,
  ResolvableView
{
  var content: Content
  var binding: FocusState<Value?>.Binding
  var value: Value

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    context.localFocusBindingRegistry?.register(
      identity: node.identity,
      bindingID: binding.bindingID,
      hasPendingRequest: binding.hasPendingRequest,
      isSelected: binding.wrappedValue == value,
      applyRuntimeFocus: { isFocused in
        if isFocused {
          return binding.applyRuntimeValue(value)
        }
        guard binding.wrappedValue == value else {
          return false
        }
        return binding.applyRuntimeValue(nil)
      }
    )
    return [node]
  }
}
