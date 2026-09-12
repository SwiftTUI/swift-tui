public import SwiftTUICore

/// Arranges children vertically using lazy stack layout rules.
public struct LazyVStack<Content: View>: PrimitiveView, IterativeResolvableView {
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

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let stackContext = context.settingEnvironment(\.stackAxis, to: .vertical)
    return makeCompositionalIndexedChildSourceWork(
      from: content, in: stackContext, kindName: "LazyVStack"
    ).map { source in
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
  }
}
