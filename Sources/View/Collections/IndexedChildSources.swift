package import Core

@MainActor
package protocol IndexedChildSourceView {
  func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)?
}

package struct ForEachIndexedChildSource<Data, ID, Content>: IndexedChildSource, @unchecked Sendable
where Data: RandomAccessCollection, ID: Hashable, Content: View {
  private final class ChildCache {
    var storage: [Int: ResolvedNode] = [:]
  }

  package let count: Int
  package let identityRoot: Identity
  package let measurementSignature: String

  private let data: Data
  private let id: KeyPath<Data.Element, ID>
  private let content: @MainActor (Data.Element) -> Content
  private let childContext: ResolveContext
  private let cache = ChildCache()

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
    identityRoot = childContext.identity
    count = data.count
    measurementSignature = data.map {
      childContext.identity.explicitID($0[keyPath: id]).path
    }.joined(separator: "|")
  }

  package func child(at index: Int) -> ResolvedNode {
    MainActor.assumeIsolated {
      if let cached = cache.storage[index] {
        return cached
      }

      let dataIndex = data.index(data.startIndex, offsetBy: index)
      let element = data[dataIndex]
      let elementContext = childContext.replacingIdentity(
        with: childContext.identity.explicitID(element[keyPath: id])
      )
      if let reused = elementContext.reusedResolvedSubtreeIfAvailable() {
        cache.storage[index] = reused
        return reused
      }
      let view = elementContext.trackingObservableAccess {
        content(element)
      }
      let elements = resolveViewElements(view, in: elementContext)
      elementContext.recordResolvedComputation(count: elements.count)
      let normalized = normalizeResolvedElements(elements, in: elementContext)
      cache.storage[index] = normalized
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
      return makeIndexedChildSource(from: content, in: childContext)
    case .falseContent(let content):
      return makeIndexedChildSource(from: content, in: childContext)
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
