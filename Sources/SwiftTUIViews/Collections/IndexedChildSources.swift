package import SwiftTUIGraph

@MainActor
package protocol IndexedChildSourceView {
  func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)?
}

/// Test instrumentation (the F118 probe pattern): counts retained-artifact
/// adoptions vs fresh mints in `ForEachIndexedChildSource.init`, so a
/// live-session test can pin that the F145 retention actually engages on the
/// composed runtime path — a nil `ViewNodeContext.current` at declaration
/// time would silently disable it (every rebuild would fresh-mint, correct
/// but decorative). Increments compile out of release, so the probe costs
/// nothing where no test reads it.
@MainActor
package enum IndexedChildSourceArtifactsProbe {
  package private(set) static var adoptionCount = 0
  package private(set) static var freshMintCount = 0
  /// Adoptions that verified through the integer-range id-space witness
  /// (R4-A) — the O(1) fast path that skips both the per-element ids
  /// materialization and the element-wise `==` verify.
  package private(set) static var rangeWitnessAdoptionCount = 0
  /// Hosted-collection row-selection snapshots served from the retained
  /// artifacts instead of the O(dataset) per-resolve rebuild (R4-A).
  package private(set) static var rowSelectionReuseCount = 0

  package static func recordAdoption() {
    #if DEBUG
      adoptionCount += 1
    #endif
  }

  package static func recordRangeWitnessAdoption() {
    #if DEBUG
      rangeWitnessAdoptionCount += 1
    #endif
  }

  package static func recordRowSelectionReuse() {
    #if DEBUG
      rowSelectionReuseCount += 1
    #endif
  }

  package static func recordFreshMint() {
    #if DEBUG
      freshMintCount += 1
    #endif
  }

  package static func reset() {
    #if DEBUG
      adoptionCount = 0
      freshMintCount = 0
      rangeWitnessAdoptionCount = 0
      rowSelectionReuseCount = 0
    #endif
  }
}

/// Process-latched R4-A resolve-reuse gate (`SWIFTTUI_COLLECTION_RESOLVE_REUSE`,
/// kill switch, default on). Latched once outside the generic source class —
/// generic types cannot host static stored state.
@MainActor
package enum HostedCollectionResolveReuse {
  package static let isEnabled = FeatureGate.collectionResolveReuse.initialIsEnabled()
}

/// O(1)-verifiable id-space witness for integer-range-shaped sources (R4-A):
/// `Range<Int>` / `ClosedRange<Int>` data identified by `\.self` fully
/// determines the materialized ids array — consecutive integers from
/// `lowerBound` — so (lowerBound, count) IS the ids array's value. Retained
/// identity artifacts carrying an equal witness verify with two `Int`
/// compares instead of an O(N) keypath map plus element-wise `==` per
/// container resolve (the `List` route body's per-notch ids floor).
package struct IntegerRangeIDWitness: Equatable, Sendable {
  package let lowerBound: Int
  package let count: Int

  package init(lowerBound: Int, count: Int) {
    self.lowerBound = lowerBound
    self.count = count
  }
}

/// The witness for `data` identified by `id`, or `nil` when the source shape
/// cannot prove its ids by bounds. The keypath must be the *identity* keypath
/// — `\Int.hashValue` is also `KeyPath<Int, Int>` and must not match.
package func integerRangeIDWitness<Data: RandomAccessCollection, ID: Hashable & Sendable>(
  data: Data,
  id: KeyPath<Data.Element, ID>
) -> IntegerRangeIDWitness? {
  guard let identityPath = id as? KeyPath<Int, Int>, identityPath == \Int.self else {
    return nil
  }
  if let range = data as? Range<Int> {
    return IntegerRangeIDWitness(lowerBound: range.lowerBound, count: range.count)
  }
  if let closedRange = data as? ClosedRange<Int> {
    return IntegerRangeIDWitness(lowerBound: closedRange.lowerBound, count: closedRange.count)
  }
  return nil
}

/// One row of the hosted collection's realization-free selection snapshot:
/// the policy-compatible selection tag (nil for non-selectable rows) plus the
/// element's derived identity. `List` materializes one per element on every
/// resolve; the R4-A cache retains the snapshot on the source's identity
/// artifacts instead (see ``RowSelectionCachingIndexedChildSource``).
package struct HostedCollectionRowSelection: Sendable {
  package var tag: SelectionTag?
  package var identity: Identity

  package init(tag: SelectionTag?, identity: Identity) {
    self.tag = tag
    self.identity = identity
  }
}

/// The inputs, besides the retained artifacts themselves, that determine a
/// hosted collection's row-selection snapshot: whether the container's policy
/// selects at all, and the selection value type the tags must cast to. Equal
/// ids already imply equal retained tags and identities (the premise the F145
/// adoption verify stands on), so (artifacts, key) fully determine the rows.
package struct HostedRowSelectionCacheKey: Equatable, Sendable {
  package let isSelectable: Bool
  package let selectionValueType: ObjectIdentifier

  package init(isSelectable: Bool, selectionValueType: ObjectIdentifier) {
    self.isSelectable = isSelectable
    self.selectionValueType = selectionValueType
  }
}

/// Sources that retain the hosted collection's row-selection snapshot across
/// container resolves (R4-A). The snapshot is rebuilt through `build` whenever
/// the compat key changes; artifacts re-mint on any ids change, so a retained
/// snapshot can never outlive the id set it was derived from.
@MainActor
package protocol RowSelectionCachingIndexedChildSource {
  func retainedRowSelections(
    key: HostedRowSelectionCacheKey,
    build: () -> [HostedCollectionRowSelection]
  ) -> [HostedCollectionRowSelection]
}

/// Instrumentation (the F118 probe pattern): counts how many distinct
/// elements an indexed source actually *realizes* — resolves a child view
/// for — during a pass. Realization dominates hosted-collection frame cost,
/// so this is the counter that distinguishes a windowed collection (O(viewport)
/// realizations) from one that collapsed to full-dataset realization. Cache
/// hits are deliberately not counted: the per-source cache lives exactly one
/// resolve, so a pass's miss count *is* its realized-row count.
///
/// Armed by ``FeatureGate/collectionProbes`` (`SWIFTTUI_COLLECTION_PROBES`):
/// always on in DEBUG, opt-in in release. Disarmed, `recordRealization()` is a
/// static `Bool` read and a branch — this fires once per realized row, which is
/// why the check is a plain main-actor-isolated load rather than anything
/// synchronized. The run loop resets it at each frame head and samples it at
/// commit into the `realized_rows` column of `frames.tsv`.
@MainActor
package enum IndexedChildRealizationProbe {
  /// Whether the probe counts. Latched from the environment on first access;
  /// settable so a test can measure the disarmed path (DEBUG defaults armed,
  /// so an unarmed assertion has no other way to reach that state).
  package static var isArmed: Bool = FeatureGate.collectionProbes.initialIsEnabled()

  /// Rows realized since the last ``reset()``. Always readable — the existing
  /// DEBUG suites assert on it directly and arming is additive to them.
  package private(set) static var realizedChildCount = 0

  /// The same count, or `nil` when the probe is disarmed. This is what the
  /// per-frame diagnostics sample reads: `nil` and `0` are opposite findings —
  /// no measurement was taken versus a pass that realized nothing — and the
  /// `realized_rows` column preserves the distinction rather than reporting an
  /// unconfigured run as a perfectly windowed one.
  package static var realizedChildCountIfArmed: Int? {
    isArmed ? realizedChildCount : nil
  }

  package static func recordRealization() {
    guard isArmed else {
      return
    }
    realizedChildCount += 1
  }

  package static func reset() {
    realizedChildCount = 0
  }
}

/// The identity artifacts a `ForEachIndexedChildSource` retains across
/// container resolves (F145): pure functions of (element ids, identity root,
/// entity scope), adopted only when all three match, so a rebuilt source over
/// unchanged data skips the per-element `EntityIdentity` mints and the
/// identity-path signature build — and shares the signature's storage box,
/// making downstream equivalence comparisons pointer-fast. Element caches are
/// deliberately NOT retained here: equal ids do not imply equal element
/// values, and realized rows capture the declaring frame's `ResolveContext`
/// (frame-scoped registries) — carrying them across frames is the
/// stale-draft-registry bug class.
@MainActor
private final class ForEachSourceIdentityArtifacts<ID: Hashable & Sendable>:
  RetainedIndexedChildSourceArtifacts
{
  let identityRoot: Identity
  let scope: StructuralPath
  let ids: [ID]
  let entityIdentities: [EntityIdentity]
  let signature: IndexedChildMeasurementSignature
  /// Per-element identities and selection tags, materialized once per id-set
  /// change instead of per call.
  ///
  /// `elementIdentity(at:)` built an `Identity` through `explicitID`, which
  /// runs `String(reflecting:)` plus per-character escaping every time; the
  /// collection containers and the windowed stack measurement called it in
  /// O(dataset) loops each resolve (register item D18). These are pure
  /// functions of (ids, identity root, entity scope) — the same triple the
  /// artifacts are already content-verified against — so retaining them is
  /// sound for exactly as long as retaining the identities themselves.
  let elementIdentities: [Identity]
  let selectionTags: [SelectionTag]
  /// Element index by id, so locating a selected row is a hash lookup rather
  /// than a scan of the whole dataset.
  let indexByID: [ID: Int]
  var tableColumns: [TableColumnPayload]?
  var tableColumnWidths: [Int] = []
  /// The integer-range id-space witness these artifacts were verified over,
  /// when the minting (or a later element-wise-verified adopting) resolve
  /// proved one (R4-A). Non-nil means `ids == Array(range)` for the witness's
  /// range, so a resolve holding an equal witness adopts in O(1).
  var integerRangeIDWitness: IntegerRangeIDWitness?
  /// The retained hosted-collection row-selection snapshot and the compat key
  /// it was built under (R4-A). Pure derived memoization: rebuilt through the
  /// container's builder on any key change, and it dies with the artifacts on
  /// any ids change.
  var rowSelectionsKey: HostedRowSelectionCacheKey?
  var rowSelections: [HostedCollectionRowSelection] = []

  init(
    identityRoot: Identity,
    scope: StructuralPath,
    ids: [ID],
    entityIdentities: [EntityIdentity],
    integerRangeIDWitness: IntegerRangeIDWitness? = nil
  ) {
    self.identityRoot = identityRoot
    self.scope = scope
    self.ids = ids
    self.entityIdentities = entityIdentities
    self.integerRangeIDWitness = integerRangeIDWitness
    elementIdentities = zip(ids, entityIdentities).map { id, entityIdentity in
      identityRoot.explicitID(id, occurrence: entityIdentity.occurrence)
    }
    // Derived from the element identities just built, so a fresh mint runs
    // the `explicitID` reflect-and-escape once per element, not twice.
    signature = IndexedChildMeasurementSignature(
      elementPaths: elementIdentities.lazy.map(\.path)
    )
    selectionTags = ids.map { SelectionTag(value: $0, includeOptional: true) }
    // First occurrence wins: a duplicated id is already a diagnostic elsewhere,
    // and the earliest row is the one selection semantics resolve to.
    indexByID = Dictionary(zip(ids, ids.indices), uniquingKeysWith: { first, _ in first })
  }

  func matches(
    ids: [ID],
    identityRoot: Identity,
    scope: StructuralPath
  ) -> Bool {
    self.identityRoot == identityRoot
      && self.scope == scope
      && self.ids == ids
  }

  /// O(1) verify against a range-shaped resolve (R4-A): sound because both
  /// sides' witnesses each fully determine their ids arrays, so equal
  /// witnesses imply the element-wise `matches(ids:)` would have succeeded.
  func matches(
    integerRangeIDWitness witness: IntegerRangeIDWitness,
    identityRoot: Identity,
    scope: StructuralPath
  ) -> Bool {
    integerRangeIDWitness == witness
      && self.identityRoot == identityRoot
      && self.scope == scope
  }
}

/// The identity artifacts a ForEach resolve adopts (or mints) for its source:
/// the entity identities plus the per-element explicit identities, both pure
/// functions of (ids, identity root, entity scope).
package struct ForEachAdoptedIdentityArtifacts {
  package let entityIdentities: [EntityIdentity]
  package let elementIdentities: [Identity]
}

/// Adopts the retained identity artifacts for a ForEach source resolving
/// under `identityRoot` on the node currently under evaluation, minting and
/// retaining them when absent or stale.
///
/// The eager `ForEach.resolveElements` path shares the lazy containers'
/// cache through this seam: a re-resolve over unchanged data skips the
/// per-element `EntityIdentity` mints (a `String(reflecting:)` each) and the
/// `explicitID` reflect-and-escape identity builds, which the eager fork
/// otherwise pays for every element on every resolve of its host.
@MainActor
package func adoptedForEachIdentityArtifacts<ID: Hashable & Sendable>(
  ids: [ID],
  identityRoot: Identity
) -> ForEachAdoptedIdentityArtifacts {
  let scope = forEachEntityScope(identityRoot: identityRoot)
  let host = ViewNodeContext.current
  if let retained = host?.retainedIndexedChildSourceArtifacts(
    forIdentityRoot: identityRoot
  ) as? ForEachSourceIdentityArtifacts<ID>,
    retained.matches(ids: ids, identityRoot: identityRoot, scope: scope)
  {
    IndexedChildSourceArtifactsProbe.recordAdoption()
    return .init(
      entityIdentities: retained.entityIdentities,
      elementIdentities: retained.elementIdentities
    )
  }
  IndexedChildSourceArtifactsProbe.recordFreshMint()
  let artifacts = ForEachSourceIdentityArtifacts(
    identityRoot: identityRoot,
    scope: scope,
    ids: ids,
    entityIdentities: makeEntityIdentities(ids: ids, scope: scope)
  )
  host?.retainIndexedChildSourceArtifacts(
    artifacts,
    forIdentityRoot: identityRoot
  )
  return .init(
    entityIdentities: artifacts.entityIdentities,
    elementIdentities: artifacts.elementIdentities
  )
}

@MainActor
package final class ForEachIndexedChildSource<Data, ID, Content>: IndexedChildSource
where Data: RandomAccessCollection, ID: Hashable & Sendable, Content: View {
  private let countStorage: Int
  private let identityRootStorage: Identity
  private let measurementSignatureStorage: IndexedChildMeasurementSignature

  private let data: Data
  private let id: KeyPath<Data.Element, ID>
  private let ids: [ID]
  private let entityIdentities: [EntityIdentity]
  private let identityArtifacts: ForEachSourceIdentityArtifacts<ID>
  private let content: @MainActor (Data.Element) -> Content
  private let childContext: ResolveContext
  private let authoringScope: AuthoringContext?
  /// The node mid-evaluation when the lazy container declared this source.
  /// Realization runs later, from layout, where `ViewNodeContext.current` is
  /// nil — so element mints anchor to this captured host instead (weak: a
  /// departed host means the container is already tearing down). Typed via
  /// the graph module directly — the authoring layer's `ViewNode` protocol
  /// shadows the graph's node class.
  private weak var mintHost: SwiftTUIGraph.ViewNode?
  private var cache: [Int: ResolvedNode] = [:]
  private var elementsCache: [Int: [ResolvedNode]] = [:]

  package init(
    data: Data,
    id: KeyPath<Data.Element, ID>,
    content: @escaping @MainActor (Data.Element) -> Content,
    childContext: ResolveContext
  ) {
    self.data = data
    self.id = id
    self.content = content
    self.childContext = childContext
    authoringScope = currentAuthoringContext()
    let host = ViewNodeContext.current
    mintHost = host
    identityRootStorage = childContext.identity
    countStorage = data.count

    let scope = forEachEntityScope(identityRoot: childContext.identity)
    let retained =
      host?.retainedIndexedChildSourceArtifacts(
        forIdentityRoot: childContext.identity
      ) as? ForEachSourceIdentityArtifacts<ID>
    let witness =
      HostedCollectionResolveReuse.isEnabled
      ? integerRangeIDWitness(data: data, id: id) : nil

    if let retained, let witness,
      retained.matches(
        integerRangeIDWitness: witness,
        identityRoot: childContext.identity,
        scope: scope
      )
    {
      // R4-A fast path: the witness proves the retained ids array equal to
      // this resolve's WITHOUT materializing it — the O(N) keypath map and
      // the element-wise `==` verify both vanish from the per-resolve cost.
      IndexedChildSourceArtifactsProbe.recordAdoption()
      IndexedChildSourceArtifactsProbe.recordRangeWitnessAdoption()
      ids = retained.ids
      entityIdentities = retained.entityIdentities
      measurementSignatureStorage = retained.signature
      identityArtifacts = retained
      return
    }

    let ids = data.map { $0[keyPath: id] }
    self.ids = ids
    if let retained,
      retained.matches(ids: ids, identityRoot: childContext.identity, scope: scope)
    {
      IndexedChildSourceArtifactsProbe.recordAdoption()
      // Stamp the witness onto artifacts that predate it (an eager-path mint
      // carries none): the element-wise verify just proved `ids` equal to the
      // retained array, and the witness was derived from this resolve's data,
      // so the two certify each other. Subsequent range-shaped resolves adopt
      // in O(1).
      if retained.integerRangeIDWitness == nil, let witness {
        retained.integerRangeIDWitness = witness
      }
      entityIdentities = retained.entityIdentities
      measurementSignatureStorage = retained.signature
      identityArtifacts = retained
    } else {
      IndexedChildSourceArtifactsProbe.recordFreshMint()
      let artifacts = ForEachSourceIdentityArtifacts(
        identityRoot: childContext.identity,
        scope: scope,
        ids: ids,
        entityIdentities: makeEntityIdentities(ids: ids, scope: scope),
        integerRangeIDWitness: witness
      )
      entityIdentities = artifacts.entityIdentities
      measurementSignatureStorage = artifacts.signature
      identityArtifacts = artifacts
      host?.retainIndexedChildSourceArtifacts(
        artifacts,
        forIdentityRoot: childContext.identity
      )
    }
  }

  // The three frame-constant accessors read `private let` storage of Sendable
  // type, fixed on the main actor during `init` and never written again, so
  // they are genuinely nonisolated: the compiler proves the absence of a race
  // rather than `withCheckedMainActorAccess` trapping on the absence of the
  // main actor. That distinction is load-bearing, not cosmetic. The frame
  // tail's layout worker legitimately holds the PREVIOUS frame's retained
  // index, whose resolved nodes still reference live sources, and
  // `RetainedInvalidationSummary` reads `identityRoot` off every one of them
  // to decide which indexed subtrees an invalidation touches. Guarding an
  // immutable read turned that legal, race-free access into a hard SIGTRAP
  // on the worker queue (`_swift_task_checkIsolatedSwift`), which is what
  // made `bun run perf:bench` die with no output at all.
  //
  // `HostedCollectionIndexedChildSource` already forwards these three to its
  // base unguarded, so this also makes the two conformers agree.
  //
  // Everything below that touches `cache`, `elementsCache`, `content`, or the
  // captured `mintHost` keeps the guard: those are the real off-main hazards,
  // and the worker must never realize an element.
  nonisolated package var count: Int {
    countStorage
  }

  nonisolated package var identityRoot: Identity {
    identityRootStorage
  }

  nonisolated package var measurementSignature: IndexedChildMeasurementSignature {
    measurementSignatureStorage
  }

  nonisolated package func child(at index: Int) -> ResolvedNode {
    withCheckedMainActorAccess("IndexedChildSource.child(at:)") {
      if let cached = cache[index] {
        return cached
      }

      let realize = { [self] () -> ResolvedNode in
        IndexedChildRealizationProbe.recordRealization()
        let dataIndex = data.index(data.startIndex, offsetBy: index)
        let element = data[dataIndex]
        let iteration = makeForEachIteration(
          element: element,
          id: element[keyPath: id],
          offset: index,
          occurrence: entityIdentities[index].occurrence,
          entityIdentity: entityIdentities[index],
          elementIdentity: identityArtifacts.elementIdentities[index],
          in: childContext,
          authoringScope: authoringScope,
          suppressStructuralLifecycle: true
        )
        let normalized = iteration.resolve(content: content)
        // The realized element joins no children array — the container's
        // resolved node keeps its lazy source instead of child nodes — so the
        // mint would strand alive in the store when the container departs (the
        // F04/F91 teardown-coherence leak; the gallery collections-tab
        // warning). The captured resolve-lifetime scope supplies the live
        // declaration host and owns this detached result there.
        childContext.viewGraph?.reportDetachedResolvedLifetimeResult(normalized)
        cache[index] = normalized
        return normalized
      }
      if let graph = childContext.viewGraph {
        return graph.withCapturedResolveLifetimeScope(hostedBy: mintHost) {
          realize()
        }
      }
      return realize()
    }
  }

  /// Realization-free: pure function of the element id and the container's
  /// identity root, byte-identical to the identity `child(at:)` resolves the
  /// element under (interior re-identification aside — see the protocol
  /// requirement's note).
  nonisolated package func elementIdentity(at index: Int) -> Identity {
    withCheckedMainActorAccess("IndexedChildSource.elementIdentity(at:)") {
      identityArtifacts.elementIdentities[index]
    }
  }

  nonisolated package func elementSelectionTag(at index: Int) -> SelectionTag? {
    withCheckedMainActorAccess("IndexedChildSource.elementSelectionTag(at:)") {
      identityArtifacts.selectionTags[index]
    }
  }

  nonisolated package func elementIndex(forSelectionTag tag: SelectionTag) -> Int? {
    withCheckedMainActorAccess("IndexedChildSource.elementIndex(forSelectionTag:)") {
      guard let id = tag.value(as: ID.self) else {
        return nil
      }
      return identityArtifacts.indexByID[id]
    }
  }

  nonisolated package func retainedTableColumnWidths(
    columns: [TableColumnPayload],
    discovered: [Int]
  ) -> [Int] {
    withCheckedMainActorAccess("IndexedChildSource.retainedTableColumnWidths") {
      if identityArtifacts.tableColumns != columns
        || identityArtifacts.tableColumnWidths.count != discovered.count
      {
        identityArtifacts.tableColumns = columns
        identityArtifacts.tableColumnWidths = discovered
      } else {
        identityArtifacts.tableColumnWidths = zip(
          identityArtifacts.tableColumnWidths,
          discovered
        ).map(max)
      }
      return identityArtifacts.tableColumnWidths
    }
  }

  nonisolated package func childElements(at index: Int) -> [ResolvedNode] {
    withCheckedMainActorAccess("IndexedChildSource.childElements(at:)") {
      if let cached = elementsCache[index] {
        return cached
      }

      // `child(at:)` realizes, entity-attaches, and hosted-detached-anchors
      // the element mint; splicing here only decides how many stack cells it
      // contributes (mirroring `ForEach.resolveElements`' EmptyView-drop and
      // group-splice arms, which the eager path applies at the same seam).
      let realized = child(at: index)
      let dataIndex = data.index(data.startIndex, offsetBy: index)
      let element = data[dataIndex]
      let iteration = makeForEachIteration(
        element: element,
        id: element[keyPath: id],
        offset: index,
        occurrence: entityIdentities[index].occurrence,
        entityIdentity: entityIdentities[index],
        elementIdentity: identityArtifacts.elementIdentities[index],
        in: childContext,
        authoringScope: authoringScope,
        suppressStructuralLifecycle: true
      )
      let flattened = iteration.consume(
        realized,
        as: .declaredChildren,
        reportDetachedGroup: false
      )
      elementsCache[index] = flattened
      return flattened
    }
  }
}

extension ForEachIndexedChildSource: RowSelectionCachingIndexedChildSource {
  package func retainedRowSelections(
    key: HostedRowSelectionCacheKey,
    build: () -> [HostedCollectionRowSelection]
  ) -> [HostedCollectionRowSelection] {
    guard HostedCollectionResolveReuse.isEnabled else {
      return build()
    }
    if identityArtifacts.rowSelectionsKey == key {
      IndexedChildSourceArtifactsProbe.recordRowSelectionReuse()
      return identityArtifacts.rowSelections
    }
    let rows = build()
    identityArtifacts.rowSelectionsKey = key
    identityArtifacts.rowSelections = rows
    return rows
  }
}

@MainActor
package final class HostedCollectionIndexedChildSource: IndexedChildSource {
  private let base: any IndexedChildSource
  private let transform: @MainActor (ResolvedNode, Int) -> ResolvedNode
  private var cache: [Int: ResolvedNode] = [:]
  private var tableColumnWidths: [Int]?

  package init(
    base: any IndexedChildSource,
    transform: @escaping @MainActor (ResolvedNode, Int) -> ResolvedNode
  ) {
    self.base = base
    self.transform = transform
  }

  nonisolated package var count: Int { base.count }
  nonisolated package var identityRoot: Identity { base.identityRoot }
  nonisolated package var measurementSignature: IndexedChildMeasurementSignature {
    base.measurementSignature
  }

  nonisolated package func child(at index: Int) -> ResolvedNode {
    withCheckedMainActorAccess("HostedCollectionIndexedChildSource.child(at:)") {
      if let cached = cache[index] {
        return cached
      }
      var node = transform(base.child(at: index), index)
      if let tableColumnWidths {
        node = applyingHostedTableColumnWidths(tableColumnWidths, to: node)
      }
      cache[index] = node
      return node
    }
  }

  nonisolated package func childElements(at index: Int) -> [ResolvedNode] {
    [child(at: index)]
  }

  nonisolated package func elementIdentity(at index: Int) -> Identity {
    base.elementIdentity(at: index)
  }

  nonisolated package func elementSelectionTag(at index: Int) -> SelectionTag? {
    base.elementSelectionTag(at: index)
  }

  nonisolated package func elementIndex(forSelectionTag tag: SelectionTag) -> Int? {
    base.elementIndex(forSelectionTag: tag)
  }

  nonisolated package func retainedTableColumnWidths(
    columns: [TableColumnPayload],
    discovered: [Int]
  ) -> [Int] {
    base.retainedTableColumnWidths(columns: columns, discovered: discovered)
  }

  nonisolated package func applyHostedTableColumnWidths(_ widths: [Int]) {
    withCheckedMainActorAccess("HostedCollectionIndexedChildSource.applyTableWidths") {
      tableColumnWidths = widths
      cache = cache.mapValues { applyingHostedTableColumnWidths(widths, to: $0) }
    }
  }
}

@MainActor
private func applyingHostedTableColumnWidths(
  _ widths: [Int],
  to source: ResolvedNode
) -> ResolvedNode {
  var node = source
  node.children = node.children.enumerated().map { index, child in
    var child = applyingHostedTableColumnWidths(widths, to: child)
    if child.kind == .view("HostedTableCell"),
      case .frame(_, let height, let alignment) = child.layoutBehavior,
      widths.indices.contains(index)
    {
      child.layoutBehavior = .frame(width: widths[index], height: height, alignment: alignment)
    }
    return child
  }
  return node
}

extension ForEach: IndexedChildSourceView {
  package func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)? {
    ForEachIndexedChildSource(
      data: data,
      id: id,
      content: content,
      childContext: childContext
    )
  }
}

extension Group: IndexedChildSourceView {
  package func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)? {
    makeIndexedChildSource(
      from: content,
      in: childContext
    )
  }
}

extension TupleView: IndexedChildSourceView {
  package func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)? {
    var sources: [any IndexedChildSource] = []

    for child in repeat each value {
      guard let source = makeIndexedChildSource(from: child, in: childContext) else {
        return nil
      }
      sources.append(source)
    }

    guard sources.count == 1 else {
      return nil
    }
    return sources[0]
  }
}

extension ConditionalContent: IndexedChildSourceView {
  package func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)? {
    switch storage {
    case .trueContent(let content):
      let branchContext = childContext.child(component: .init(rawValue: "true"))
      return makeIndexedChildSource(from: content, in: branchContext)
    case .falseContent(let content):
      let branchContext = childContext.child(component: .init(rawValue: "false"))
      return makeIndexedChildSource(from: content, in: branchContext)
    }
  }
}

extension VariadicView: IndexedChildSourceView {
  package func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)? {
    guard content.count == 1, let element = content.first else {
      return nil
    }

    return makeIndexedChildSource(from: element, in: childContext)
  }
}

@MainActor
package func makeIndexedChildSource<V: View>(
  from view: V,
  in childContext: ResolveContext
) -> (any IndexedChildSource)? {
  let erased: Any = view
  guard let provider = erased as? any IndexedChildSourceView else {
    return nil
  }

  return provider.indexedChildSource(in: childContext)
}
