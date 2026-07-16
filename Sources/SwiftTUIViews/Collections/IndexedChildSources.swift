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

  package static func recordAdoption() {
    #if DEBUG
      adoptionCount += 1
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
    #endif
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
  var tableColumns: [TableColumnPayload]?
  var tableColumnWidths: [Int] = []

  init(
    identityRoot: Identity,
    scope: StructuralPath,
    ids: [ID],
    entityIdentities: [EntityIdentity],
    signature: IndexedChildMeasurementSignature
  ) {
    self.identityRoot = identityRoot
    self.scope = scope
    self.ids = ids
    self.entityIdentities = entityIdentities
    self.signature = signature
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

    let ids = data.map { $0[keyPath: id] }
    self.ids = ids
    let scope = forEachEntityScope(identityRoot: childContext.identity)
    if let retained = host?.retainedIndexedChildSourceArtifacts(
      forIdentityRoot: childContext.identity
    ) as? ForEachSourceIdentityArtifacts<ID>,
      retained.matches(ids: ids, identityRoot: childContext.identity, scope: scope)
    {
      IndexedChildSourceArtifactsProbe.recordAdoption()
      entityIdentities = retained.entityIdentities
      measurementSignatureStorage = retained.signature
      identityArtifacts = retained
    } else {
      IndexedChildSourceArtifactsProbe.recordFreshMint()
      entityIdentities = makeEntityIdentities(ids: ids, scope: scope)
      measurementSignatureStorage = IndexedChildMeasurementSignature(
        elementPaths: zip(ids, entityIdentities).lazy.map { id, entityIdentity in
          childContext.identity.explicitID(
            id,
            occurrence: entityIdentity.occurrence
          ).path
        }
      )
      let artifacts = ForEachSourceIdentityArtifacts(
        identityRoot: childContext.identity,
        scope: scope,
        ids: ids,
        entityIdentities: entityIdentities,
        signature: measurementSignatureStorage
      )
      identityArtifacts = artifacts
      host?.retainIndexedChildSourceArtifacts(
        artifacts,
        forIdentityRoot: childContext.identity
      )
    }
  }

  nonisolated package var count: Int {
    withCheckedMainActorAccess("IndexedChildSource.count") { countStorage }
  }

  nonisolated package var identityRoot: Identity {
    withCheckedMainActorAccess("IndexedChildSource.identityRoot") { identityRootStorage }
  }

  nonisolated package var measurementSignature: IndexedChildMeasurementSignature {
    withCheckedMainActorAccess("IndexedChildSource.measurementSignature") {
      measurementSignatureStorage
    }
  }

  nonisolated package func child(at index: Int) -> ResolvedNode {
    withCheckedMainActorAccess("IndexedChildSource.child(at:)") {
      if let cached = cache[index] {
        return cached
      }

      let realize = { [self] () -> ResolvedNode in
        let dataIndex = data.index(data.startIndex, offsetBy: index)
        let element = data[dataIndex]
        let iteration = makeForEachIteration(
          element: element,
          id: element[keyPath: id],
          offset: index,
          occurrence: entityIdentities[index].occurrence,
          entityIdentity: entityIdentities[index],
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
      identityRootStorage.explicitID(
        ids[index],
        occurrence: entityIdentities[index].occurrence
      )
    }
  }

  nonisolated package func elementSelectionTag(at index: Int) -> SelectionTag? {
    withCheckedMainActorAccess("IndexedChildSource.elementSelectionTag(at:)") {
      SelectionTag(value: ids[index], includeOptional: true)
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
