public import SwiftTUICore

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
  private static let collectionScrollAnchorBase = -8_000_000
  private static let tabDormantArchiveBase = -9_000_000

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

  package static var collectionScrollAnchor: Int {
    collectionScrollAnchorBase
  }

  package static var tabDormantArchive: Int {
    tabDormantArchiveBase
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
    if boundLocationsByOwner[owner] == nil {
      pruneRetiredBoundLocations()
    }
    boundLocationsByOwner[owner] = location
  }

  func rememberedLocation(for owner: StateStorageOwner) -> DynamicStateLocation<Value>? {
    return boundLocationsByOwner[owner]
  }

  /// Finds this box's nearest already-bound owner on the exact live dispatch
  /// owner's parent chain. This is the imperative callback seam for an action
  /// closure authored by an ancestor and forwarded through arbitrary custom
  /// views before reaching a control: each captured StateBox selects its own
  /// bound ancestor rather than minting storage on the forwarding leaf.
  ///
  /// The search is deliberately handle- and relation-only. The registry first
  /// resolves the exact graph/lifetime pair, then the walk follows only that
  /// node's live parents. It never scans graph identities, sibling branches,
  /// raw node IDs, or a retired owner's retained object.
  func rememberedAncestorLocation(
    for dispatchOwner: StateStorageOwner
  ) -> DynamicStateLocation<Value>? {
    guard let dispatchNode = LiveViewGraphRegistry.node(for: dispatchOwner) else {
      return nil
    }
    let dispatchGraph = dispatchNode.ownerGraph
    var ancestor = dispatchNode.parent
    while let candidate = ancestor {
      guard candidate.ownerGraph === dispatchGraph else {
        return nil
      }
      if let candidateOwner = candidate.stateOwnerHandle,
        let location = boundLocationsByOwner[candidateOwner]
      {
        return location
      }
      ancestor = candidate.parent
    }
    return nil
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

  /// Releases graph-location closures for owner lifetimes the live registry can
  /// no longer resolve. This scans only this box's previously bound handles;
  /// it never searches a graph or substitutes identity/raw node addressing.
  /// A separately retained `Binding` owns its location closure directly, and
  /// `retainedValuesByOwner` intentionally remains available to that stale
  /// binding after retirement.
  private func pruneRetiredBoundLocations() {
    let retiredOwners = boundLocationsByOwner.keys.filter {
      LiveViewGraphRegistry.node(for: $0) == nil
    }
    for owner in retiredOwners {
      boundLocationsByOwner.removeValue(forKey: owner)
    }
  }

  var currentOrdinal: Int {
    slotOrdinal
  }

  #if DEBUG
    var rememberedOwnerCount: Int {
      boundLocationsByOwner.count
    }
  #endif
}

@propertyWrapper
@MainActor
/// Local value storage owned by a view identity within a runtime graph.
///
/// The view identity path and source location within the view identify persistent `@State` storage.
/// Interactive runtime callbacks, bindings, and local actions use a graph-scoped storage identity.
/// Thus, reuse of the same view value in another live graph does not leak mutations between sessions.
///
/// Construction-time, graphless accesses retain the wrapper's local seed.
/// Once graph-backed, mutations remain scoped to the exact graph-owner lifetime;
/// a later snapshot or mount never inherits a retired owner's fallback value.
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

  #if DEBUG
    package var rememberedOwnerCountForTesting: Int {
      box.rememberedOwnerCount
    }
  #endif

  private func activeLocation() -> DynamicStateLocation<Value>? {
    guard let context = AuthoringContextStorage.current else {
      return nil
    }
    guard let storageOwner = stateStorageOwner(for: context) else {
      return nil
    }

    if ViewNodeContext.current != nil {
      // The update pass refreshes both top-level and path-qualified bindings
      // immediately before body evaluation. Reuse that exact binding: making
      // another unqualified location here would duplicate closure/claim work,
      // and would erase a composed wrapper's qualified slot identity.
      if let refreshed = box.rememberedLocation(for: storageOwner) {
        return refreshed
      }
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

    if let location = box.rememberedAncestorLocation(for: storageOwner) {
      return location
    }

    // A legacy/undiscovered imperative path may arrive without an update-pass
    // binding. Preserve the exact captured owner handle in a location whose
    // closures revalidate liveness on every access; never substitute identity
    // or raw node addressing.
    let location = makeImperativeLocation(storageOwner: storageOwner)
    box.remember(
      location,
      for: storageOwner
    )
    return location
  }

  private func makeLocation(
    for context: AuthoringContext,
    storageOwner: StateStorageOwner,
    path: StateSlotPath = .root
  ) -> DynamicStateLocation<Value> {
    if let viewNode = liveAuthoringOwnerNode(stateOwnerHandle: storageOwner) {
      if ViewNodeContext.current != nil {
        // Resolve-time claim bookkeeping: a second distinct box claiming
        // this slot identity in one evaluation is the silent-sharing
        // signature (see `ViewNode.recordStateSlotClaim`).
        viewNode.recordStateSlotClaim(
          StateSlotIdentifier(ordinal: box.currentOrdinal, path: path),
          claimant: ObjectIdentifier(box)
        )
      }
    }
    return graphSlotLocation(
      storageOwner: storageOwner,
      path: path
    )
  }

  /// Builds an exact-handle location for imperative access outside a resolve
  /// pass. Construction does not require the node to be live: each read/write
  /// resolves the owner handle again, and a retired owner uses only its own
  /// retained value (then the authored seed), never another graph or identity.
  private func makeImperativeLocation(
    storageOwner: StateStorageOwner
  ) -> DynamicStateLocation<Value> {
    return graphSlotLocation(
      storageOwner: storageOwner
    )
  }

  /// A location that reads and writes the graph slot owned by `viewNode`. The
  /// closures re-resolve the live node from its graph on every access, so a
  /// location built once stays valid across reuse, and degrade to the retained
  /// value (then the seed) if the node is gone.
  private func graphSlotLocation(
    storageOwner: StateStorageOwner,
    path: StateSlotPath = .root
  ) -> DynamicStateLocation<Value> {
    let slotIdentifier = StateSlotIdentifier(ordinal: box.currentOrdinal, path: path)
    // Fresh slots always seed from the authored initial value. A retained
    // per-owner value serves only the node-gone read fallback below — seeding
    // a new slot from carried mutation would resurrect state across committed
    // removal and leak writes into replacement identities.
    let authoredSeed = box.currentSeedValue()
    return DynamicStateLocation(
      getValue: { [weak box] in
        guard let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) else {
          if let retainedValue = box?.retainedValue(for: storageOwner) {
            return retainedValue
          }
          return authoredSeed
        }
        return withPersistentDormantStateSlot {
          liveViewNode.stateSlot(
            slotIdentifier,
            seed: authoredSeed
          )
        }
      },
      setValue: { [weak box] newValue in
        // Graph-backed writes stay owner-scoped: the slot holds the mutation
        // and the per-owner retained value backs the node-gone read fallback.
        // Never mirror a graph-backed write into the box-global seed: even a
        // no-invalidator snapshot graph is a distinct owner lifetime, and
        // carrying its mutation into a later mount would cross that boundary.
        if let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) {
          withPersistentDormantStateSlot {
            liveViewNode.setStateSlot(
              slotIdentifier,
              value: newValue,
              invalidationIdentity: liveViewNode.identity
            )
          }
          box?.storeRetainedValue(newValue, for: storageOwner)
        } else {
          box?.storeRetainedValue(newValue, for: storageOwner)
        }
      }
    )
  }
}

extension State: DynamicProperty {
  /// Binds the graph location during the dynamic-property update pass without
  /// reading or materializing the slot. A top-level wrapper keeps the legacy
  /// unqualified slot identity, but remembering its exact authored owner here
  /// lets a forwarded imperative action route back from a descendant even when
  /// the owning body never read or projected the state. Composed wrappers are
  /// qualified by their ambient path so distinct instances cannot share slots.
  public func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    let path = DynamicPropertyPathScope.current
    guard
      ViewNodeContext.current != nil,
      let context = AuthoringContextStorage.current,
      let storageOwner = stateStorageOwner(for: context)
    else {
      return .unchanged
    }
    let location = makeLocation(
      for: context,
      storageOwner: storageOwner,
      path: path
    )
    box.remember(
      location,
      for: storageOwner
    )
    return .unchanged
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
      // The update pass runs under the same ambient scope the body closure
      // observes (the ambient-wins rule above): wrapper bindings made during
      // update(in:) and during the body must name the same owner.
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
