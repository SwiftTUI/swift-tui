package import Core

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
}


/// Resolves authored views into resolved render trees.
///
/// This is the lowest public entry point for inspecting the authored view tree
/// before layout, semantics, draw extraction, and rasterization occur.
public struct Resolver {
  public init() {}

  /// Resolves `root` in the supplied context.
  @MainActor
  package func resolve<V: View>(
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
package func appendDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [AnyView]
) {
  let erased: Any = view
  if let composite = erased as? any BuilderCompositeView {
    children.append(contentsOf: composite.builderChildren)
    return
  }
  children.append(scopedAnyView { view })
}

@MainActor
package func declaredBuilderChildren<V: View>(
  from view: V
) -> [AnyView] {
  var children: [AnyView] = []
  appendDeclaredBuilderChildren(
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
  let graphNode = context.viewGraph?.beginEvaluation(
    identity: context.identity,
    invalidator: context.invalidationProxy?.invalidator
  )
  context.recordResolvedComputation()
  let erased: Any = view
  var accessedStateSlots = 0
  let resolved = ViewNodeContext.withValue(graphNode) {
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
  if let graphNode {
    context.viewGraph?.finishEvaluation(
      graphNode,
      resolved: resolved,
      accessedStateSlots: accessedStateSlots
    )
  }
  return resolved
}
