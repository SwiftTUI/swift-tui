package import Core

@MainActor
package protocol IndexedChildSourceView {
  func indexedChildSource(
    in childContext: ResolveContext
  ) -> (any IndexedChildSource)?
}

@MainActor
package final class ForEachIndexedChildSource<Data, ID, Content>: IndexedChildSource
where Data: RandomAccessCollection, ID: Hashable, Content: View {
  private let countStorage: Int
  private let identityRootStorage: Identity
  private let measurementSignatureStorage: String

  private let data: Data
  private let id: KeyPath<Data.Element, ID>
  private let content: @MainActor (Data.Element) -> Content
  private let childContext: ResolveContext
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
      let elementContext = childContext.replacingIdentity(
        with: childContext.identity.explicitID(element[keyPath: id])
      )
      let view = elementContext.trackingObservableAccess {
        content(element)
      }
      let elements = resolveViewElements(view, in: elementContext)
      elementContext.recordResolvedComputation(count: elements.count)
      let normalized = normalizeResolvedElements(elements, in: elementContext)
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
