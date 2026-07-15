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
    // The entity scope disambiguates this ForEach instance's element keys
    // from another instance's equal id values. It must be the *identity*
    // projection, not the positional structural path: a structural scope
    // embeds every ancestor's sibling offset, so an outer reorder re-keys
    // every inner element (evicting live rows' state) and can collide one
    // outer element's fresh key with its sibling's departed key in the
    // global routing table (adopting the wrong row's state). Identity is
    // position-independent across reorders and still distinct per instance.
    let entityIdentities = makeEntityIdentities(
      for: data,
      id: id,
      scope: StructuralPath(identity: context.identity)
    )
    var elementOffset = 0
    for element in data {
      let currentElementOffset = elementOffset
      let structuralElementContext = context.indexedChild(
        kind: .init(rawValue: "ForEachElement"),
        index: currentElementOffset
      )
      elementOffset += 1
      let entityIdentity = entityIdentities[currentElementOffset]
      // Occurrence-qualified element identity: a duplicate id's later
      // occurrences resolve their subtrees under a distinct identity, so
      // interior nodes, action registrations, and state slots stay
      // per-occurrence instead of last-write-winning on the primary's keys
      // (occurrence 0 keeps the plain explicit-ID path unchanged).
      let elementContext = structuralElementContext.replacingIdentity(
        with: context.identity.explicitID(
          element[keyPath: id],
          occurrence: entityIdentity.occurrence
        )
      )
      // Diverge structural identity per iteration so identity-deriving
      // modifiers such as `.panel()` (which reads
      // `scope.structuralIdentity`) see distinct positions for each
      // element, while `viewIdentity` keeps pointing at the outer
      // authoring view — this preserves invalidation routing and
      // `@State` ownership for any closures that captured the scope
      // (Button/Menu/Link/Picker/Stepper/TabView/value controls).
      let perIterationScope = dynamicPropertyScope.map { scope in
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
        identity: entityIdentity,
        structuralPath: elementContext.structuralPath
      )
      var elementNode = withAuthoringContext(perIterationScope) {
        withResolveEntityRoute(route) {
          resolveView(view, in: elementContext)
        }
      }
      elementNode.attachResolvedForEachEntity(
        entityIdentity,
        at: elementContext.structuralPath
      )
      context.viewGraph?.refreshResolvedMetadata(for: elementNode)
      if elementNode.identity == elementContext.identity,
        elementNode.kind == .view("EmptyView")
      {
        continue
      }
      if elementNode.identity == elementContext.identity,
        elementNode.kind == .view("Group")
      {
        // Splicing lifts the row's children into the enclosing container, so
        // the row's own mint (the node carrying this iteration's entity route
        // and any row-scoped state) appears in no committed value afterwards
        // — reachable through neither children arrays nor parent links.
        // Resolve-lifetime scope automatically owns that mint at the nearest
        // declaring host; the spliced children are committed normally.
        context.viewGraph?.reportDetachedResolvedLifetimeResult(elementNode)
        resolved.append(contentsOf: elementNode.children)
      } else {
        resolved.append(elementNode)
      }
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
    into children: inout [ScopedContentPayload]
  ) {
    for element in data {
      let view = withAuthoringContext(authoringScope) {
        content(element)
      }
      appendScopedDeclaredBuilderChildren(
        from: view,
        into: &children
      )
    }
  }

  package func appendPortalDeclaredChildren(
    into children: inout [PortalAttachmentContentPayload]
  ) {
    for element in data {
      let view = withAuthoringContext(authoringScope) {
        content(element)
      }
      appendPortalDeclaredBuilderChildren(
        from: view,
        into: &children
      )
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
    let dynamicPropertyScope = currentAuthoringContext() ?? authoringScope
    let entityIdentities = makeEntityIdentities(
      for: data,
      id: id,
      scope: childContext.structuralPath
    )

    var elementOffset = 0
    for element in data {
      let currentElementOffset = elementOffset
      let structuralElementContext = childContext.indexedChild(
        kind: .init(rawValue: "ForEachElement"),
        index: currentElementOffset
      )
      elementOffset += 1
      let entityIdentity = entityIdentities[currentElementOffset]
      let elementContext = structuralElementContext.replacingIdentity(
        with: childContext.identity.explicitID(element[keyPath: id])
      )
      let perIterationScope = dynamicPropertyScope.map { scope in
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

      visitor(view, elementContext) {
        let route = ResolveEntityRoute(
          identity: entityIdentity,
          structuralPath: elementContext.structuralPath
        )
        var resolved = withAuthoringContext(perIterationScope) {
          withResolveEntityRoute(route) {
            resolveView(view, in: elementContext)
          }
        }
        resolved.attachResolvedForEachEntity(
          entityIdentity,
          at: elementContext.structuralPath
        )
        context.viewGraph?.refreshResolvedMetadata(for: resolved)
        return resolved
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
  var counts: [ID: Int] = [:]
  var identities: [EntityIdentity] = []
  identities.reserveCapacity(ids.count)

  for value in ids {
    let occurrence = counts[value, default: 0]
    counts[value] = occurrence + 1
    identities.append(
      EntityIdentity(
        forEachValue: value,
        occurrence: occurrence,
        scope: scope
      )
    )
  }

  return identities
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
