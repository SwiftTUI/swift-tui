public import Core

/// The typed location a `GestureStateBox` binds to inside a running
/// resolve pass. Parallels `DynamicStateLocation` in State.swift and
/// the private `FocusStateLocation` in FocusState.swift.
@MainActor
private struct GestureStateLocation<Value> {
  var getValue: @MainActor () -> Value
  var setValue: @MainActor (Value) -> Void
  var resetToSeed: @MainActor () -> Void
}

/// Storage for a `@GestureState` cell. Structurally mirrors `StateBox`:
/// a slot-ordinal-keyed store with a seed, a remembered ViewNode-scoped
/// location when bound, and a fallback local value for out-of-context
/// access (tests, construction-time reads).
@MainActor
public final class GestureStateBox<Value> {
  public let slotOrdinal: Int
  private let seed: Value
  private var localValue: Value
  private var boundLocationsByIdentity: [Identity: GestureStateLocation<Value>] = [:]
  private var lastBoundIdentity: Identity?

  public init(seed: Value, slotOrdinal: Int) {
    self.seed = seed
    self.localValue = seed
    self.slotOrdinal = slotOrdinal
  }

  /// The true initial seed value -- used by `makeLocation` to capture
  /// the correct reset target even when the local value has been mutated.
  fileprivate var seedValue: Value { seed }

  /// Reads the current value. When bound to a ViewNode, goes through
  /// the slot (dependency-tracked). Otherwise falls back to the local
  /// seed-initialized value.
  fileprivate func currentValue() -> Value {
    if let location = currentLocation() {
      return location.getValue()
    }
    return localValue
  }

  /// Writes a new value. When bound to a ViewNode, writes through
  /// setStateSlot (queues invalidation + respects AnimationContext).
  fileprivate func setValue(_ newValue: Value) {
    if let location = currentLocation() {
      location.setValue(newValue)
    } else {
      localValue = newValue
    }
  }

  /// Resets to the initial seed. Used by the recognizer on gesture end
  /// and by the registry on subtree teardown.
  fileprivate func resetToSeed() {
    setValue(seed)
  }

  fileprivate func remember(
    _ location: GestureStateLocation<Value>,
    for identity: Identity
  ) {
    boundLocationsByIdentity[identity] = location
    lastBoundIdentity = identity
  }

  fileprivate func rememberedLocation(
    for identity: Identity
  ) -> GestureStateLocation<Value>? {
    boundLocationsByIdentity[identity]
  }

  fileprivate func currentLocation() -> GestureStateLocation<Value>? {
    guard let lastBoundIdentity else { return nil }
    return boundLocationsByIdentity[lastBoundIdentity]
  }

  /// Produces a type-erased binding for registration with the runtime.
  public func eraseToAnyBinding() -> AnyGestureStateBinding {
    AnyGestureStateBinding(
      valueType: Value.self,
      setValue: { value in self.setValue(value) },
      reset: { self.resetToSeed() }
    )
  }

  /// Test-only -- reads the local/bound value without requiring an
  /// authoring context.
  public func currentValueForTests() -> Value { currentValue() }

  /// Test-only -- writes without requiring an authoring context.
  public func setForTests(_ newValue: Value) { setValue(newValue) }
}

/// Narrow binding type accepted by `Gesture.updating(_:body:)`.
///
/// Authors never construct this directly -- `$state` on a `@GestureState`
/// produces it. The `updating` modifier captures it and hands it to the
/// recognizer, which writes through it during gesture events.
@MainActor
public struct GestureStateBinding<Value> {
  public let box: GestureStateBox<Value>

  public init(box: GestureStateBox<Value>) {
    self.box = box
  }
}

/// A value whose storage is managed by a gesture recognizer and
/// automatically resets to the initial value when the gesture ends.
///
/// Access via `$state` (yields a `GestureStateBinding<T>` for
/// `Gesture.updating`) or by reading `wrappedValue` in the view body.
///
/// Structurally parallels `@State`: slot-ordinal storage keyed by
/// source location, lazy-bound to the current `ViewNode` during body
/// evaluation so reads/writes participate in the dependency tracker.
@propertyWrapper
@MainActor
public struct GestureState<Value> {
  private let box: GestureStateBox<Value>

  public init(
    wrappedValue: Value,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = GestureStateBox(
      seed: wrappedValue,
      slotOrdinal: StateSlotOrdinals.authored(line: line, column: column)
    )
  }

  public init(
    initialValue: Value,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = GestureStateBox(
      seed: initialValue,
      slotOrdinal: StateSlotOrdinals.authored(line: line, column: column)
    )
  }

  public var wrappedValue: Value {
    activeLocation()?.getValue() ?? box.currentValue()
  }

  public var projectedValue: GestureStateBinding<Value> {
    _ = activeLocation()  // lazy-bind side effect
    return GestureStateBinding(box: box)
  }

  /// Mirrors `@State.activeLocation()` -- lazy-binds the box to the
  /// current ViewNode so reads/writes flow through the slot machinery.
  /// Returns `nil` when outside a resolve pass (e.g. unit tests).
  ///
  /// Key parity with @State.activeLocation():
  ///   1. Checks AuthoringContextStorage.current (same task-local)
  ///   2. When ViewNodeContext.current != nil (resolve pass), builds and
  ///      remembers a fresh location via makeLocation(for:) and triggers
  ///      dependency tracking via location.getValue().
  ///   3. Falls back to the most-recently remembered location (bound-but-
  ///      not-in-resolve-pass) or nil.
  @discardableResult
  private func activeLocation() -> GestureStateLocation<Value>? {
    if let context = AuthoringContextStorage.current {
      if ViewNodeContext.current != nil {
        let location = makeLocation(for: context)
        box.remember(location, for: context.viewIdentity)
        _ = location.getValue()  // triggers dependency tracking
        return location
      }
      // Not in a resolve pass -- action/lifecycle closure.
      if let existing = box.rememberedLocation(for: context.viewIdentity) {
        return existing
      }
    }
    return box.currentLocation()
  }

  private func makeLocation(
    for context: AuthoringContext
  ) -> GestureStateLocation<Value> {
    let ordinal = box.slotOrdinal
    // Capture the true initial seed, not the current runtime value,
    // so resetToSeed always targets the construction-time value.
    let trueSeed = box.seedValue

    guard let viewNode = context.viewNode else {
      // No ViewNode -- fallback local-only location (degraded path,
      // e.g. body called outside a full resolve pipeline).
      return GestureStateLocation(
        getValue: { [weak box] in box?.currentValue() ?? trueSeed },
        setValue: { [weak box] newValue in box?.setValue(newValue) },
        resetToSeed: { [weak box] in box?.setValue(trueSeed) }
      )
    }

    return GestureStateLocation(
      getValue: {
        viewNode.stateSlot(ordinal: ordinal, seed: trueSeed)
      },
      setValue: { newValue in
        viewNode.setStateSlot(ordinal: ordinal, value: newValue)
      },
      resetToSeed: {
        viewNode.setStateSlot(ordinal: ordinal, value: trueSeed)
      }
    )
  }
}
