public import SwiftTUICore

/// Arranges children horizontally using lazy stack layout rules.
public struct LazyHStack<Content: View>: PrimitiveView, ResolvableView {
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
    let source = makeCompositionalIndexedChildSource(
      from: content, in: stackContext, kindName: "LazyHStack"
    )
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
