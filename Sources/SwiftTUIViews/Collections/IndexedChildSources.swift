package import SwiftTUICore

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
  private var cache: [Int: ResolvedNode] = [:]

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
    entityIdentities = makeEntityIdentities(for: data, id: id)
    authoringScope = currentAuthoringContext()
    identityRootStorage = childContext.identity
    countStorage = data.count
    measurementSignatureStorage = data.map {
      childContext.identity.explicitID($0[keyPath: id]).path
    }.joined(separator: "|")
  }

  nonisolated package var count: Int {
    MainActor.assumeIsolated { countStorage }
  }

  nonisolated package var identityRoot: Identity {
    MainActor.assumeIsolated { identityRootStorage }
  }

  nonisolated package var measurementSignature: String {
    MainActor.assumeIsolated { measurementSignatureStorage }
  }

  nonisolated package func child(at index: Int) -> ResolvedNode {
    MainActor.assumeIsolated {
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
          ordinalTracker: scope.ordinalTracker
        )
      }
      let view = withAuthoringContext(perIterationScope) {
        elementContext.trackingObservableAccess {
          content(element)
        }
      }
      var normalized = withAuthoringContext(perIterationScope) {
        resolveView(view, in: elementContext)
      }
      normalized.attachResolvedForEachEntity(
        entityIdentities[index],
        at: elementContext.structuralPath
      )
      childContext.viewGraph?.refreshResolvedMetadata(for: normalized)
      cache[index] = normalized
      return normalized
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
