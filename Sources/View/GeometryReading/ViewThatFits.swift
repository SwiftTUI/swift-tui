public import Core

/// Chooses the first child whose layout fits the proposed space.
public struct ViewThatFits<Content: View>: View, ResolvableView {
  public var axes: Axis.Set
  package var content: Content

  public init(
    in axes: Axis.Set = [.horizontal, .vertical],
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.content = content()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "ViewThatFits"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ViewThatFits"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .viewThatFits(axes)
      )
    ]
  }
}
