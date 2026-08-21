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
  /// Latches once any owner binds a location. Distinguishes a pre-mount
  /// seed read (expected: the box has only its seed) from an imperative
  /// access that lost its live slot and silently degraded to the seed —
  /// the `state.imperativeSeedFallback` warning fires only for the latter.
  private(set) var hasEverBeenGraphBound = false

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
    hasEverBeenGraphBound = true
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

  /// This box's only live binding, when exactly one remains.
  ///
  /// ``rememberedAncestorLocation(for:)`` walks the dispatch node's live
  /// parent chain, which covers an action closure forwarded down a single
  /// subtree. It cannot cover a closure forwarded into a *detached* subtree —
  /// `.background`, `.overlay`, and presentation layers mount content whose
  /// ancestry never reaches the authoring view — so the walk misses even
  /// though the author's slot is bound and live.
  ///
  /// Minting fresh storage on the foreign dispatch owner is never the right
  /// answer for an already-bound box: it silently forks the state, so the
  /// author's reads keep seeing the authored seed while writes land in a
  /// second slot nobody observes. A single remaining binding is unambiguous —
  /// it is the author's own slot — so prefer it. Boxes shared across several
  /// live owners stay ambiguous and fall through to the imperative path,
  /// which keeps its exact-handle behaviour.
  func soleRememberedLocation() -> DynamicStateLocation<Value>? {
    pruneRetiredBoundLocations()
    guard boundLocationsByOwner.count == 1 else {
      return nil
    }
    return boundLocationsByOwner.values.first
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
  /// The owner this copy was bound to by the capture-bind pass (plan
  /// 2026-08-20-001) — written in place into the exact container copy body
  /// evaluation consumes, so closures created in the body carry their state
  /// owner. `.unbound` until a bind pass runs; `.conflicted` latches a
  /// shared class instance mounted at several identities back onto the
  /// ambient ladder. Per-copy by struct value semantics: distinct mounts
  /// bind distinct copies.
  private var capture: StateCaptureSlot = .unbound

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
      if let location = activeLocation() {
        return location.getValue()
      }
      if box.hasEverBeenGraphBound, ViewNodeContext.current == nil {
        reportImperativeSeedFallback(
          slotOrdinal: box.currentOrdinal,
          reason: "no live state owner could be resolved from the dispatch context"
        )
      }
      return box.currentSeedValue()
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

    package var captureSlotForTesting: StateCaptureSlot {
      capture
    }
  #endif

  private func activeLocation() -> DynamicStateLocation<Value>? {
    if ViewNodeContext.current != nil {
      guard let context = AuthoringContextStorage.current,
        let storageOwner = stateStorageOwner(for: context)
      else {
        return nil
      }
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

    // Imperative access. The carried capture is the exact owner the body
    // that created this closure was evaluated against — more specific than
    // any ambient dispatch context — so it serves first. Only bind-pass
    // evaluations produce `.bound`, which keeps this rung inert whenever the
    // capture-binding gate is off.
    if let location = captureLocation() {
      return location
    }

    guard let context = AuthoringContextStorage.current,
      let storageOwner = stateStorageOwner(for: context)
    else {
      return nil
    }

    if let location = box.rememberedLocation(for: storageOwner) {
      StateCaptureCensus.record(.ladderExactOwner)
      return location
    }

    if let location = box.rememberedAncestorLocation(for: storageOwner) {
      StateCaptureCensus.record(.ladderAncestorWalk)
      return location
    }

    // The ancestor walk cannot see across a detached subtree: `.background`,
    // `.overlay`, and presentation layers dispatch from nodes whose live
    // ancestry never reaches the authoring view. An already-bound box with a
    // single live owner is unambiguous, so use that binding rather than
    // minting a second slot on the foreign dispatch owner below — which would
    // fork the state and make the author's write a silent no-op.
    if let location = box.soleRememberedLocation() {
      StateCaptureCensus.record(.ladderSoleBinding)
      return location
    }

    // A legacy/undiscovered imperative path may arrive without an update-pass
    // binding. Preserve the exact captured owner handle in a location whose
    // closures revalidate liveness on every access; never substitute identity
    // or raw node addressing.
    StateCaptureCensus.record(.ladderMinted)
    let location = makeImperativeLocation(storageOwner: storageOwner)
    box.remember(
      location,
      for: storageOwner
    )
    return location
  }

  /// Rung 2 of imperative resolution: route through the capture written by
  /// the bind pass. A live captured owner serves directly; a dead one takes
  /// the fire-time identity refresh — map the capture's resolve identity
  /// through its own graph scope's live identity index to the current
  /// occupant node (the ratified focused-values category: dispatch context
  /// is runtime state). The refresh never crosses graph scopes and requires
  /// a live occupant, so committed removal still falls through to the
  /// ambient ladder; it re-addresses dispatch, never mints storage on a
  /// foreign graph.
  private func captureLocation() -> DynamicStateLocation<Value>? {
    guard case .bound(let binding) = capture else {
      return nil
    }
    if LiveViewGraphRegistry.node(for: binding.owner) != nil {
      StateCaptureCensus.record(.captureHit)
      return location(for: binding.owner, path: binding.path)
    }
    if let liveGraph = LiveViewGraphRegistry.graph(for: binding.graphScope),
      let occupant = liveGraph.nodeForIdentity(binding.identity),
      let refreshedOwner = occupant.stateOwnerHandle
    {
      StateCaptureCensus.record(.captureRefreshedOwner)
      return location(for: refreshedOwner, path: binding.path)
    }
    StateCaptureCensus.record(.captureMiss)
    if StateCaptureBindingConfiguration.isEnabled {
      SoundnessProbeConfiguration.recordStateCaptureMissViolation(
        "state-capture-miss: owner dead and refresh failed for \(binding.identity)"
      )
    }
    return nil
  }

  private func location(
    for storageOwner: StateStorageOwner,
    path: StateSlotPath
  ) -> DynamicStateLocation<Value> {
    if let remembered = box.rememberedLocation(for: storageOwner) {
      return remembered
    }
    let location = graphSlotLocation(
      storageOwner: storageOwner,
      path: path
    )
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
          claimant: ObjectIdentifier(box),
          wrapperDescription: "@State<\(Value.self)>"
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
    let slotOrdinal = box.currentOrdinal
    return DynamicStateLocation(
      getValue: { [weak box] in
        guard let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) else {
          if let retainedValue = box?.retainedValue(for: storageOwner) {
            return retainedValue
          }
          if ViewNodeContext.current == nil {
            reportImperativeSeedFallback(
              slotOrdinal: slotOrdinal,
              reason: "the state's owning node is no longer live and holds no retained value"
            )
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
        // A live (invalidator-backed) graph never mirrors a write into the
        // box-global seed — that leaked one owner's mutation into every future
        // owner seeded from the same box.
        //
        // A no-invalidator graph is the one-shot `DefaultRenderer` snapshot
        // path, and it is not a mount lifetime at all: the graph is discarded
        // when `render` returns, so there is no later owner for a seed write
        // to leak into. Its only reader is a subsequent snapshot of the same
        // view value, which is exactly the same-instance continuity an
        // imperative dispatch between two renders depends on. Without this,
        // such a write lands in a graph that no longer exists and the next
        // render silently re-seeds from the authored value.
        if let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) {
          withPersistentDormantStateSlot {
            liveViewNode.setStateSlot(
              slotIdentifier,
              value: newValue,
              invalidationIdentity: liveViewNode.identity
            )
          }
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
}

/// Records the silent-corruption signature as a diagnosable warning: an
/// imperative `@State` access on a box that once had a live graph slot
/// bottomed out at the authored seed. Every dispatch surface that loses its
/// owner (identity churn between registration and fire, a cleared ambient
/// context) ends here, and the read silently returns the *initial* value —
/// the warning is what makes that observable. Dispatch-time issues buffer in
/// `ImperativeRuntimeIssueQueue` and surface at the next frame head.
@MainActor
private func reportImperativeSeedFallback(slotOrdinal: Int, reason: String) {
  StateCaptureCensus.record(.seedFallback)
  if StateCaptureBindingConfiguration.isEnabled {
    // Oracle promotion (plan 2026-08-20-001 Stage 3): with captures live,
    // a seed fallback is a soundness failure, not merely a loud diagnostic.
    SoundnessProbeConfiguration.recordStateSeedFallbackViolation(
      "state-seed-fallback: slot \(slotOrdinal): \(reason)"
    )
  }
  var message =
    "An imperative @State access fell back to the authored initial value: "
    + reason + ". The closure observed the seed, not the last written value."
  if slotOrdinal >= 0 {
    message +=
      " The state is declared near line \(slotOrdinal >> 16), column \(slotOrdinal & 0xFFFF)."
  }
  ImperativeRuntimeIssueQueue.record(
    RuntimeIssue(
      severity: .warning,
      code: "state.imperativeSeedFallback",
      message: message,
      source: "@State"
    )
  )
}

extension State: CaptureBindableDynamicProperty {
  /// Writes the bind pass's owner into this copy. Struct copies are private
  /// to their mount, so overwriting is always correct there. A shared class
  /// instance mounted at several live identities would collapse every mount
  /// onto the last writer — that shape demotes to `.conflicted` (permanent
  /// ambient-ladder fallback for the instance) instead. Overwriting a dead
  /// owner is a normal re-bind: identity churn and teardown must not latch.
  package mutating func bindCapture(
    _ binding: StateCaptureBinding,
    sharedMutableContainer: Bool
  ) {
    switch capture {
    case .conflicted:
      return
    case .bound(let existing):
      if sharedMutableContainer,
        existing.owner != binding.owner,
        LiveViewGraphRegistry.node(for: existing.owner) != nil
      {
        capture = .conflicted
        StateCaptureCensus.record(.classConflictDemoted)
        return
      }
      capture = .bound(binding)
    case .unbound:
      capture = .bound(binding)
    }
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
