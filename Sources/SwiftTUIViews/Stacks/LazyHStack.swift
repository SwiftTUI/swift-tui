public import SwiftTUICore

/// Arranges children horizontally using lazy stack layout rules.
public struct LazyHStack<Content: View>: View, ResolvableView {
  public var alignment: VerticalAlignment
  public var spacing: Int?
  package var content: Content

  public init(
    alignment: VerticalAlignment = .center,
    spacing: Int? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.spacing = spacing
    self.content = content()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let stackContext = context.settingEnvironment(\.stackAxis, to: .horizontal)
    let childContext = stackContext.indexedChild(
      kind: .init(rawValue: "LazyHStack"),
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
          kind: .view("LazyHStack"),
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction,
          layoutBehavior: .lazyStack(
            axis: .horizontal,
            spacing: spacing,
            horizontalAlignment: .center,
            verticalAlignment: alignment
          ),
          indexedChildSource: source
        )
      ]
    }

    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: stackContext,
      kindName: "LazyHStack"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("LazyHStack"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .lazyStack(
          axis: .horizontal,
          spacing: spacing,
          horizontalAlignment: .center,
          verticalAlignment: alignment
        )
      )
    ]
  }
}
