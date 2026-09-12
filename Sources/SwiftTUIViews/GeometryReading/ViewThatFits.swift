public import SwiftTUICore

/// Chooses the first child whose layout fits the proposed space.
public struct ViewThatFits<Content: View>: PrimitiveView, IterativeResolvableView {
  public var axes: Axis.Set
  package var content: Content

  public init(
    in axes: Axis.Set = [.horizontal, .vertical],
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.content = content()
  }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    // Every candidate resolves; layout places one. A style body that offers
    // the same route in two candidates installs it once per placed slot, so
    // each candidate claims on its own alternative of the route ledger.
    return withStyleRouteAlternativesWork {
      resolveDeclaredChildrenWork(
        content,
        in: context,
        kindName: "ViewThatFits"
      )
    }
    .map { resolvedChildren in
      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("ViewThatFits"),
          children: resolvedChildren,
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction,
          layoutBehavior: .viewThatFits(axes)
        )
      ]
    }
  }
}
