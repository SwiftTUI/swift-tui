import SwiftTUICore

extension Group {
  package func appendDeclaredChildrenWork(
    in context: ResolveContext, kindName: String, into state: DeclaredChildrenWorkState
  ) -> ResolveWork<Void> {
    .deferred {
      let childContext = context.indexedChild(
        kind: .init(rawValue: kindName), index: state.nextIndex)
      state.nextIndex += 1
      return resolveDeclaredChildrenWork(content, in: childContext, kindName: "Group").map {
        state.nodes.append(contentsOf: $0)
      }
    }
  }
}

extension TupleView {
  package func appendDeclaredChildrenWork(
    in context: ResolveContext, kindName: String, into state: DeclaredChildrenWorkState
  ) -> ResolveWork<Void> {
    var work: [ResolveWork<Void>] = []
    for child in repeat each value {
      work.append(appendDeclaredChildWork(child, in: context, kindName: kindName, into: state))
    }
    return resolveSequentially(work) { $0 }
  }
}

extension VariadicView {
  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    .deferred {
      let state = DeclaredChildrenWorkState()
      return resolveSequentially(content) {
        appendDeclaredChildWork($0, in: context, kindName: "Group", into: state)
      }.map {
        assignEntityIdentityOccurrences(to: &state.nodes)
        return state.nodes
      }
    }
  }

  package func appendDeclaredChildrenWork(
    in context: ResolveContext, kindName: String, into state: DeclaredChildrenWorkState
  ) -> ResolveWork<Void> {
    .deferred {
      let childContext = context.indexedChild(
        kind: .init(rawValue: kindName), index: state.nextIndex)
      state.nextIndex += 1
      let children = DeclaredChildrenWorkState()
      return resolveSequentially(content) {
        appendDeclaredChildWork($0, in: childContext, kindName: kindName, into: children)
      }.map { state.nodes.append(contentsOf: children.nodes) }
    }
  }
}

extension ConditionalContent {
  package func appendDeclaredChildrenWork(
    in context: ResolveContext, kindName: String, into state: DeclaredChildrenWorkState
  ) -> ResolveWork<Void> {
    .deferred {
      let slotContext = context.indexedChild(
        kind: .init(rawValue: kindName), index: state.nextIndex)
      state.nextIndex += 1
      let branch = DeclaredChildrenWorkState()
      let work: ResolveWork<Void>
      switch storage {
      case .trueContent(let content):
        work = appendDeclaredChildWork(
          content, in: slotContext.child(component: .named("true")),
          kindName: kindName, into: branch)
      case .falseContent(let content):
        if collapsesImplicitEmptyFalseBranch, content is EmptyView { return .value(()) }
        work = appendDeclaredChildWork(
          content, in: slotContext.child(component: .named("false")),
          kindName: kindName, into: branch)
      }
      return work.map { state.nodes.append(contentsOf: branch.nodes) }
    }
  }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    switch storage {
    case .trueContent(let content):
      return resolveBranchWork(content, in: context, component: "true")
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView { return .value([]) }
      return resolveBranchWork(content, in: context, component: "false")
    }
  }

  private func resolveBranchWork<Content: View>(
    _ content: Content, in context: ResolveContext, component: String
  ) -> ResolveWork<[ResolvedNode]> {
    let branchContext = context.child(component: .init(rawValue: component))
    guard !(content is any ResolvableView), context.viewGraph != nil else {
      return resolveViewElementsWork(content, in: branchContext)
    }
    return resolveViewWork(content, in: branchContext).map {
      consumeDeclaredChild(
        $0, resolvedUnder: branchContext.identity,
        in: context.viewGraph, policy: .declaredBuilder)
    }
  }
}
