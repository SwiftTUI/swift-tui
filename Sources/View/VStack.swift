public import Core

/// Arranges children vertically using stack layout rules.
public struct VStack<Content: View>: View, ResolvableView {
  public var alignment: HorizontalAlignment
  public var spacing: Int?
  package var content: Content

  public init(
    alignment: HorizontalAlignment = .center,
    spacing: Int? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.spacing = spacing
    self.content = content()
  }

  package init(
    alignment: HorizontalAlignment = .center,
    spacing: Int? = nil,
    children: [AnyView]
  ) where Content == VariadicView<AnyView> {
    self.alignment = alignment
    self.spacing = spacing
    content = VariadicView(children)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "VStack"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("VStack"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .stack(
          axis: .vertical,
          spacing: spacing,
          horizontalAlignment: alignment,
          verticalAlignment: .center
        )
      )
    ]
  }
}

