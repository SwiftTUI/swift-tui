public import SwiftTUICore

/// Arranges children vertically using stack layout rules.
public struct VStack<Content: View>: PrimitiveView, IterativeResolvableView {
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
    return resolveDeclaredChildrenWork(
      content,
      in: stackContext,
      kindName: "VStack"
    )
    .map { resolvedChildren in
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
}
