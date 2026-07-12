package import SwiftTUICore
package import SwiftTUIGraph

@MainActor
package protocol IndexedChildSourceView {
  func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)?
}

@MainActor
package final class ForEachIndexedChildSource<Data, ID, Content>: IndexedChildSource
where Data: RandomAccessCollection, ID: Hashable & Sendable, Content: View {
  private let countStorage: Int
  private let identityRootStorage: Identity
  private let measurementSignatureStorage: String

  private let data: Data
  private let id: KeyPath<Data.Element, ID>
  private let entityIdentities: [EntityIdentity]
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
    entityIdentities = makeEntityIdentities(
      for: data,
      id: id,
      scope: childContext.structuralPath
    )
    authoringScope = currentAuthoringContext()
    mintHost = ViewNodeContext.current
    identityRootStorage = childContext.identity
    countStorage = data.count
    measurementSignatureStorage = data.map {
      childContext.identity.explicitID($0[keyPath: id]).path
    }.joined(separator: "|")
  }

  nonisolated package var count: Int {
    withCheckedMainActorAccess("IndexedChildSource.count") { countStorage }
  }

  nonisolated package var identityRoot: Identity {
    withCheckedMainActorAccess("IndexedChildSource.identityRoot") { identityRootStorage }
  }

  nonisolated package var measurementSignature: String {
    withCheckedMainActorAccess("IndexedChildSource.measurementSignature") {
      measurementSignatureStorage
    }
  }

  nonisolated package func child(at index: Int) -> ResolvedNode {
    withCheckedMainActorAccess("IndexedChildSource.child(at:)") {
      if let cached = cache[index] {
        return cached
      }

      let dataIndex = data.index(data.startIndex, offsetBy: index)
      let element = data[dataIndex]
      let structuralElementContext = childContext.indexedChild(
        kind: .init(rawValue: "ForEachElement"),
        index: index
      )
      let elementContext = structuralElementContext.replacingIdentity(
        with: childContext.identity.explicitID(element[keyPath: id])
      )
      .suppressingStructuralLifecycle()
      // Mirror `ForEach.resolveElements`: diverge structural identity
      // per iteration so identity-deriving modifiers (`.panel()`) see
      // a distinct position per element, while `viewIdentity` stays
      // pinned to the outer authoring scope so owner-semantics callers
      // (controls, @State) remain stable.
      let perIterationScope = authoringScope.map { scope in
        AuthoringContext(
          viewIdentity: scope.viewIdentity,
          structuralIdentity: elementContext.identity,
          structuralPath: elementContext.structuralPath,
          focusedValues: scope.focusedValues,
          viewNode: scope.viewNode,
          ownerNodeID: scope.ownerNodeID,
          stateGraphScope: scope.stateGraphScope,
          ordinalTracker: scope.ordinalTracker
        )
      }
      let view = withAuthoringContext(perIterationScope) {
        elementContext.trackingObservableAccess {
          content(element)
        }
      }
      let route = ResolveEntityRoute(
        identity: entityIdentities[index],
        structuralPath: elementContext.structuralPath
      )
      var normalized = withAuthoringContext(perIterationScope) {
        withResolveEntityRoute(route) {
          resolveView(view, in: elementContext)
        }
      }
      normalized.attachResolvedForEachEntity(
        entityIdentities[index],
        at: elementContext.structuralPath
      )
      childContext.viewGraph?.refreshResolvedMetadata(for: normalized)
      // The realized element joins no children array — the container's
      // resolved node keeps its lazy source instead of child nodes — so the
      // mint would strand alive in the store when the container departs (the
      // F04/F91 teardown-coherence leak; the gallery collections-tab
      // warning). Anchor it to the host captured at declaration so that
      // host's teardown retires realized elements through the standard
      // cascade.
      childContext.viewGraph?.recordDetachedHostedSubtree(
        normalized,
        hostedBy: mintHost
      )
      cache[index] = normalized
      return normalized
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
      let elementIdentity = childContext.identity.explicitID(element[keyPath: id])
      let flattened: [ResolvedNode]
      if realized.identity == elementIdentity,
        realized.kind == .view("EmptyView")
      {
        flattened = []
      } else if realized.identity == elementIdentity,
        realized.kind == .view("Group")
      {
        flattened = realized.children
      } else {
        flattened = [realized]
      }
      elementsCache[index] = flattened
      return flattened
    }
  }
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
