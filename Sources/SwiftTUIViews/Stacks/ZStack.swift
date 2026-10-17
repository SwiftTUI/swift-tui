public import SwiftTUICore

/// Overlays children along the z axis using alignment rules.
public struct ZStack<Content: View>: PrimitiveView, IterativeResolvableView {
  public var alignment: Alignment
  package var content: Content

  public init(
    alignment: Alignment = .center,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.content = content()
  }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    // A ZStack is not a stack along either axis, so its children resolve
    // with no stack axis — the same context `ZStackLayout {}` and a custom
    // layout without a declared orientation install. Direct spacers are
    // neutral beside content (or fill a spacer-only container); dividers
    // default to horizontal, independent of any enclosing stack.
    let overlayContext = context.settingEnvironment(\.stackAxis, to: nil)
    return resolveDeclaredChildrenWork(
      content,
      in: overlayContext,
      kindName: "ZStack"
    )
    .map { resolvedChildren in
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
}
