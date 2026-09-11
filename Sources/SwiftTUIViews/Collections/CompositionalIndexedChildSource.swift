/// Structural builder traversal shared by eager declared children and lazy stacks.
/// ForEach is a leaf here: discovering a source never executes its row producers.
@MainActor
package protocol DeclaredChildStructure {
  func appendDeclaredStructure(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into result: inout DeclaredChildAccumulator
  )
}

@MainActor
package struct DeclaredChildAccumulator {
  let indexed: Bool
  var nodes: [ResolvedNode] = []
  var sources: [any IndexedChildSource] = []

  mutating func normalizeOccurrences() {
    assignEntityIdentityOccurrences(to: &nodes)
  }

  mutating func append(_ other: Self) {
    nodes.append(contentsOf: other.nodes)
    sources.append(contentsOf: other.sources)
  }
}

@MainActor
package func appendDeclaredContent<V: View>(
  _ view: V,
  in context: ResolveContext,
  kindName: String,
  nextIndex: inout Int,
  into result: inout DeclaredChildAccumulator
) {
  if let structure = view as? any DeclaredChildStructure {
    structure.appendDeclaredStructure(
      in: context, kindName: kindName, nextIndex: &nextIndex, into: &result
    )
    return
  }
  if result.indexed, let provider = view as? any IndexedChildSourceView {
    let childContext = context.indexedChild(kind: .init(rawValue: kindName), index: nextIndex)
    if let source = provider.indexedChildSource(in: childContext) {
      nextIndex += 1
      result.sources.append(source)
      return
    }
  }
  var nodes: [ResolvedNode] = []
  appendDeclaredChildNodes(
    view, in: context, kindName: kindName, nextIndex: &nextIndex, into: &nodes
  )
  if result.indexed {
    for node in nodes {
      context.viewGraph?.reportDetachedResolvedLifetimeResult(node)
      result.sources.append(
        IndexedChildSourceSnapshot(
          identityRoot: node.identity,
          measurementSignature: .init(elementPaths: [node.identity.path]),
          children: [node]
        ))
    }
  } else {
    result.nodes.append(contentsOf: nodes)
  }
}

@MainActor
package func makeCompositionalIndexedChildSource<V: View>(
  from view: V, in context: ResolveContext, kindName: String
) -> any IndexedChildSource {
  var result = DeclaredChildAccumulator(indexed: true)
  var nextIndex = 0
  appendDeclaredContent(
    view, in: context, kindName: kindName, nextIndex: &nextIndex, into: &result
  )
  return CompositionalIndexedChildSource(identityRoot: context.identity, sources: result.sources)
}

/// Addresses logical elements across authored segments without changing their identities.
/// Every segment belongs to this resolve generation, including its live producer.
package struct CompositionalIndexedChildSource: IndexedChildSource {
  package let identityRoot: Identity
  package let measurementSignature: IndexedChildMeasurementSignature
  private let sources: [any IndexedChildSource]
  private let ends: [Int]
  package let count: Int

  package init(identityRoot: Identity, sources: [any IndexedChildSource]) {
    self.identityRoot = identityRoot
    self.sources = sources.filter { $0.count > 0 }
    var count = 0
    ends = self.sources.map {
      count += $0.count
      return count
    }
    self.count = count
    measurementSignature = .init(
      elementPaths: self.sources.flatMap { source in
        (0..<source.count).map { source.elementIdentity(at: $0).path }
      })
  }

  private func address(_ index: Int) -> (any IndexedChildSource, Int) {
    precondition(index >= 0 && index < count)
    var lower = 0
    var upper = ends.count
    while lower < upper {
      let mid = (lower + upper) / 2
      if ends[mid] <= index { lower = mid + 1 } else { upper = mid }
    }
    return (sources[lower], index - (lower == 0 ? 0 : ends[lower - 1]))
  }

  package func child(at index: Int) -> ResolvedNode {
    let (source, local) = address(index)
    return source.child(at: local)
  }

  package func childElements(at index: Int) -> [ResolvedNode] {
    let (source, local) = address(index)
    return source.childElements(at: local)
  }

  package func elementIdentity(at index: Int) -> Identity {
    let (source, local) = address(index)
    return source.elementIdentity(at: local)
  }

  package func elementSelectionTag(at index: Int) -> SelectionTag? {
    let (source, local) = address(index)
    return source.elementSelectionTag(at: local)
  }

  package func estimationSegment(at index: Int) -> Identity {
    let (source, local) = address(index)
    return source.estimationSegment(at: local)
  }

  package func elementIndex(forSelectionTag tag: SelectionTag) -> Int? {
    var start = 0
    for source in sources {
      if let index = source.elementIndex(forSelectionTag: tag) { return start + index }
      start += source.count
    }
    return nil
  }
}
