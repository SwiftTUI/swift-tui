public import SwiftTUICore

/// The typed location a `GestureStateBox` binds to inside a running
/// resolve pass. Parallels `DynamicStateLocation` in State.swift and
/// the private `FocusStateLocation` in FocusState.swift.
@MainActor
private struct GestureStateLocation<Value> {
  var owner: StateStorageOwner? = nil
  var slot: StateSlotIdentifier? = nil
  var getValue: @MainActor () -> Value
  var setValue: @MainActor (Value) -> Void
  var resetToSeed: @MainActor () -> Void
}

/// Storage for a `@GestureState` cell. Its structure mirrors `StateBox`.
/// A slot-ordinal-keyed store contains a seed.
/// It remembers a ViewNode-scoped or graph-scoped location when bound.
/// A local fallback value supports tests and reads during construction.
/// Direct box operations use the explicitly installed authoring scope. Use
/// the wrapper's projected binding for callbacks that must retain an owner;
/// a box shared by multiple wrapper copies has no single implicit owner.
@MainActor
public final class GestureStateBox<Value> {
  /// A remembered location plus how it was bound; a path-qualified binding
  /// (made by the dynamic-property update pass) wins over access-time
  /// re-binding, which has no ambient path (see `StateBox.BoundLocation`).
  private struct LocationKey: Hashable {
    var owner: StateStorageOwner
    var slot: StateSlotIdentifier
  }

  public let slotOrdinal: Int
  private let seed: Value
  private var localValue: Value
  private var locations: [LocationKey: GestureStateLocation<Value>] = [:]
  private var selectedSlots: [StateStorageOwner: StateSlotIdentifier] = [:]
  /// Builds the transaction governing a genuine end-of-gesture reset from
  /// the value being reset. Nil for the plain initializers — their resets
  /// snap. Resolve-time resets (recognizer teardown, registry drain) never
  /// consult it; see ``resetToSeedApplyingResetTransaction()``.
  fileprivate let resetTransactionProvider: (@MainActor (Value) -> Transaction)?

  public init(seed: Value, slotOrdinal: Int) {
    self.seed = seed
    self.localValue = seed
    self.slotOrdinal = slotOrdinal
    self.resetTransactionProvider = nil
  }

  package init(
    seed: Value,
    slotOrdinal: Int,
    resetTransactionProvider: (@MainActor (Value) -> Transaction)?
  ) {
    self.seed = seed
    self.localValue = seed
    self.slotOrdinal = slotOrdinal
    self.resetTransactionProvider = resetTransactionProvider
  }

  /// The true initial seed value -- used by `makeLocation` to capture
  /// the correct reset target even when the local value has been mutated.
  fileprivate var seedValue: Value { seed }

  fileprivate func localFallbackValue() -> Value {
    localValue
  }

  fileprivate func setLocalFallbackValue(_ newValue: Value) {
    localValue = newValue
  }

  /// Reads the current value. When bound to a ViewNode, goes through
  /// the slot (dependency-tracked). Otherwise falls back to the local
  /// seed-initialized value.
  public func currentValue() -> Value {
    if let location = scopedLocation() {
      return location.getValue()
    }
    return localValue
  }

  /// Writes a new value. When bound to a ViewNode, writes through
  /// setStateSlot (queues invalidation + respects AnimationContext).
  public func setValue(_ newValue: Value) {
    if let location = scopedLocation() {
      location.setValue(newValue)
    } else {
      localValue = newValue
    }
  }

  /// Resets to the initial seed with no transaction applied. Used by
  /// resolve-time paths (recognizer teardown on replacement and the
  /// registry's subtree drain), which must never animate: `.gesture(_:)`
  /// rebuilds recognizers during resolve, so a scoped reset here would
  /// animate structural churn.
  public func resetToSeed() {
    setValue(seed)
  }

  /// Resets to the initial seed inside the authored reset transaction,
  /// when one exists. Only the genuine end-of-gesture paths call this —
  /// the terminal-phase and deadline resets in `UpdatingDecorator`.
  /// SwiftUI probe (2026-08-05): the reset transaction alone governs the
  /// reset; a body-mutated transaction does not carry over to it.
  package func resetToSeedApplyingResetTransaction() {
    guard let resetTransactionProvider else {
      resetToSeed()
      return
    }
    let transaction = resetTransactionProvider(currentValue())
    withTransaction(transaction) {
      setValue(seed)
    }
  }

  fileprivate func remember(
    _ location: GestureStateLocation<Value>,
    for owner: StateStorageOwner,
    path: StateSlotPath = .root
  ) {
    let retired = selectedSlots.keys.filter { LiveViewGraphRegistry.node(for: $0) == nil }
    if !retired.isEmpty {
      let retired = Set(retired)
      selectedSlots = selectedSlots.filter { !retired.contains($0.key) }
      locations = locations.filter { !retired.contains($0.key.owner) }
    }
    let slot = StateSlotIdentifier(ordinal: slotOrdinal, path: path)
    locations[LocationKey(owner: owner, slot: slot)] = location
    selectedSlots[owner] = slot
  }

  fileprivate func rememberedLocation(
    for owner: StateStorageOwner
  ) -> GestureStateLocation<Value>? {
    guard let slot = selectedSlots[owner] else { return nil }
    return locations[LocationKey(owner: owner, slot: slot)]
  }

  fileprivate func rememberedLocation(
    for owner: StateStorageOwner, path: StateSlotPath
  ) -> GestureStateLocation<Value>? {
    locations[LocationKey(owner: owner, slot: .init(ordinal: slotOrdinal, path: path))]
  }

  fileprivate func rememberedPathQualifiedLocation(
    for owner: StateStorageOwner
  ) -> GestureStateLocation<Value>? {
    guard let slot = selectedSlots[owner], !slot.path.isEmpty else { return nil }
    return locations[LocationKey(owner: owner, slot: slot)]
  }

  fileprivate var rememberedLocationCount: Int { locations.count }

  fileprivate func scopedLocation() -> GestureStateLocation<Value>? {
    guard let context = AuthoringContextStorage.current else {
      return nil
    }
    guard let storageOwner = stateStorageOwner(for: context) else {
      return nil
    }
    if let existing = rememberedLocation(for: storageOwner) {
      return existing
    }
    return nil
  }

  /// Produces a type-erased binding for registration with the runtime.
  public func eraseToAnyBinding() -> AnyGestureStateBinding {
    GestureStateBinding(box: self).eraseToAnyBinding()
  }

}

/// Narrow binding type accepted by `Gesture.updating(_:body:)`.
///
/// Authors never construct this directly; `$state` on a `@GestureState`
/// produces it. The `updating` modifier captures it and hands it to the
/// recognizer, which writes through it during gesture events. The binding
/// captures its exact graph-owner location when projected; an attachment on
/// a child or a callback in another authoring scope cannot redirect it.
@MainActor
public struct GestureStateBinding<Value> {
  public let box: GestureStateBox<Value>
  private let location: GestureStateLocation<Value>?

  public init(box: GestureStateBox<Value>) {
    self.box = box
    location = box.scopedLocation()
  }

  fileprivate init(box: GestureStateBox<Value>, location: GestureStateLocation<Value>?) {
    self.box = box
    self.location = location
  }

  package func currentValue() -> Value {
    location?.getValue() ?? box.localFallbackValue()
  }

  package func setValue(_ value: Value) {
    if let location { location.setValue(value) } else { box.setLocalFallbackValue(value) }
  }

  package func resetToSeed() {
    if let location { location.resetToSeed() } else { box.setLocalFallbackValue(box.seedValue) }
  }

  package func resetToSeedApplyingResetTransaction() {
    guard let provider = box.resetTransactionProvider else {
      resetToSeed()
      return
    }
    withTransaction(provider(currentValue())) { resetToSeed() }
  }

  package func hasSameStorage(as other: Self) -> Bool {
    if let location, let otherLocation = other.location {
      return location.owner == otherLocation.owner && location.slot == otherLocation.slot
    }
    return location == nil && other.location == nil && box === other.box
  }

  package func eraseToAnyBinding() -> AnyGestureStateBinding {
    AnyGestureStateBinding(
      valueType: Value.self,
      setValue: { setValue($0) },
      reset: { resetToSeed() }
    )
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
/// Bound locations are graph-scoped for imperative gesture updates.
/// Thus, a reused gesture-state box starts from the seed and reset lifecycle of its current render graph.
@propertyWrapper
@MainActor
public struct GestureState<Value> {
  private let box: GestureStateBox<Value>
  private var capturedLocation: GestureStateLocation<Value>?

  #if DEBUG
    package var rememberedLocationCountForTesting: Int { box.rememberedLocationCount }
  #endif

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

  /// Creates gesture state whose end-of-gesture reset applies
  /// `resetTransaction`, typically an animation for the snap-back.
  /// Resolve-time resets (recognizer teardown, subtree removal) stay
  /// un-animated regardless.
  public init(
    wrappedValue: Value,
    resetTransaction: Transaction,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = GestureStateBox(
      seed: wrappedValue,
      slotOrdinal: StateSlotOrdinals.authored(line: line, column: column),
      resetTransactionProvider: { _ in resetTransaction }
    )
  }

  /// `init(wrappedValue:resetTransaction:)` under its explicit-value label.
  public init(
    initialValue: Value,
    resetTransaction: Transaction,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = GestureStateBox(
      seed: initialValue,
      slotOrdinal: StateSlotOrdinals.authored(line: line, column: column),
      resetTransactionProvider: { _ in resetTransaction }
    )
  }

  /// Creates gesture state whose end-of-gesture reset consults `reset`:
  /// the closure receives the value being reset and can mutate the
  /// transaction that will govern the seed write.
  public init(
    wrappedValue: Value,
    reset: @escaping @MainActor (Value, inout Transaction) -> Void,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = GestureStateBox(
      seed: wrappedValue,
      slotOrdinal: StateSlotOrdinals.authored(line: line, column: column),
      resetTransactionProvider: { value in
        var transaction = Transaction()
        reset(value, &transaction)
        return transaction
      }
    )
  }

  /// `init(wrappedValue:reset:)` under its explicit-value label.
  public init(
    initialValue: Value,
    reset: @escaping @MainActor (Value, inout Transaction) -> Void,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = GestureStateBox(
      seed: initialValue,
      slotOrdinal: StateSlotOrdinals.authored(line: line, column: column),
      resetTransactionProvider: { value in
        var transaction = Transaction()
        reset(value, &transaction)
        return transaction
      }
    )
  }

  public var wrappedValue: Value {
    activeLocation()?.getValue() ?? box.currentValue()
  }

  public var projectedValue: GestureStateBinding<Value> {
    GestureStateBinding(box: box, location: activeLocation())
  }

  /// Prepared copies carry an exact location. Unprepared app-held values
  /// retain the explicit ambient-owner lookup used by direct box clients.
  @discardableResult
  private func activeLocation() -> GestureStateLocation<Value>? {
    if let capturedLocation { return capturedLocation }
    guard let context = AuthoringContextStorage.current else {
      return nil
    }
    guard let storageOwner = stateStorageOwner(for: context) else {
      return nil
    }

    if ViewNodeContext.current != nil {
      // A path-qualified binding made by this evaluation's update pass wins
      // during resolve (see `State.activeLocation`).
      if let qualified = box.rememberedPathQualifiedLocation(for: storageOwner) {
        _ = qualified.getValue()  // triggers dependency tracking
        return qualified
      }
      let location = makeLocation(owner: storageOwner)
      box.remember(
        location,
        for: storageOwner
      )
      _ = location.getValue()  // triggers dependency tracking
      return location
    }
    // Not in a resolve pass -- action/lifecycle closure.
    if let existing = box.rememberedLocation(for: storageOwner) {
      return existing
    }
    return nil
  }

  private func makeLocation(
    owner storageOwner: StateStorageOwner,
    path: StateSlotPath = .root
  ) -> GestureStateLocation<Value> {
    let slotIdentifier = StateSlotIdentifier(ordinal: box.slotOrdinal, path: path)
    // Capture the true initial seed, not the current runtime value,
    // so resetToSeed always targets the construction-time value.
    let trueSeed = box.seedValue

    if ViewNodeContext.current != nil,
      let viewNode = LiveViewGraphRegistry.node(for: storageOwner)
    {
      // Resolve-time claim bookkeeping (see `ViewNode.recordStateSlotClaim`).
      viewNode.recordStateSlotClaim(
        slotIdentifier,
        claimant: ObjectIdentifier(box),
        wrapperDescription: "@GestureState<\(Value.self)>"
      )
    }

    return GestureStateLocation(
      owner: storageOwner,
      slot: slotIdentifier,
      getValue: { [weak box] in
        guard let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) else {
          return box?.localFallbackValue() ?? trueSeed
        }
        return withTransientDormantStateSlot {
          liveViewNode.stateSlot(slotIdentifier, seed: trueSeed)
        }
      },
      setValue: { [weak box] newValue in
        guard let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) else {
          box?.setLocalFallbackValue(newValue)
          return
        }
        withTransientDormantStateSlot {
          liveViewNode.setStateSlot(
            slotIdentifier,
            value: newValue,
            invalidationIdentity: liveViewNode.identity
          )
        }
      },
      resetToSeed: { [weak box] in
        guard let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) else {
          box?.setLocalFallbackValue(trueSeed)
          return
        }
        withTransientDormantStateSlot {
          liveViewNode.setStateSlot(
            slotIdentifier,
            value: trueSeed,
            invalidationIdentity: liveViewNode.identity
          )
        }
      }
    )
  }
}

extension GestureState: CaptureBindableDynamicProperty {
  package mutating func bindCapture(_ context: DynamicPropertyCaptureContext) {
    guard let slot = context.ownedSlot else {
      capturedLocation = nil
      return
    }
    if let existing = box.rememberedLocation(for: slot.owner, path: slot.path) {
      capturedLocation = existing
    } else {
      let location = makeLocation(owner: slot.owner, path: slot.path)
      box.remember(location, for: slot.owner, path: slot.path)
      capturedLocation = location
    }
  }
}

extension GestureState: DynamicProperty {
  /// Binds the gesture-state slot eagerly under the discovered-property
  /// path when the update pass reached this wrapper through a composed
  /// dynamic property (see `State.update(in:)`). Top-level wrappers keep lazy
  /// binding and their exact slot identity.
  public func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    let path = DynamicPropertyPathScope.current
    guard !path.isEmpty else {
      return .unchanged
    }
    guard
      ViewNodeContext.current != nil,
      let context = AuthoringContextStorage.current,
      let storageOwner = stateStorageOwner(for: context)
    else {
      return .unchanged
    }
    let location = makeLocation(owner: storageOwner, path: path)
    box.remember(
      location,
      for: storageOwner,
      path: path
    )
    return .unchanged
  }
}
