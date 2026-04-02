public import Core

/// Arranges children vertically using lazy stack layout rules.
public struct LazyVStack<Content: View>: View, ResolvableView {
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
    let stackContext = context.settingEnvironment(\.stackAxis, to: .vertical)
    let childContext = stackContext.indexedChild(
      kind: .init(rawValue: "LazyVStack"),
      index: 0
    )
    if let source = makeIndexedChildSource(
      from: content,
      in: childContext
    ) {
      context.recordResolvedComputation()
      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("LazyVStack"),
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction,
          layoutBehavior: .lazyStack(
            axis: .vertical,
            spacing: spacing,
            horizontalAlignment: alignment,
            verticalAlignment: .center
          ),
          indexedChildSource: source
        )
      ]
    }

    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: stackContext,
      kindName: "LazyVStack"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("LazyVStack"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .lazyStack(
          axis: .vertical,
          spacing: spacing,
          horizontalAlignment: alignment,
          verticalAlignment: .center
        )
      )
    ]
  }
}
