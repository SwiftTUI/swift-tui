import SwiftTUICore

@MainActor
package final class DeclaredChildrenWorkState {
  package var nextIndex = 0
  package var nodes: [ResolvedNode] = []
}

@MainActor
package func appendDeclaredChildWork<V: View>(
  _ view: V, in context: ResolveContext, kindName: String,
  into state: DeclaredChildrenWorkState
) -> ResolveWork<Void> {
  .deferred {
    if let structural = view as? any DeclaredChildrenView {
      return structural.appendDeclaredChildrenWork(in: context, kindName: kindName, into: state)
    }
    let childContext = context.indexedChild(kind: .init(rawValue: kindName), index: state.nextIndex)
    state.nextIndex += 1
    return resolvingStyleRouteAlternative {
      if context.viewGraph != nil {
        return resolveViewWork(view, in: childContext).map { node in
          state.nodes.append(
            contentsOf: consumeDeclaredChild(
              node, resolvedUnder: childContext.identity, in: context.viewGraph,
              policy: .declaredBuilder))
        }
      }
      return resolveViewElementsWork(view, in: childContext).map { elements in
        childContext.recordResolvedComputation(count: elements.count)
        state.nodes.append(contentsOf: elements)
      }
    }
  }
}

@MainActor
package func resolveDeclaredChildrenWork<V: View>(
  _ view: V, in context: ResolveContext, kindName: String
) -> ResolveWork<[ResolvedNode]> {
  .deferred {
    let state = DeclaredChildrenWorkState()
    return appendDeclaredChildWork(view, in: context, kindName: kindName, into: state).map {
      assignEntityIdentityOccurrences(to: &state.nodes)
      return state.nodes
    }
  }
}

@MainActor
package func resolveSequentially<Element>(
  _ elements: [Element], _ operation: @escaping @MainActor (Element) -> ResolveWork<Void>
) -> ResolveWork<Void> {
  func next(_ index: Int) -> ResolveWork<Void> {
    .deferred {
      guard index < elements.count else { return .value(()) }
      return operation(elements[index]).flatMap { next(index + 1) }
    }
  }
  return next(0)
}
