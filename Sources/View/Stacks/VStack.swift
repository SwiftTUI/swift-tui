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

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let stackContext = context.settingEnvironment(\.stackAxis, to: .vertical)
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: stackContext,
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
