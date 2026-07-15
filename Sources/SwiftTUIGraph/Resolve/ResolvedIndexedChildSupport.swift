/// Fingerprint of a lazy container's element-identity sequence, compared by
/// the resolve/measure/place equivalence gates to prove the container's data
/// membership and order unchanged.
///
/// Equality is byte-exact: the `(elementCount, contentHash)` prefilter can
/// only *reject* (paths equal implies both match), and a prefilter tie falls
/// back to comparing the joined element-identity paths — a hash collision can
/// never prove a false equivalence. The O(1) fast path on the *equal* side is
/// storage identity: sources that adopt a container's retained identity
/// artifacts across resolves share the storage box, so the common
/// unchanged-data comparison never touches the path bytes (F145; the joined
/// string was previously rebuilt per resolve and compared byte-wise per
/// equivalence check).
package struct IndexedChildMeasurementSignature: Equatable, Sendable,
  CustomDebugStringConvertible
{
  package let elementCount: Int
  private let contentHash: Int
  private let storage: Storage

  private final class Storage: Sendable {
    let joinedElementPaths: String

    init(joinedElementPaths: String) {
      self.joinedElementPaths = joinedElementPaths
    }
  }

  package init(elementPaths: some Sequence<String>) {
    var joined = ""
    var hasher = Hasher()
    var count = 0
    for path in elementPaths {
      if count > 0 {
        joined.append("|")
      }
      joined.append(path)
      hasher.combine(path)
      count += 1
    }
    elementCount = count
    contentHash = hasher.finalize()
    storage = Storage(joinedElementPaths: joined)
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    if lhs.storage === rhs.storage {
      return true
    }
    guard lhs.elementCount == rhs.elementCount, lhs.contentHash == rhs.contentHash else {
      return false
    }
    return lhs.storage.joinedElementPaths == rhs.storage.joinedElementPaths
  }

  /// The storage box's identity — lets tests pin that adoption shares the box
  /// (the pointer-equal fast path) rather than merely comparing equal.
  package var storageIdentifier: ObjectIdentifier {
    ObjectIdentifier(storage)
  }

  package var debugDescription: String {
    storage.joinedElementPaths
  }
}

/// Marker for the per-container identity artifacts a lazy indexed-child
/// source retains across container resolves (F145). Concrete conformers live
/// with the sources (the authoring layer); the graph only stores them on the
/// hosting `ViewNode`, keyed by the container's child-context identity.
/// Entries are pure derived memoization — the adopting source content-verifies
/// them (element ids + identity root + entity scope) before use, so a stale
/// entry can only miss, never corrupt.
package protocol RetainedIndexedChildSourceArtifacts: AnyObject {}

/// Indexed child access for data-backed lazy containers.
package protocol IndexedChildSource: Sendable {
  var count: Int { get }
  var identityRoot: Identity { get }
  var measurementSignature: IndexedChildMeasurementSignature { get }
  var canRunOnWorker: Bool { get }
  var workerResolvedChildren: [ResolvedNode]? { get }

  func child(at index: Int) -> ResolvedNode

  /// The stack cells one element contributes: a multi-view element (a
  /// TupleView row, a nested ForEach) realizes as a synthesized Group whose
  /// children must join the enclosing stack as individual cells — exactly
  /// the eager path's group-splice arm. Elements that realize to a single
  /// view contribute themselves (the default).
  func childElements(at index: Int) -> [ResolvedNode]
}

extension IndexedChildSource {
  package var canRunOnWorker: Bool { false }
  package var workerResolvedChildren: [ResolvedNode]? { nil }

  package func childElements(at index: Int) -> [ResolvedNode] {
    [child(at: index)]
  }
}

/// Resolve-time aggregate of every layout-offload disqualifier in a subtree.
///
/// `count`/`firstIdentity` keep their original meaning — main-actor-only
/// *custom layouts* — because they feed the `customLayoutFallbackCount`
/// diagnostic channel (TSV column, drop-eligibility blocker). The two
/// additional counters cover the remaining offload disqualifiers so the
/// frame-tail eligibility queries are O(1) summary reads instead of
/// full-tree scans (F35).
package struct CustomLayoutFallbackSummary: Equatable, Sendable {
  package var count: Int
  package var firstIdentity: Identity?
  /// Indexed child sources in the subtree whose `canRunOnWorker` is `false`.
  package var mainActorOnlyIndexedChildSourceCount: Int
  /// Layout-realized content boundaries in the subtree.
  package var layoutRealizedContentCount: Int

  package init(
    count: Int = 0,
    firstIdentity: Identity? = nil,
    mainActorOnlyIndexedChildSourceCount: Int = 0,
    layoutRealizedContentCount: Int = 0
  ) {
    self.count = count
    self.firstIdentity = firstIdentity
    self.mainActorOnlyIndexedChildSourceCount = mainActorOnlyIndexedChildSourceCount
    self.layoutRealizedContentCount = layoutRealizedContentCount
  }

  package mutating func record(_ identity: Identity) {
    count += 1
    if firstIdentity == nil {
      firstIdentity = identity
    }
  }

  package mutating func recordMainActorOnlyIndexedChildSource() {
    mainActorOnlyIndexedChildSourceCount += 1
  }

  package mutating func recordLayoutRealizedContent() {
    layoutRealizedContentCount += 1
  }

  package mutating func merge(_ other: Self) {
    count += other.count
    if firstIdentity == nil {
      firstIdentity = other.firstIdentity
    }
    mainActorOnlyIndexedChildSourceCount += other.mainActorOnlyIndexedChildSourceCount
    layoutRealizedContentCount += other.layoutRealizedContentCount
  }
}

/// Sendable resolved-child snapshot for lazy indexed containers that have
/// already materialized their authored children on the main actor.
package struct IndexedChildSourceSnapshot: IndexedChildSource {
  package let identityRoot: Identity
  package let measurementSignature: IndexedChildMeasurementSignature
  private let children: [ResolvedNode]

  package init(
    identityRoot: Identity,
    measurementSignature: IndexedChildMeasurementSignature,
    children: [ResolvedNode]
  ) {
    self.identityRoot = identityRoot
    self.measurementSignature = measurementSignature
    self.children = children
  }

  package var count: Int {
    children.count
  }

  package var canRunOnWorker: Bool {
    true
  }

  package var workerResolvedChildren: [ResolvedNode]? {
    children
  }

  package func child(at index: Int) -> ResolvedNode {
    children[index]
  }
}

extension ResolvedNode {
  package var usesIndexedChildSource: Bool {
    indexedChildSource != nil
  }
}
