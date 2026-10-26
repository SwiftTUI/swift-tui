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
  package static let pickerMenuExpansion = -10_000_000
  package static let pickerSelectionTokens = pickerMenuExpansion - 1
  package static let capturedSubviewArchive = -11_000_000
  package static let capturedSubviewLocator = capturedSubviewArchive - 1
  package static let menuExpansion = -12_000_000
  package static let tableKeyboardSelection = -13_000_000
  package static let tabAccessibilityTokens = -14_000_000
  package static let collectionAccessibilityReview = -15_000_000

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
  var bindingSourceID: AnyID
  var bindingDeclarationID: AnyID
  var getValue: @MainActor () -> Value
  var setValue: @MainActor (Value) -> Void
  var valueIdentity: @MainActor @Sendable () -> StateValueIdentity?
  var ownerKind: StateOwnerKind

  var binding: Binding<Value> {
    var binding = Binding(
      mainActorGet: getValue,
      set: setValue
    )
    binding.valueIdentity = valueIdentity
    binding.bindingSourceID = bindingSourceID
    binding.bindingDeclarationID = bindingDeclarationID
    return binding
  }
}

/// Whether a location's owner is a snapshot owner: its node evaluates without
/// an invalidator, the one-shot `DefaultRenderer` path, which is not a mount
/// lifetime. The answer is read from the live node whenever it has evaluated —
/// in its body, or imperatively afterwards, never in the update pass that runs
/// before a fresh node's first evaluation installs its invalidator — and kept
/// for writes that arrive after the node is gone (a projected binding written
/// once the snapshot renderer is released, STUI-1265). A location built for an
/// already retired owner starts from its capture's bind-time answer.
@MainActor
private final class StateOwnerKind {
  private(set) var isSnapshotOwner: Bool

  init(isSnapshotOwner: Bool) {
    self.isSnapshotOwner = isSnapshotOwner
  }

  /// Records the answer of an owner node that has evaluated, and returns it.
  @discardableResult
  func observe(_ ownerNode: SwiftTUICore.ViewNode) -> Bool {
    isSnapshotOwner = ownerNode.invalidator == nil
    return isSnapshotOwner
  }
}

/// Backing-storage identity survives re-projection while distinguishing
/// declarations, composed-property paths, and independently mounted owners.
private struct StateBindingSource: Hashable, Sendable {
  var owner: StateStorageOwner
  var slot: StateSlotIdentifier
}

/// The declaration a `StateBindingSource` belongs to, without its owner's
/// lifetime: the same authored `@State` keeps one token across every node the
/// framework mounts for it, such as an owner restored from tab dormancy.
private struct StateBindingDeclaration: Hashable, Sendable {
  var graphScope: StateGraphScopeID
  var declarationFileID: String
  var slot: StateSlotIdentifier
}

@MainActor
private final class StateBox<Value> {
  private let slotOrdinal: Int
  /// Whether the graph slots this box binds may ride a lazy container's
  /// dormant archive (`.owned`, the authored-state default) or are
  /// re-derived scratch that must stay out of it (`.transient`). Fixed at
  /// construction: the slot keeps the policy it was born with.
  let dormantPolicy: DormantStateSlotPolicy
  /// The `#fileID` of the authoring declaration. Diagnostics only: slot
  /// identity stays line/column-keyed (`slotOrdinal`), so the file never
  /// participates in matching a box to its graph slot.
  let declarationFileID: String
  private var seedValue: Value
  private let graphSeedFactory: (@MainActor () -> Value)?
  private(set) var seedValueIdentity = StateValueIdentity()
  /// The last write a snapshot owner (an owner in a no-invalidator
  /// `DefaultRenderer` graph) made to this box, or `nil` when a seed write
  /// followed it. Only a snapshot owner's fresh slot or capture-miss read sees
  /// it: snapshot continuity reaches a later snapshot of the same view value,
  /// never a live mount, which seeds from `seedValue` alone (STUI-1241,
  /// STUI-1265, STUI-1266).
  private var snapshotSeed: (value: Value, identity: StateValueIdentity)?
  private var boundLocationsByOwner: [StateStorageOwner: DynamicStateLocation<Value>]
  private var retainedValuesByOwner:
    [StateStorageOwner: (value: Value, identity: StateValueIdentity)]
  /// Latches once any owner binds a location. Distinguishes a pre-mount
  /// seed read (expected: the box has only its seed) from an imperative
  /// access that lost its live slot and silently degraded to the seed —
  /// the `state.imperativeSeedFallback` warning fires only for the latter.
  private(set) var hasEverBeenGraphBound = false

  init(
    seedValue: Value,
    slotOrdinal: Int,
    declarationFileID: String,
    dormantPolicy: DormantStateSlotPolicy = .owned,
    graphSeedFactory: (@MainActor () -> Value)? = nil
  ) {
    self.graphSeedFactory = graphSeedFactory
    self.slotOrdinal = slotOrdinal
    self.declarationFileID = declarationFileID
    self.dormantPolicy = dormantPolicy
    self.seedValue = seedValue
    boundLocationsByOwner = [:]
    retainedValuesByOwner = [:]
  }

  func currentSeedValue() -> Value {
    seedValue
  }

  /// The value a snapshot owner's capture-miss read observes.
  func currentSnapshotSeedValue() -> Value {
    snapshotSeed?.value ?? seedValue
  }

  /// The value a fresh graph slot starts from: the authored (or pre-mount)
  /// seed, never a snapshot's write.
  func initialGraphValue() -> Value {
    graphSeedFactory?() ?? seedValue
  }

  /// The value a snapshot owner's fresh slot starts from instead, when a
  /// snapshot write follows the last seed write. Factory-seeded boxes always
  /// start from their factory.
  func snapshotGraphValue() -> Value? {
    graphSeedFactory == nil ? snapshotSeed?.value : nil
  }

  /// A seed write (pre-mount, or capture-less) supersedes any snapshot write,
  /// so the last writer still wins for a later snapshot.
  func updateSeedValue(_ newValue: Value) {
    seedValue = newValue
    seedValueIdentity = StateValueIdentity()
    snapshotSeed = nil
  }

  func updateSnapshotSeedValue(_ newValue: Value) {
    snapshotSeed = (newValue, StateValueIdentity())
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

  func retainedValue(
    for owner: StateStorageOwner
  ) -> Value? {
    retainedValuesByOwner[owner]?.value
  }

  func retainedValueIdentity(for owner: StateStorageOwner) -> StateValueIdentity? {
    retainedValuesByOwner[owner]?.identity
  }

  func storeRetainedValue(
    _ value: Value,
    for owner: StateStorageOwner
  ) {
    retainedValuesByOwner[owner] = (value, StateValueIdentity())
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
/// A no-invalidator `DefaultRenderer` snapshot is not a mount lifetime: an
/// imperative write to one of its owners, through the state or a projected
/// binding, reaches a later snapshot of the same view value, also after the
/// first renderer is released. It never seeds a later live mount.
public struct State<Value> {
  private let box: StateBox<Value>
  /// The owner this copy was bound to by the capture-bind pass (plan
  /// 2026-08-20-001) — written in place into the exact container copy body
  /// evaluation consumes, so closures created in the body carry their state
  /// owner. `nil` until a bind pass runs. Per-copy by value semantics:
  /// authored containers are value types (plan 2026-08-29-001), so distinct
  /// mounts always bind distinct copies.
  private var capture: StateCaptureBinding?

  /// Creates state with the supplied initial wrapped value.
  ///
  /// `fileID`, `line`, and `column` default to the declaration site. Line and
  /// column key the slot identity; the file only names the declaration in
  /// runtime diagnostics such as `state.imperativeSeedFallback`.
  public init(
    wrappedValue: Value,
    fileID: String = #fileID,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: wrappedValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      ),
      declarationFileID: fileID
    )
  }

  public init(
    initialValue: Value,
    fileID: String = #fileID,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: initialValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      ),
      declarationFileID: fileID
    )
  }

  /// Framework-internal state with an explicit dormancy policy. `.transient`
  /// keeps the slot out of a lazy container's dormant archive: the archive
  /// neither stores it nor reports it as unsupported, and a returning tab
  /// re-seeds it from the authored value. For re-derived scratch that a
  /// reference type carries across re-renders without scheduling a frame
  /// (a measured width, a layout cache), that is the honest contract —
  /// the value is rebuilt on the first pass after reactivation anyway.
  package init(
    wrappedValue: Value,
    dormantPolicy: DormantStateSlotPolicy,
    fileID: String = #fileID,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: wrappedValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      ),
      declarationFileID: fileID,
      dormantPolicy: dormantPolicy
    )
  }

  /// Internal identity storage can allocate a distinct seed for each mounted
  /// owner. Initializing a graph slot is a read, never a render-time mutation.
  package init(
    initialValueFactory: @escaping @MainActor () -> Value,
    fileID: String = #fileID,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: initialValueFactory(),
      slotOrdinal: StateSlotOrdinals.authored(line: line, column: column),
      declarationFileID: fileID,
      graphSeedFactory: initialValueFactory
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
          declarationFileID: box.declarationFileID,
          reason: "no live state owner could be resolved from the dispatch context"
        )
      }
      if resolvesThroughCapture, capture?.isSnapshotOwner == true {
        return box.currentSnapshotSeedValue()
      }
      return box.currentSeedValue()
    }
    nonmutating set {
      if let location = activeLocation() {
        location.setValue(newValue)
        return
      }
      // A carried capture that missed names an owner whose committed removal
      // left no occupant. When that owner was a mount lifetime (its graph had
      // an invalidator), the write belongs to the retired lifetime and is
      // discarded: the box seed is shared by every copy of the authored value,
      // and a later mount's fresh slot seeds from it (STUI-1173). A snapshot
      // owner's graph was never a mount lifetime, so its write reaches the
      // box's snapshot seed below, the same-instance continuity of the
      // graph-slot setter (STUI-1241), which only a later snapshot reads
      // (STUI-1266).
      let discardsRetiredWrite = resolvesThroughCapture && capture?.isSnapshotOwner != true
      // Pre-mount seeding is the legitimate use of the seed arm. A write on a
      // box that once had a live slot does not reach that slot — the
      // silent-no-op-write half of the corruption class — so it is as loud as
      // the read-side fallback (plan 2026-08-20-001 Stage 5).
      if box.hasEverBeenGraphBound, ViewNodeContext.current == nil {
        reportImperativeSeedFallback(
          slotOrdinal: box.currentOrdinal,
          declarationFileID: box.declarationFileID,
          reason:
            "no live state owner could be resolved from the dispatch context; "
            + (discardsRetiredWrite
              ? "the write to the removed owner was discarded"
              : "the write reached only the authored seed")
        )
      }
      guard !discardsRetiredWrite else {
        return
      }
      if resolvesThroughCapture {
        box.updateSnapshotSeedValue(newValue)
      } else {
        box.updateSeedValue(newValue)
      }
    }
  }

  public var projectedValue: Binding<Value> {
    if let location = activeLocation(retainingRemovedOwner: true) {
      return location.binding
    }
    var binding = Binding(
      mainActorGet: { wrappedValue },
      set: { wrappedValue = $0 }
    ).withBindingSource(ObjectIdentifier(box))
    binding.valueIdentity = {
      if let location = activeLocation() {
        return location.valueIdentity()
      }
      return box.seedValueIdentity
    }
    return binding
  }

  #if DEBUG
    package var rememberedOwnerCountForTesting: Int {
      box.rememberedOwnerCount
    }

    package var captureSlotForTesting: StateCaptureBinding? {
      capture
    }
  #endif

  /// In-body accesses resolve through the ambient resolve scope; every other
  /// access resolves through the carried capture when this copy has one.
  private var resolvesInBodyScope: Bool {
    ViewNodeContext.current != nil && HandlerInvocationScope.current == nil
  }

  private var resolvesThroughCapture: Bool {
    capture != nil && !resolvesInBodyScope
  }

  private func activeLocation(retainingRemovedOwner: Bool = false) -> DynamicStateLocation<Value>? {
    if resolvesInBodyScope {
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
        observeOwnerKind(of: refreshed, storageOwner: storageOwner)
        return refreshed
      }
      let location = makeLocation(
        for: context,
        storageOwner: storageOwner
      )
      observeOwnerKind(of: location, storageOwner: storageOwner)
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
    if resolvesThroughCapture {
      // A captured owner is authoritative even after removal. Falling through
      // would let an unrelated dispatch context lend this closure its state.
      return captureLocation(retainingRemovedOwner: retainingRemovedOwner)
    }

    // Dispatch-snapshot tier: an installed imperative context names an exact
    // recorded owner handle, so serving it is precise by construction — no
    // guessing. It covers closures minted from app-held view values (copies
    // the bind pass never saw) dispatched under a registration snapshot, the
    // a81ee22e nil-preservation contract. The guessing tiers that used to
    // follow — the live-parent ancestor walk, the sole-live-binding pick,
    // and the imperative location mint — are deleted (plan 2026-08-20-001
    // Stage 5): body-created closures carry their owner as captures, and an
    // access neither a capture nor an exact bound location can serve reads
    // the authored seed loudly instead of another owner's slot silently.
    guard let context = AuthoringContextStorage.current,
      let storageOwner = stateStorageOwner(for: context),
      let location = box.rememberedLocation(for: storageOwner)
    else {
      return nil
    }
    StateCaptureCensus.record(.ladderExactOwner)
    return location
  }

  /// An in-body access runs inside its owner's evaluation, so the owner node's
  /// invalidator is installed: record whether it is a snapshot owner, for a
  /// projected binding that is written only after its node is gone.
  private func observeOwnerKind(
    of location: DynamicStateLocation<Value>,
    storageOwner: StateStorageOwner
  ) {
    if let ownerNode = LiveViewGraphRegistry.node(for: storageOwner) {
      location.ownerKind.observe(ownerNode)
    }
  }

  /// Rung 2 of imperative resolution: route through the capture written by
  /// the bind pass. A live captured owner serves directly; a dead one takes
  /// the fire-time identity refresh — map the capture's resolve identity
  /// through its own graph scope's live identity index to the current
  /// occupant node (the ratified focused-values category: dispatch context
  /// is runtime state). The refresh never crosses graph scopes and requires
  /// a live occupant. Committed removal cannot fall through to an unrelated
  /// ambient owner. Only a projected Binding, or a carried lifecycle handler of
  /// the removed view (``CommittedOwnerHandlerScope``), may retain the retired
  /// value.
  private func captureLocation(retainingRemovedOwner: Bool) -> DynamicStateLocation<Value>? {
    guard let binding = capture else {
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
    if retainingRemovedOwner || CommittedOwnerHandlerScope.isActive {
      return location(
        for: binding.owner, path: binding.path,
        retiredOwnerIsSnapshot: binding.isSnapshotOwner)
    }
    if StateCaptureBindingConfiguration.isEnabled {
      SoundnessProbeConfiguration.recordStateCaptureMissViolation(
        "state-capture-miss: owner dead, refresh failed for \(binding.identity)"
      )
    }
    return nil
  }

  private func location(
    for storageOwner: StateStorageOwner,
    path: StateSlotPath,
    retiredOwnerIsSnapshot: Bool = false
  ) -> DynamicStateLocation<Value> {
    if let remembered = box.rememberedLocation(for: storageOwner) {
      return remembered
    }
    let location = graphSlotLocation(
      storageOwner: storageOwner,
      path: path,
      retiredOwnerIsSnapshot: retiredOwnerIsSnapshot
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
      if box.dormantPolicy.survivesDormancy {
        let slot = StateSlotIdentifier(ordinal: box.currentOrdinal, path: path)
        HotReloadSchemaCapture.current?.record(viewNode, slot: slot, type: Value.self)
        if viewNode.ownerGraph?.hasHotReloadValue(for: viewNode.identity, slot: slot) == true {
          // Restore even unread declarations before body/lifecycle evaluation.
          _ = withDormantStateSlotPolicy(box.dormantPolicy) {
            viewNode.primedStateSlot(slot, seed: box.currentSeedValue())
          }
        }
      }
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

  /// A location that reads and writes the graph slot owned by `viewNode`. The
  /// closures re-resolve the live node from its graph on every access, so a
  /// location built once stays valid across reuse, and degrade to the retained
  /// value (then the seed) if the node is gone.
  ///
  /// A snapshot owner (``StateOwnerKind``) keeps its writes for a later
  /// snapshot of the same view value: its fresh slot continues the box's last
  /// snapshot write, and its writes reach that snapshot seed. A live owner
  /// never reads or writes it.
  private func graphSlotLocation(
    storageOwner: StateStorageOwner,
    path: StateSlotPath = .root,
    retiredOwnerIsSnapshot: Bool = false
  ) -> DynamicStateLocation<Value> {
    let slotIdentifier = StateSlotIdentifier(ordinal: box.currentOrdinal, path: path)
    let ownerKind = StateOwnerKind(isSnapshotOwner: retiredOwnerIsSnapshot)
    // Fresh slots always seed from the authored initial value; a snapshot
    // owner's fresh slot continues the last snapshot write of this view value
    // instead. A retained per-owner value serves only the node-gone read
    // fallback below — seeding a new slot from carried mutation would
    // resurrect state across committed removal and leak writes into
    // replacement identities.
    let authoredSeed = box.initialGraphValue()
    let authoredSeedIdentity = box.seedValueIdentity
    let slotOrdinal = box.currentOrdinal
    let declarationFileID = box.declarationFileID
    let dormantPolicy = box.dormantPolicy
    return DynamicStateLocation(
      bindingSourceID: AnyID(StateBindingSource(owner: storageOwner, slot: slotIdentifier)),
      bindingDeclarationID: AnyID(
        StateBindingDeclaration(
          graphScope: storageOwner.graphScope,
          declarationFileID: declarationFileID,
          slot: slotIdentifier
        )
      ),
      getValue: { [weak box] in
        guard let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) else {
          if let retainedValue = box?.retainedValue(for: storageOwner) {
            return retainedValue
          }
          if ViewNodeContext.current == nil {
            reportImperativeSeedFallback(
              slotOrdinal: slotOrdinal,
              declarationFileID: declarationFileID,
              reason: "the state's owning node is no longer live and holds no retained value"
            )
          }
          return authoredSeed
        }
        // Invalid composed helpers can claim the same slot with different
        // types. The claim diagnostic identifies the authoring error; preserve
        // the first slot and serve this declaration's seed instead of trapping
        // or corrupting another declaration's storage.
        if let slot = liveViewNode.stateSlotStorage(slotIdentifier),
          slot.isInitialized, !slot.stores(Value.self)
        {
          return authoredSeed
        }
        let isSnapshotOwner = ownerKind.observe(liveViewNode)
        return withDormantStateSlotPolicy(dormantPolicy) {
          liveViewNode.stateSlot(
            slotIdentifier,
            seed: (isSnapshotOwner ? box?.snapshotGraphValue() : nil) ?? authoredSeed
          )
        }
      },
      setValue: { [weak box] newValue in
        // Graph-backed writes stay owner-scoped: the slot holds the mutation
        // and the per-owner retained value backs the node-gone read fallback.
        // A live (invalidator-backed) graph never mirrors a write into the
        // box — that leaked one owner's mutation into every future owner
        // seeded from the same box.
        //
        // A no-invalidator graph is the one-shot `DefaultRenderer` snapshot
        // path, and it is not a mount lifetime at all: the graph is discarded
        // when `render` returns. Its only reader is a subsequent snapshot of
        // the same view value, which is exactly the same-instance continuity
        // an imperative dispatch between two renders depends on, so a
        // snapshot owner's write reaches the box's snapshot seed — whether
        // its node is still live or its renderer is already released (a
        // projected binding writes here, not through a capture, STUI-1265).
        // A live mount never seeds from that value (STUI-1266).
        if let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) {
          if let slot = liveViewNode.stateSlotStorage(slotIdentifier),
            slot.isInitialized, !slot.stores(Value.self)
          {
            ImperativeRuntimeIssueQueue.record(
              RuntimeIssue(
                severity: .warning, code: "state.duplicateSlotClaim",
                message:
                  "A write from @State<\(Value.self)> cannot replace the incompatible slot \(slotIdentifier) storing \(slot.storedTypeDescription). Conform the enclosing helper to DynamicProperty.",
                source: "@State"))
            return
          }
          withDormantStateSlotPolicy(dormantPolicy) {
            liveViewNode.setStateSlot(
              slotIdentifier,
              value: newValue,
              invalidationIdentity: liveViewNode.identity
            )
          }
          if ownerKind.observe(liveViewNode) {
            box?.updateSnapshotSeedValue(newValue)
          }
          box?.storeRetainedValue(newValue, for: storageOwner)
        } else {
          if ownerKind.isSnapshotOwner {
            box?.updateSnapshotSeedValue(newValue)
          }
          box?.storeRetainedValue(newValue, for: storageOwner)
        }
      },
      valueIdentity: { [weak box] in
        if let liveViewNode = LiveViewGraphRegistry.node(for: storageOwner) {
          // The preceding value read primes the slot and records its reader.
          // Inspecting currency must not introduce a new state dependency.
          return liveViewNode.stateSlotStorage(slotIdentifier)?.valueIdentity
        }
        return box?.retainedValueIdentity(for: storageOwner) ?? authoredSeedIdentity
      },
      ownerKind: ownerKind
    )
  }
}

/// Installs the slot-policy scope a `StateBox`'s graph accesses materialize
/// under, so the slot is born with the policy its wrapper declared.
@MainActor
private func withDormantStateSlotPolicy<Result>(
  _ policy: DormantStateSlotPolicy,
  _ body: () throws -> Result
) rethrows -> Result {
  switch policy {
  case .owned:
    return try withOwnedDormantStateSlot(body)
  case .persistent:
    return try withPersistentDormantStateSlot(body)
  case .transient:
    return try withTransientDormantStateSlot(body)
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
private func reportImperativeSeedFallback(
  slotOrdinal: Int,
  declarationFileID: String,
  reason: String
) {
  StateCaptureCensus.record(.seedFallback)
  let declarationSite = stateDeclarationSite(
    slotOrdinal: slotOrdinal,
    declarationFileID: declarationFileID
  )
  if StateCaptureBindingConfiguration.isEnabled {
    // Oracle promotion (plan 2026-08-20-001 Stage 3): with captures live,
    // a seed fallback is a soundness failure, not merely a loud diagnostic.
    SoundnessProbeConfiguration.recordStateSeedFallbackViolation(
      "state-seed-fallback: \(declarationSite) (slot \(slotOrdinal)): \(reason)"
    )
  }
  let message =
    "An imperative @State access fell back to the authored initial value: "
    + reason + ". The closure observed the seed, not the last written value."
    + " The state is declared at \(declarationSite)."
  ImperativeRuntimeIssueQueue.record(
    RuntimeIssue(
      severity: .warning,
      code: "state.imperativeSeedFallback",
      message: message,
      source: "@State"
    )
  )
}

/// The `file:line:column` a diagnostic names for an authored slot. Authored
/// ordinals pack the declaration's line and column (`StateSlotOrdinals`);
/// a framework-internal negative ordinal carries no authored position, so
/// only the file is named.
private func stateDeclarationSite(
  slotOrdinal: Int,
  declarationFileID: String
) -> String {
  guard slotOrdinal >= 0 else {
    return declarationFileID
  }
  return "\(declarationFileID):\(slotOrdinal >> 16):\(slotOrdinal & 0xFFFF)"
}

extension State: HotReloadSlotDeclaring {
  package func hotReloadDeclaration(path: StateSlotPath) -> (StateSlotIdentifier, String)? {
    guard box.dormantPolicy.survivesDormancy else { return nil }
    return (.init(ordinal: box.currentOrdinal, path: path), String(reflecting: Value.self))
  }
}

extension State: CaptureBindableDynamicProperty {
  /// Writes the bind pass's owner into this copy. An unconditional
  /// overwrite: copies are private to their mount, because authored
  /// containers are value types (plan 2026-08-29-001). Every fresh
  /// evaluation rebinds, and no two mounts can reach the same slot.
  package mutating func bindCapture(_ context: DynamicPropertyCaptureContext) {
    capture = context.ownedSlot
  }

  // Direct adapter used by the State lifetime contract tests.
  package mutating func bindCapture(_ binding: StateCaptureBinding) {
    capture = binding
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

#if DEBUG
  extension State: BodyDebugStateDeclaring {
    package func bodyDebugStateSlot(path: StateSlotPath) -> StateSlotKey? {
      guard let owner = capture?.owner ?? currentAuthoringContext()?.stateOwnerHandle else {
        return nil
      }
      return StateSlotKey(
        owner: owner.ownerLifetime,
        slot: .init(ordinal: box.currentOrdinal, path: capture?.path ?? path))
    }
  }

  extension Binding: BodyDebugStateDeclaring {
    package func bodyDebugStateSlot(path: StateSlotPath) -> StateSlotKey? {
      // A member projection (`$model.count`) boxes its base's source, once per
      // member; the state slot is named by the root (STUI-1131).
      guard let source = bindingSourceID?.derivationRoot, let scope = BodyChangeScope.current
      else { return nil }
      let candidates = (scope.prior?.states ?? []).union(
        ViewNodeContext.current?.dependencies.stateSlotReads ?? [])
      return candidates.first { key in
        source
          == AnyID(
            StateBindingSource(
              owner: StateOwnerHandle(
                graphScope: .init(rawValue: scope.graph), ownerLifetime: key.owner),
              slot: key.slot))
      }
    }
  }
#endif
