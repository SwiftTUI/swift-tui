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
  private static let tabFocusedIndexBase = -4_000_000
  private static let tabOverflowMenuExpandedBase = -5_000_000
  private static let navigationDestinationActivationBase = -6_000_000
  private static let tabOptionSignatureBase = -7_000_000

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

  package static func valueAnimation(
    _ ordinal: Int
  ) -> Int {
    valueAnimationOrdinal - ordinal
  }

  package static var tabFocusedIndex: Int {
    tabFocusedIndexBase
  }

  package static var tabOverflowMenuExpanded: Int {
    tabOverflowMenuExpandedBase
  }

  package static var tabOptionSignature: Int {
    tabOptionSignatureBase
  }

  package static func navigationDestinationActivation(
    _ ordinal: Int
  ) -> Int {
    navigationDestinationActivationBase - ordinal
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
      // Reader-attributed: projecting a `$binding` records nothing here; only a
      // genuine `wrappedValue` read records, attributed to its actual reader. So
      // a bare projection no longer re-resolves the owner's whole subtree.
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

    // Outside a resolve pass with no remembered location: the body never read
    // this property during resolve, so no box was ever taught to reach the
    // graph slot. Recover the live owner node from the captured graph scope so
    // imperative reads and writes (a `.task` loop, a gesture callback) land on
    // the graph-backed slot instead of a stale per-box seed. Remembered so a
    // later imperative access on this same box short-circuits here.
    if let location = makeImperativeLocation(
      for: context,
      storageOwner: storageOwner
    ) {
      box.remember(
        location,
        for: storageOwner
      )
      return location
    }
    return nil
  }

  private func makeLocation(
    for context: AuthoringContext,
    storageOwner: StateStorageOwner
  ) -> DynamicStateLocation<Value> {
    // Captured authoring snapshots keep the owner node ID but drop the
    // ViewNode reference. During a resolve pass, recover the live owner so
    // scoped subtrees do not replace graph-backed state with seed storage.
    let resolvedViewNode =
      context.viewNode
      ?? liveOwnerNode(
        ownerNodeID: context.ownerNodeID,
        stateGraphScope: context.stateGraphScope
      )

    if let viewNode = resolvedViewNode {
      return graphSlotLocation(
        viewNode: viewNode,
        storageOwner: storageOwner,
        invalidationIdentity: context.viewIdentity
      )
    }

    return DynamicStateLocation(
      getValue: { box.currentSeedValue() },
      setValue: { newValue in
        box.updateSeedValue(newValue)
      }
    )
  }

  /// Builds a graph-backed location for an imperative access (a `.task` loop, a
  /// gesture callback) that ran outside any resolve pass. Returns `nil` when the
  /// captured scope's graph is gone or the owner node cannot be found, so the
  /// caller falls back to the per-box seed exactly as it did before — the
  /// graph-scoped fallback never substitutes a different live graph's state.
  private func makeImperativeLocation(
    for context: AuthoringContext,
    storageOwner: StateStorageOwner
  ) -> DynamicStateLocation<Value>? {
    guard
      let viewNode = liveOwnerNode(
        ownerNodeID: context.ownerNodeID,
        stateGraphScope: context.stateGraphScope,
        ownerIdentity: context.viewIdentity
      )
    else {
      return nil
    }
    return graphSlotLocation(
      viewNode: viewNode,
      storageOwner: storageOwner,
      invalidationIdentity: context.viewIdentity
    )
  }

  /// A location that reads and writes the graph slot owned by `viewNode`. The
  /// closures re-resolve the live node from its graph on every access, so a
  /// location built once stays valid across reuse, and degrade to the retained
  /// value (then the seed) if the node is gone.
  private func graphSlotLocation(
    viewNode: SwiftTUICore.ViewNode,
    storageOwner: StateStorageOwner,
    invalidationIdentity: Identity
  ) -> DynamicStateLocation<Value> {
    let ordinal = box.currentOrdinal
    // Fresh slots always seed from the authored initial value. A retained
    // per-owner value serves only the node-gone read fallback below — seeding
    // a new slot from carried mutation would resurrect state across committed
    // removal and leak writes into replacement identities.
    let authoredSeed = box.currentSeedValue()
    // Access-time re-resolution is identity-aware: if the registration-time
    // node was displaced by a fresh mint at the same identity (a lazy-tab
    // revisit, a mid-frame eviction), the closures follow the identity to the
    // live occupant instead of writing the orphaned node's slots.
    return DynamicStateLocation(
      getValue: { [weak viewNode, weak box] in
        guard let viewNode else {
          if let retainedValue = box?.retainedValue(for: storageOwner) {
            return retainedValue
          }
          return authoredSeed
        }
        let liveViewNode =
          viewNode.ownerGraph?.liveStateOwnerNode(
            registeredOwner: viewNode.viewNodeID,
            identity: invalidationIdentity
          ) ?? viewNode
        return liveViewNode.stateSlot(
          ordinal: ordinal,
          seed: authoredSeed
        )
      },
      setValue: { [weak viewNode, weak box] newValue in
        // Graph-backed writes stay owner-scoped: the slot holds the mutation
        // and the per-owner retained value backs the node-gone read fallback.
        // Live (invalidator-backed) graphs never mirror writes into the
        // box-global seed — that leaked one owner's mutation into every
        // future owner seeded from the same box. No-invalidator snapshot
        // graphs (one-shot `DefaultRenderer` renders) keep the same-instance
        // seed fallback so an imperative write feeds a later snapshot of the
        // same view value.
        if let viewNode {
          let liveViewNode =
            viewNode.ownerGraph?.liveStateOwnerNode(
              registeredOwner: viewNode.viewNodeID,
              identity: invalidationIdentity
            ) ?? viewNode
          liveViewNode.setStateSlot(
            ordinal: ordinal,
            value: newValue,
            invalidationIdentity: invalidationIdentity
          )
          if liveViewNode.invalidator == nil {
            box?.updateSeedValue(newValue)
          }
          box?.storeRetainedValue(newValue, for: storageOwner)
        } else {
          box?.storeRetainedValue(newValue, for: storageOwner)
        }
      }
    )
  }

  private func liveOwnerNode(
    ownerNodeID: ViewNodeID?,
    stateGraphScope: StateGraphScopeID?,
    ownerIdentity: Identity? = nil
  ) -> SwiftTUICore.ViewNode? {
    liveAuthoringOwnerNode(
      ownerNodeID: ownerNodeID,
      stateGraphScope: stateGraphScope,
      ownerIdentity: ownerIdentity
    )
  }
}

extension View {
  @MainActor
  func resolveBody(
    in context: ResolveContext,
    body makeBody: () -> Body
  ) -> [ResolvedNode] {
    // Ambient-wins is load-bearing here: capture-hosted content (tab bodies,
    // scoped payloads, dirty-frontier evaluator re-runs) deliberately
    // evaluates under a reinstalled enclosing scope, and re-scoping at this
    // boundary detaches those bodies' captured @State from their true owner
    // (verified by ButtonFocusStabilityTests' TabView delete regression).
    // The multi-mount aliasing this would otherwise allow (one view VALUE
    // mounted at several identities sharing one state owner) is handled at
    // the chain-content seam instead: an identity modifier's per-mount
    // rebase survives the inner chains' capture reinstall via
    // `AuthoringContext.rebasedFromOwnerNodeID` (see
    // `ModifierContentInputs.applyAuthoringContext`).
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
