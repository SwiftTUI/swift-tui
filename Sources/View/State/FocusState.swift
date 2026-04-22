package import Core

private struct FocusStateSnapshot<Value: Equatable> {
  var value: Value
  var hasPendingRequest: Bool
}

@MainActor
private final class FocusStateStorage<Value: Equatable> {
  private var snapshot: FocusStateSnapshot<Value>

  init(
    value: Value,
    hasPendingRequest: Bool = false
  ) {
    snapshot = .init(
      value: value,
      hasPendingRequest: hasPendingRequest
    )
  }

  func currentSnapshot() -> FocusStateSnapshot<Value> {
    snapshot
  }

  func requestValue(_ newValue: Value) {
    snapshot.value = newValue
    snapshot.hasPendingRequest = true
  }

  @discardableResult
  func applyRuntimeValue(_ newValue: Value) -> Bool {
    let didChange = snapshot.value != newValue
    snapshot.value = newValue
    snapshot.hasPendingRequest = false
    return didChange
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
  private let slotOrdinal: Int

  private struct Storage {
    var localStorage: FocusStateStorage<Value>
    var boundLocation: FocusStateLocation<Value>?
  }

  private var storage: Storage

  init(
    seedValue: Value,
    slotOrdinal: Int
  ) {
    self.slotOrdinal = slotOrdinal
    storage = Storage(
      localStorage: .init(value: seedValue),
      boundLocation: nil
    )
  }

  func currentLocalSnapshot() -> FocusStateSnapshot<Value> {
    storage.localStorage.currentSnapshot()
  }

  func requestLocalValue(_ newValue: Value) {
    storage.localStorage.requestValue(newValue)
  }

  @discardableResult
  func applyRuntimeLocalValue(_ newValue: Value) -> Bool {
    storage.localStorage.applyRuntimeValue(newValue)
  }

  func remember(_ location: FocusStateLocation<Value>) {
    storage.boundLocation = location
  }

  func currentLocation() -> FocusStateLocation<Value>? {
    storage.boundLocation
  }

  var currentOrdinal: Int {
    slotOrdinal
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

  private init(
    seedValue: Value,
    line: UInt,
    column: UInt
  ) {
    box = FocusStateBox(
      seedValue: seedValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      )
    )
  }

  /// Creates a boolean focus state with a default value of `false`.
  public init(
    line: UInt = #line,
    column: UInt = #column
  ) where Value == Bool {
    self.init(
      seedValue: false,
      line: line,
      column: column
    )
  }

  /// Creates an optional focus state with a default value of `nil`.
  public init<Wrapped: Hashable>(
    line: UInt = #line,
    column: UInt = #column
  ) where Value == Wrapped? {
    self.init(
      seedValue: nil,
      line: line,
      column: column
    )
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
    if let context = currentAuthoringContext() {
      let location = makeLocation(for: context)
      box.remember(location)
      _ = location.snapshot()
      return location
    }

    return box.currentLocation()
  }

  private func makeLocation(
    for context: AuthoringContext
  ) -> FocusStateLocation<Value> {
    let ordinal = box.currentOrdinal
    let seedSnapshot = box.currentLocalSnapshot()

    if let viewNode = context.viewNode {
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
    modifier(BoolFocusBindingModifier(binding: binding))
  }

  public func focused<Value: Hashable>(
    _ binding: FocusState<Value?>.Binding,
    equals value: Value
  ) -> some View {
    modifier(
      OptionalFocusBindingModifier(
        binding: binding,
        value: value
      )
    )
  }
}

@MainActor
public struct BoolFocusBindingModifier: PrimitiveViewModifier {
  var binding: FocusState<Bool>.Binding

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
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
public struct OptionalFocusBindingModifier<Value: Hashable>: PrimitiveViewModifier {
  var binding: FocusState<Value?>.Binding
  var value: Value

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
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
