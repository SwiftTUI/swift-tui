public import SwiftTUICore
import Synchronization

/// The typed location a `GestureStateBox` binds to inside a running
/// resolve pass. Parallels `DynamicStateLocation` in State.swift and
/// the private `FocusStateLocation` in FocusState.swift.
@MainActor
private struct GestureStateLocation<Value> {
  var getValue: @MainActor () -> Value
  var setValue: @MainActor (Value) -> Void
  var resetToSeed: @MainActor () -> Void
}

/// Storage for a `@GestureState` cell. Its structure mirrors `StateBox`.
/// A slot-ordinal-keyed store contains a seed.
/// It remembers a ViewNode-scoped or graph-scoped location when bound.
/// A local fallback value supports tests and reads during construction.
@MainActor
public final class GestureStateBox<Value> {
  /// A remembered location plus how it was bound; a path-qualified binding
  /// (made by the dynamic-property update pass) wins over access-time
  /// re-binding, which has no ambient path (see `StateBox.BoundLocation`).
  private struct BoundLocation {
    var location: GestureStateLocation<Value>
    var isPathQualified: Bool
  }

  public let slotOrdinal: Int
  private let seed: Value
  private var localValue: Value
  private var boundLocationsByOwner: [StateStorageOwner: BoundLocation] = [:]
  /// Builds the transaction governing a genuine end-of-gesture reset from
  /// the value being reset. Nil for the plain initializers — their resets
  /// snap. Resolve-time resets (recognizer teardown, registry drain) never
  /// consult it; see ``resetToSeedApplyingResetTransaction()``.
  private let resetTransactionProvider: (@MainActor (Value) -> Transaction)?

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

  deinit {
    GestureStateGraphBindingRegistry.shared.forget(boxID: ObjectIdentifier(self))
  }

  /// The true initial seed value -- used by `makeLocation` to capture
  /// the correct reset target even when the local value has been mutated.
  fileprivate var seedValue: Value { seed }

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
  /// resolve-time paths — recognizer teardown on replacement and the
  /// registry's subtree drain — which must never animate: `.gesture(_:)`
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
    pathQualified: Bool = false
  ) {
    boundLocationsByOwner[owner] = BoundLocation(
      location: location,
      isPathQualified: pathQualified
    )
    if let graphID = owner.graphScope {
      GestureStateGraphBindingRegistry.shared.remember(
        owner,
        for: ObjectIdentifier(self),
        graphID: graphID
      )
    }
  }

  fileprivate func rememberedLocation(
    for owner: StateStorageOwner
  ) -> GestureStateLocation<Value>? {
    boundLocationsByOwner[owner]?.location
  }

  fileprivate func rememberedPathQualifiedLocation(
    for owner: StateStorageOwner
  ) -> GestureStateLocation<Value>? {
    guard let bound = boundLocationsByOwner[owner], bound.isPathQualified else {
      return nil
    }
    return bound.location
  }

  fileprivate func currentLocation(
    in viewGraphID: StateGraphScopeID
  ) -> GestureStateLocation<Value>? {
    guard
      let owner = GestureStateGraphBindingRegistry.shared.currentOwner(
        for: ObjectIdentifier(self),
        graphID: viewGraphID
      )
    else {
      return nil
    }
    return boundLocationsByOwner[owner]?.location
  }

  private func scopedLocation() -> GestureStateLocation<Value>? {
    guard let context = AuthoringContextStorage.current else {
      return nil
    }
    guard let storageOwner = stateStorageOwner(for: context) else {
      return nil
    }
    if let existing = rememberedLocation(for: storageOwner) {
      return existing
    }
    if let graphID = storageOwner.graphScope {
      return currentLocation(in: graphID)
    }
    return nil
  }

  /// Produces a type-erased binding for registration with the runtime.
  public func eraseToAnyBinding() -> AnyGestureStateBinding {
    AnyGestureStateBinding(
      valueType: Value.self,
      setValue: { value in self.setValue(value) },
      reset: { self.resetToSeed() }
    )
  }

}

private final class GestureStateGraphBindingRegistry: Sendable {
  static let shared = GestureStateGraphBindingRegistry()

  private let currentOwnerByBoxAndGraph = Mutex<
    [ObjectIdentifier: [StateGraphScopeID: StateStorageOwner]]
  >([:])

  func remember(
    _ owner: StateStorageOwner,
    for boxID: ObjectIdentifier,
    graphID: StateGraphScopeID
  ) {
    currentOwnerByBoxAndGraph.withLock { owners in
      owners[boxID, default: [:]][graphID] = owner
    }
  }

  func currentOwner(
    for boxID: ObjectIdentifier,
    graphID: StateGraphScopeID
  ) -> StateStorageOwner? {
    currentOwnerByBoxAndGraph.withLock { owners in
      owners[boxID]?[graphID]
    }
  }

  func forget(boxID: ObjectIdentifier) {
    currentOwnerByBoxAndGraph.withLock { owners in
      owners[boxID] = nil
    }
  }
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
/// Bound locations are graph-scoped for imperative gesture updates.
/// Thus, a reused gesture-state box starts from the seed and reset lifecycle of its current render graph.
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

  /// Creates gesture state whose end-of-gesture reset applies
  /// `resetTransaction` — typically an animation for the snap-back.
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
      let location = makeLocation(for: context)
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
    if let graphID = storageOwner.graphScope {
      return box.currentLocation(in: graphID)
    }
    return nil
  }

  private func makeLocation(
    for context: AuthoringContext,
    path: StateSlotPath = .root
  ) -> GestureStateLocation<Value> {
    let slotIdentifier = StateSlotIdentifier(ordinal: box.slotOrdinal, path: path)
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

    if ViewNodeContext.current != nil {
      // Resolve-time claim bookkeeping (see `ViewNode.recordStateSlotClaim`).
      viewNode.recordStateSlotClaim(
        slotIdentifier,
        claimant: ObjectIdentifier(box)
      )
    }

    // Access-time re-resolution is identity-aware, mirroring `@State`
    // (F135): if the registration-time node was displaced by a fresh mint
    // at the same identity (a lazy-tab revisit, a mid-frame eviction), the
    // closures follow the identity to the live occupant. The previous
    // node-ID-only lookup kept recognizer updates writing the orphaned
    // node's slots. Weak capture matches `@State`: a dead registration
    // falls back to the local box.
    let invalidationIdentity = context.viewIdentity
    return GestureStateLocation(
      getValue: { [weak viewNode, weak box] in
        guard let viewNode else {
          return box?.currentValue() ?? trueSeed
        }
        let liveViewNode =
          viewNode.ownerGraph?.liveStateOwnerNode(
            registeredOwner: viewNode.viewNodeID,
            identity: invalidationIdentity
          ) ?? viewNode
        return liveViewNode.stateSlot(slotIdentifier, seed: trueSeed)
      },
      setValue: { [weak viewNode, weak box] newValue in
        guard let viewNode else {
          box?.setValue(newValue)
          return
        }
        let liveViewNode =
          viewNode.ownerGraph?.liveStateOwnerNode(
            registeredOwner: viewNode.viewNodeID,
            identity: invalidationIdentity
          ) ?? viewNode
        liveViewNode.setStateSlot(
          slotIdentifier,
          value: newValue,
          invalidationIdentity: invalidationIdentity
        )
      },
      resetToSeed: { [weak viewNode, weak box] in
        guard let viewNode else {
          box?.setValue(trueSeed)
          return
        }
        let liveViewNode =
          viewNode.ownerGraph?.liveStateOwnerNode(
            registeredOwner: viewNode.viewNodeID,
            identity: invalidationIdentity
          ) ?? viewNode
        liveViewNode.setStateSlot(
          slotIdentifier,
          value: trueSeed,
          invalidationIdentity: invalidationIdentity
        )
      }
    )
  }
}

extension GestureState: DynamicProperty {
  /// Binds the gesture-state slot eagerly under the discovered-property
  /// path when the update pass reached this wrapper through a composed
  /// dynamic property (see `State.update()`). Top-level wrappers keep lazy
  /// binding and their exact slot identity.
  public mutating func update() {
    let path = DynamicPropertyPathScope.current
    guard !path.isEmpty else {
      return
    }
    guard
      ViewNodeContext.current != nil,
      let context = AuthoringContextStorage.current,
      let storageOwner = stateStorageOwner(for: context)
    else {
      return
    }
    let location = makeLocation(for: context, path: path)
    box.remember(
      location,
      for: storageOwner,
      pathQualified: true
    )
  }
}
