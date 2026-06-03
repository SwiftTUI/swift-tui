import SwiftTUICore
import Synchronization

@MainActor
package final class AuthoringOrdinalTracker {
  private(set) var nextOrdinal = 0
  private var frozen = false

  package init() {}

  /// Prevents new ordinal claims.  Existing cached ordinals on `StateBox`
  /// instances are unaffected — only first-time claims are blocked.
  package func freeze() {
    frozen = true
  }

  package func claimOrdinal() -> Int? {
    guard !frozen else { return nil }
    defer {
      nextOrdinal += 1
    }
    return nextOrdinal
  }
}

package enum StateSlotOrdinals {
  private static let authoredColumnBits = 16
  private static let changeModifierBase = -1_000_000
  private static let defaultFocusBase = -2_000_000
  private static let valueAnimationOrdinal = -3_000_000

  package static func authored(
    line: UInt,
    column: UInt
  ) -> Int {
    (Int(line) << authoredColumnBits) | Int(column)
  }

  package static func changeModifier(
    _ ordinal: Int
  ) -> Int {
    changeModifierBase - ordinal
  }

  package static func defaultFocus(
    _ ordinal: Int
  ) -> Int {
    defaultFocusBase - ordinal
  }

  package static var valueAnimation: Int {
    valueAnimationOrdinal
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
  private let slotOrdinal: Int
  private var seedValue: Value
  private var boundLocationsByOwner: [StateStorageOwner: DynamicStateLocation<Value>]
  private var retainedValuesByOwner: [StateStorageOwner: Value]

  init(
    seedValue: Value,
    slotOrdinal: Int
  ) {
    self.slotOrdinal = slotOrdinal
    self.seedValue = seedValue
    boundLocationsByOwner = [:]
    retainedValuesByOwner = [:]
  }

  deinit {
    StateGraphBindingRegistry.shared.forget(boxID: ObjectIdentifier(self))
  }

  func currentSeedValue() -> Value {
    seedValue
  }

  func updateSeedValue(_ newValue: Value) {
    seedValue = newValue
  }

  func remember(
    _ location: DynamicStateLocation<Value>,
    for owner: StateStorageOwner
  ) {
    boundLocationsByOwner[owner] = location
    if let graphID = owner.graphScope {
      StateGraphBindingRegistry.shared.remember(
        owner,
        for: ObjectIdentifier(self),
        graphID: graphID
      )
    }
  }

  func rememberedLocation(for owner: StateStorageOwner) -> DynamicStateLocation<Value>? {
    boundLocationsByOwner[owner]
  }

  func currentLocation(
    in viewGraphID: StateGraphScopeID
  ) -> DynamicStateLocation<Value>? {
    guard
      let owner = StateGraphBindingRegistry.shared.currentOwner(
        for: ObjectIdentifier(self),
        graphID: viewGraphID
      )
    else {
      return nil
    }
    return boundLocationsByOwner[owner]
  }

  func retainedValue(
    for owner: StateStorageOwner
  ) -> Value? {
    retainedValuesByOwner[owner]
  }

  func storeRetainedValue(
    _ value: Value,
    for owner: StateStorageOwner
  ) {
    retainedValuesByOwner[owner] = value
  }

  var currentOrdinal: Int {
    slotOrdinal
  }
}

private final class StateGraphBindingRegistry: Sendable {
  static let shared = StateGraphBindingRegistry()

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

@propertyWrapper
@MainActor
/// Local value storage owned by a view identity within a runtime graph.
///
/// `@State` persistence is keyed by the view's identity path plus source
/// location within that view. Interactive runtime callbacks, bindings, and
/// local actions use a graph-scoped storage identity so reusing the same view
/// value in a different live graph does not leak mutations across sessions.
///
/// Snapshot-style renders without an invalidating runtime graph retain the
/// same-instance fallback used by one-shot tests and previews: if you reuse the
/// same stateful view instance with `DefaultRenderer`, imperative writes can
/// feed a later snapshot of that same instance.
public struct State<Value> {
  private let box: StateBox<Value>

  /// Creates state with the supplied initial wrapped value.
  public init(
    wrappedValue: Value,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: wrappedValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      )
    )
  }

  public init(
    initialValue: Value,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: initialValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      )
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
    return activeLocation()?.binding
      ?? Binding(
        mainActorGet: { wrappedValue },
        set: { wrappedValue = $0 }
      )
  }

  private func activeLocation() -> DynamicStateLocation<Value>? {
    guard let context = AuthoringContextStorage.current else {
      return nil
    }
    guard let storageOwner = stateStorageOwner(for: context) else {
      return nil
    }

    if ViewNodeContext.current != nil {
      let location = makeLocation(
        for: context,
        storageOwner: storageOwner
      )
      box.remember(
        location,
        for: storageOwner
      )
      _ = location.getValue()
      return location
    }

    if let location = box.rememberedLocation(for: storageOwner) {
      return location
    }

    if let viewGraphID = storageOwner.graphScope,
      let location = box.currentLocation(in: viewGraphID)
    {
      return location
    }
    return nil
  }

  private func makeLocation(
    for context: AuthoringContext,
    storageOwner: StateStorageOwner
  ) -> DynamicStateLocation<Value> {
    let ordinal = box.currentOrdinal
    let retainedSeed =
      box.retainedValue(for: storageOwner) ?? box.currentSeedValue()

    if let viewNode = context.viewNode {
      return DynamicStateLocation(
        getValue: { [weak viewNode, weak box] in
          guard let viewNode else {
            if let retainedValue = box?.retainedValue(for: storageOwner) {
              return retainedValue
            }
            return retainedSeed
          }
          let liveViewNode =
            viewNode.ownerGraph?.nodeForViewNodeID(viewNode.viewNodeID) ?? viewNode
          return liveViewNode.stateSlot(
            ordinal: ordinal,
            seed: retainedSeed
          )
        },
        setValue: { [weak viewNode, weak box] newValue in
          if let viewNode {
            let liveViewNode =
              viewNode.ownerGraph?.nodeForViewNodeID(viewNode.viewNodeID) ?? viewNode
            liveViewNode.setStateSlot(
              ordinal: ordinal,
              value: newValue,
              invalidationIdentity: context.viewIdentity
            )
            box?.updateSeedValue(newValue)
            box?.storeRetainedValue(newValue, for: storageOwner)
          } else {
            box?.updateSeedValue(newValue)
            box?.storeRetainedValue(newValue, for: storageOwner)
          }
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
    if let authoringContext = currentAuthoringContext() {
      let body = context.trackingObservableAccess {
        makeBody()
      }
      return withAuthoringContext(authoringContext) {
        return body.resolveElements(in: context)
      }
    }

    let authoringContext = makeAuthoringContext(for: context)
    return withAuthoringContext(authoringContext) {
      let body = context.trackingObservableAccess {
        makeBody()
      }
      return body.resolveElements(in: context)
    }
  }
}
