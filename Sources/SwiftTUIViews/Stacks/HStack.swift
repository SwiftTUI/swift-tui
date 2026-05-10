public import SwiftTUICore

/// Arranges children horizontally using stack layout rules.
public struct HStack<Content: View>: PrimitiveView, ResolvableView {
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
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: stackContext,
      kindName: "HStack"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("HStack"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .stack(
          axis: .horizontal,
          spacing: spacing,
          horizontalAlignment: .center,
          verticalAlignment: alignment
        )
      )
    ]
  }
}
