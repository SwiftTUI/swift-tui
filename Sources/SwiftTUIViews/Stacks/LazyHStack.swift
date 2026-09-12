public import SwiftTUICore

/// Arranges children horizontally using lazy stack layout rules.
public struct LazyHStack<Content: View>: PrimitiveView, IterativeResolvableView {
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

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let stackContext = context.settingEnvironment(\.stackAxis, to: .horizontal)
    return makeCompositionalIndexedChildSourceWork(
      from: content, in: stackContext, kindName: "LazyHStack"
    ).map { source in
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
  }
}
