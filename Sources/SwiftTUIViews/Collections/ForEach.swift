package import SwiftTUICore

/// Generates repeated content from a random-access collection.
public struct ForEach<Data, ID, Content>: PrimitiveView, ResolvableView
where Data: RandomAccessCollection, ID: Hashable & Sendable, Content: View {
  public var data: Data
  public var id: KeyPath<Data.Element, ID>
  package let content: @MainActor (Data.Element) -> Content
  private let authoringScope: AuthoringContext?

  public init(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @ViewBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.data = data
    self.id = id
    self.content = content
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var resolved: [ResolvedNode] = []
    let dynamicPropertyScope = currentAuthoringContext() ?? authoringScope
    let iterations = makeForEachIterations(
      data: data,
      id: id,
      in: context,
      authoringScope: dynamicPropertyScope
    )
    for iteration in iterations {
      resolved.append(
        contentsOf: iteration.resolveElements(
          content: content,
          consumingAs: .declaredChildren
        )
      )
    }
    return resolved
  }
}

extension ForEach: DeclaredChildrenView {
  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    let childContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    resolved.append(contentsOf: resolveElements(in: childContext))
  }

  package func appendScopedDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: String,
    nextIndex: inout Int,
    into children: inout [ScopedContentPayload]
  ) {
    let slotContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    let ids = data.map { $0[keyPath: id] }
    let occurrences = makeForEachOccurrences(ids: ids)
    let iterationAuthoringScope = currentAuthoringContext() ?? authoringScope

    var offset = 0
    for element in data {
      let currentOffset = offset
      let id = ids[offset]
      let occurrence = occurrences[offset]
      children.append(
        ScopedContentPayload(resolveElements: { _, placementRoot in
          let baseContext = slotContext.applying(to: placementRoot)
          let iteration = makeForEachIteration(
            element: element,
            id: id,
            offset: currentOffset,
            occurrence: occurrence,
            in: baseContext,
            authoringScope: iterationAuthoringScope
          )
          return iteration.resolveElements(
            content: content,
            consumingAs: .declaredChildren
          )
        })
      )
      offset += 1
    }
  }

  package func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: String,
    nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  ) {
    let slotContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    let ids = data.map { $0[keyPath: id] }
    let occurrences = makeForEachOccurrences(ids: ids)
    let iterationAuthoringScope = currentAuthoringContext() ?? authoringScope

    var offset = 0
    for element in data {
      let currentOffset = offset
      let id = ids[offset]
      let occurrence = occurrences[offset]
      children.append(
        PortalAttachmentContentPayload(resolveElements: { _, placementRoot in
          let baseContext = slotContext.applying(to: placementRoot)
          let iteration = makeForEachIteration(
            element: element,
            id: id,
            offset: currentOffset,
            occurrence: occurrence,
            in: baseContext,
            authoringScope: iterationAuthoringScope
          )
          return iteration.resolveElements(
            content: content,
            consumingAs: .declaredChildren
          )
        })
      )
      offset += 1
    }
  }

  package func enumerateDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    visitor: (
      _ child: Any,
      _ childContext: ResolveContext,
      _ resolveOne: @escaping @MainActor () -> ResolvedNode
    ) -> Void
  ) {
    let childContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    let iterations = makeForEachIterations(
      data: data,
      id: id,
      in: childContext,
      authoringScope: currentAuthoringContext() ?? authoringScope
    )

    for iteration in iterations {
      let view = iteration.makeView(content)
      visitor(view, iteration.context) {
        iteration.resolve(view)
      }
    }
  }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
  public init(
    _ data: Data,
    @ViewBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.init(data, id: \.id, content: content)
  }
}

extension ForEach where Data == Range<Int>, ID == Int {
  public init(
    _ data: Range<Int>,
    @ViewBuilder content: @escaping @MainActor (Int) -> Content
  ) {
    self.init(data, id: \.self, content: content)
  }
}

package func makeEntityIdentities<Data, ID>(
  for data: Data,
  id: KeyPath<Data.Element, ID>,
  scope: StructuralPath
) -> [EntityIdentity]
where Data: RandomAccessCollection, ID: Hashable & Sendable {
  makeEntityIdentities(
    ids: data.map { $0[keyPath: id] },
    scope: scope
  )
}

package func makeEntityIdentities<ID>(
  ids: [ID],
  scope: StructuralPath
) -> [EntityIdentity]
where ID: Hashable & Sendable {
  zip(ids, makeForEachOccurrences(ids: ids)).map { value, occurrence in
    EntityIdentity(
      forEachValue: value,
      occurrence: occurrence,
      scope: scope
    )
  }
}

package func makeForEachOccurrences<ID>(
  ids: [ID]
) -> [Int]
where ID: Hashable & Sendable {
  var counts: [ID: Int] = [:]
  return ids.map { value in
    let occurrence = counts[value, default: 0]
    counts[value] = occurrence + 1
    return occurrence
  }
}

extension ResolvedNode {
  mutating func attachResolvedForEachEntity(
    _ entityIdentity: EntityIdentity,
    at entityStructuralPath: StructuralPath
  ) {
    if kind == .view("Group") {
      for index in children.indices {
        children[index].attachingEntityIdentity(
          entityIdentity,
          at: entityStructuralPath
        )
      }
    } else {
      attachingEntityIdentity(
        entityIdentity,
        at: entityStructuralPath
      )
    }
  }
}
