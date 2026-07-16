import SwiftTUICore

/// One fully-derived `ForEach` element traversal.
///
/// Every consumer — eager resolution, declared-child enumeration, lazy indexed
/// realization, and deferred scoped/portal payloads — must construct elements
/// through this type. It owns the five coupled pieces that previously drifted:
/// identity-projection entity scope, duplicate occurrence, explicit element
/// identity, per-iteration authoring scope, and entity-route attachment.
@MainActor
package struct ForEachIteration<Element> {
  package enum ConsumptionMode {
    /// Preserve the normalized per-element node for enumerated or indexed
    /// callers that own realization and caching themselves.
    case normalizedNode
    /// Match declared-builder traversal: omit an unmodified empty element and
    /// splice an unmodified group element into its enclosing container.
    case declaredChildren
  }

  package let element: Element
  package let offset: Int
  package let entityIdentity: EntityIdentity
  package let context: ResolveContext
  package let authoringContext: AuthoringContext?

  package func makeView<Content: View>(
    _ content: @MainActor (Element) -> Content
  ) -> Content {
    withAuthoringContext(authoringContext) {
      context.trackingObservableAccess {
        content(element)
      }
    }
  }

  package func resolve<Content: View>(
    _ view: Content
  ) -> ResolvedNode {
    let route = ResolveEntityRoute(
      identity: entityIdentity,
      structuralPath: context.structuralPath
    )
    var resolved = withAuthoringContext(authoringContext) {
      withResolveEntityRoute(route) {
        resolveView(view, in: context)
      }
    }
    resolved.attachResolvedForEachEntity(
      entityIdentity,
      at: context.structuralPath
    )
    context.viewGraph?.refreshResolvedMetadata(for: resolved)
    return resolved
  }

  package func resolve<Content: View>(
    content: @MainActor (Element) -> Content
  ) -> ResolvedNode {
    resolve(makeView(content))
  }

  package func resolveElements<Content: View>(
    content: @MainActor (Element) -> Content,
    consumingAs mode: ConsumptionMode
  ) -> [ResolvedNode] {
    consume(resolve(content: content), as: mode)
  }

  package func consume(
    _ resolved: ResolvedNode,
    as mode: ConsumptionMode,
    reportDetachedGroup: Bool = true
  ) -> [ResolvedNode] {
    switch mode {
    case .normalizedNode:
      return [resolved]
    case .declaredChildren:
      if resolved.identity == context.identity,
        resolved.kind == .view("EmptyView")
      {
        return []
      }
      if resolved.identity == context.identity,
        resolved.kind == .view("Group")
      {
        if reportDetachedGroup {
          context.viewGraph?.reportDetachedResolvedLifetimeResult(resolved)
        }
        return resolved.children
      }
      return [resolved]
    }
  }
}

@MainActor
package func makeForEachIterations<Data, ID>(
  data: Data,
  id: KeyPath<Data.Element, ID>,
  in context: ResolveContext,
  authoringScope: AuthoringContext?,
  entityIdentities suppliedEntityIdentities: [EntityIdentity]? = nil,
  suppressStructuralLifecycle: Bool = false
) -> [ForEachIteration<Data.Element>]
where Data: RandomAccessCollection, ID: Hashable & Sendable {
  let ids = data.map { $0[keyPath: id] }
  let occurrences = makeForEachOccurrences(ids: ids)
  if let suppliedEntityIdentities {
    precondition(
      suppliedEntityIdentities.count == ids.count,
      "ForEach iteration identities must be total over the source collection."
    )
  }

  var iterations: [ForEachIteration<Data.Element>] = []
  iterations.reserveCapacity(ids.count)
  var offset = 0
  for element in data {
    iterations.append(
      makeForEachIteration(
        element: element,
        id: ids[offset],
        offset: offset,
        occurrence: occurrences[offset],
        entityIdentity: suppliedEntityIdentities?[offset],
        in: context,
        authoringScope: authoringScope,
        suppressStructuralLifecycle: suppressStructuralLifecycle
      )
    )
    offset += 1
  }
  return iterations
}

@MainActor
package func makeForEachIteration<Element, ID>(
  element: Element,
  id: ID,
  offset: Int,
  occurrence: Int,
  entityIdentity suppliedEntityIdentity: EntityIdentity? = nil,
  in context: ResolveContext,
  authoringScope: AuthoringContext?,
  suppressStructuralLifecycle: Bool = false
) -> ForEachIteration<Element>
where ID: Hashable & Sendable {
  let entityIdentity =
    suppliedEntityIdentity
    ?? EntityIdentity(
      forEachValue: id,
      occurrence: occurrence,
      scope: forEachEntityScope(identityRoot: context.identity)
    )
  precondition(
    entityIdentity.occurrence == occurrence,
    "ForEach iteration occurrence must match its entity identity."
  )
  let structuralElementContext = context.indexedChild(
    kind: .init(rawValue: "ForEachElement"),
    index: offset
  )
  var elementContext = structuralElementContext.replacingIdentity(
    with: context.identity.explicitID(
      id,
      occurrence: entityIdentity.occurrence
    )
  )
  if suppressStructuralLifecycle {
    elementContext = elementContext.suppressingStructuralLifecycle()
  }

  return ForEachIteration(
    element: element,
    offset: offset,
    entityIdentity: entityIdentity,
    context: elementContext,
    authoringContext: forEachIterationAuthoringContext(
      authoringScope,
      elementContext: elementContext
    )
  )
}

package func forEachEntityScope(
  identityRoot: Identity
) -> StructuralPath {
  StructuralPath(identity: identityRoot)
}

@MainActor
private func forEachIterationAuthoringContext(
  _ scope: AuthoringContext?,
  elementContext: ResolveContext
) -> AuthoringContext? {
  scope.map { scope in
    AuthoringContext(
      viewIdentity: scope.viewIdentity,
      structuralIdentity: elementContext.identity,
      structuralPath: elementContext.structuralPath,
      focusedValues: scope.focusedValues,
      viewNode: scope.viewNode,
      ownerNodeID: scope.ownerNodeID,
      stateGraphScope: scope.stateGraphScope,
      ordinalTracker: scope.ordinalTracker,
      rebasedFromOwnerNodeID: scope.rebasedFromOwnerNodeID
    )
  }
}
