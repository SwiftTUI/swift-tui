public import Core

@MainActor
package protocol ViewNode {
  func resolve(in context: ResolveContext) -> ResolvedNode
}

/// A declarative unit of terminal UI content.
///
/// Implement `body` the same way you would in SwiftUI: compose smaller views,
/// modifiers, and property wrappers rather than constructing render nodes
/// directly.
@MainActor
public protocol View {
  associatedtype Body: View = Never

  @ViewBuilder @MainActor
  var body: Body { get }
}

extension Never: View {
  /// Primitive views use `Never` as their body type.
  public typealias Body = Never

  public var body: Never {
    fatalError("Never.body is unreachable.")
  }
}

@MainActor
package protocol ResolvableView {
  func resolveElements(in context: ResolveContext) -> [ResolvedNode]
}

@MainActor
package protocol DeclaredChildrenView {
  func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  )

  func appendErasedDeclaredChildren(
    into children: inout [AnyView]
  )

  func appendDeferredDeclaredChildren(
    into children: inout [DeferredViewPayload]
  )
}

/// Resolves authored views into resolved render trees.
///
/// This is the lowest public entry point for inspecting the authored view tree
/// before layout, semantics, draw extraction, and rasterization occur.
public struct Resolver {
  public init() {}

  /// Resolves `root` in the supplied context.
  @MainActor
  public func resolve<V: View>(
    _ root: V,
    in context: ResolveContext = .init()
  ) -> ResolvedNode {
    resolveView(root, in: context)
  }
}

@MainActor
package func scopedAnyView<V: View>(
  authoringContext: AuthoringContext? = currentAuthoringContext(),
  _ build: () -> V
) -> AnyView {
  // AnyView policy: use this helper instead of plain AnyView(...) when stored
  // authored content must preserve its original authored context.
  withAuthoringContext(authoringContext) {
    AnyView(
      scoped: build(),
      authoringContext: authoringContext
    )
  }
}

@MainActor
package func appendDeclaredChildNodes<V: View>(
  _ view: V,
  in context: ResolveContext,
  kindName: String,
  nextIndex: inout Int,
  into resolved: inout [ResolvedNode]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendDeclaredChildren(
      in: context,
      kindName: kindName,
      nextIndex: &nextIndex,
      into: &resolved
    )
    return
  }

  let childContext = context.indexedChild(
    kind: .init(rawValue: kindName),
    index: nextIndex
  )
  nextIndex += 1

  if context.viewGraph != nil {
    let resolvedNode = resolveView(view, in: childContext)
    context.viewGraph?.recordRegistrationAlias(
      from: childContext.identity,
      to: resolvedNode.identity
    )
    if resolvedNode.identity == childContext.identity,
      resolvedNode.kind == .view("EmptyView")
    {
      return
    }
    if resolvedNode.identity == childContext.identity,
      resolvedNode.kind == .view("Group")
    {
      resolved.append(contentsOf: resolvedNode.children)
      return
    }
    resolved.append(resolvedNode)
    return
  }

  let elements = resolveViewElements(view, in: childContext)
  childContext.recordResolvedComputation(count: elements.count)
  resolved.append(contentsOf: elements)
}

@MainActor
package func resolveDeclaredChildren<V: View>(
  _ view: V,
  in context: ResolveContext,
  kindName: String
) -> [ResolvedNode] {
  var resolved: [ResolvedNode] = []
  var nextIndex = 0
  appendDeclaredChildNodes(
    view,
    in: context,
    kindName: kindName,
    nextIndex: &nextIndex,
    into: &resolved
  )
  return resolved
}

@MainActor
package func appendErasedDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [AnyView]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendErasedDeclaredChildren(
      into: &children
    )
    return
  }
  children.append(scopedAnyView { view })
}

@MainActor
package func erasedDeclaredBuilderChildren<V: View>(
  from view: V
) -> [AnyView] {
  var children: [AnyView] = []
  appendErasedDeclaredBuilderChildren(
    from: view,
    into: &children
  )
  return children
}

@MainActor
package func appendDeferredDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [DeferredViewPayload]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendDeferredDeclaredChildren(
      into: &children
    )
    return
  }
  children.append(
    DeferredViewPayload {
      view
    }
  )
}

@MainActor
package func deferredDeclaredBuilderChildren<V: View>(
  from view: V
) -> [DeferredViewPayload] {
  var children: [DeferredViewPayload] = []
  appendDeferredDeclaredBuilderChildren(
    from: view,
    into: &children
  )
  return children
}

@MainActor
package func resolveViewElements<V: View>(
  _ view: V,
  in context: ResolveContext
) -> [ResolvedNode] {
  let erased: Any = view
  if let resolvable = erased as? any ResolvableView {
    return resolvable.resolveElements(in: context)
  }
  return view.resolveBody(in: context) {
    view.body
  }
}

@MainActor
package func resolveViewElements<V: View & ResolvableView>(
  _ view: V,
  in context: ResolveContext
) -> [ResolvedNode] {
  view.resolveElements(in: context)
}

@MainActor
package func normalizeResolvedElements(
  _ resolvedElements: [ResolvedNode],
  in context: ResolveContext
) -> ResolvedNode {
  switch resolvedElements.count {
  case 0:
    return ResolvedNode(
      identity: context.identity,
      kind: .view("EmptyView"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      intrinsicSize: .zero
    )
  case 1:
    return resolvedElements[0]
  default:
    return ResolvedNode(
      identity: context.identity,
      kind: .view("Group"),
      children: resolvedElements,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
  }
}

@MainActor
package func resolveView<V: View>(
  _ view: V,
  in context: ResolveContext
) -> ResolvedNode {
  // When a shared FrameResolveState is available, refresh the per-frame
  // invalidation set so evaluator closures captured on prior frames see
  // the current frame's dirty identities.
  var context = context
  if let fs = context.frameState {
    context.invalidatedIdentities = fs.invalidatedIdentities
  }
  if let reused = context.viewGraph?.reusableSnapshot(
    for: context.identity,
    invalidatedIdentities: context.effectiveInvalidatedIdentities,
    invalidationSummary: context.effectiveInvalidationSummary,
    environment: context.environment,
    transaction: context.transaction,
    invalidator: context.invalidationProxy?.invalidator
  ) {
    context.viewGraph?.restoreRuntimeRegistrations(
      for: reused,
      into: context.runtimeRegistrations
    )
    context.recordResolvedReuse(
      count: reused.subtreeNodeCount
    )
    return reused
  }

  let graphNode = context.viewGraph?.beginEvaluation(
    identity: context.identity,
    invalidator: context.invalidationProxy?.invalidator
  )
  if let graphNode, graphNode.isAtOutermostEvaluationDepth {
    context.viewGraph?.setEvaluator(for: context.identity) {
      _ = resolveView(view, in: context)
    }
  }
  context.recordResolvedComputation()
  let erased: Any = view
  var accessedStateSlots = 0
  let resolved = ViewUpdateGuard.withViewUpdate {
    ViewNodeContext.withValue(graphNode) {
      if erased is any ResolvableView {
        return normalizeResolvedElements(
          resolveViewElements(view, in: context),
          in: context
        )
      }

      let authoringContext = makeAuthoringContext(
        for: context,
        viewNode: graphNode
      )
      return withAuthoringContext(authoringContext) {
        let resolved = normalizeResolvedElements(
          resolveViewElements(view, in: context),
          in: context
        )
        accessedStateSlots = authoringContext.ordinalTracker.nextOrdinal
        return resolved
      }
    }
  }
  if let graphNode {
    context.viewGraph?.finishEvaluation(
      graphNode,
      resolved: resolved,
      accessedStateSlots: accessedStateSlots
    )
  }
  return resolved
}
