public import Core

/// Overlays children along the z axis using alignment rules.
public struct ZStack<Content: View>: View, ResolvableView {
  public var alignment: Alignment
  package var content: Content

  public init(
    alignment: Alignment = .center,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.content = content()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "ZStack"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ZStack"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .overlay(alignment: alignment)
      )
    ]
  }
}
