import SwiftTUICore

// A wrapper view that marks its subtree as participating in pointer hit
// testing under a caller-supplied identity.
//
// Renamed from `SelectionAndValueSupport.swift`, whose other contents were
// decomposed into `ControlValueMath.swift`, `BoundSelectionSupport.swift`, and
// `ControlFocusRowSupport.swift`.

struct PointerRouteView<Content: View>: PrimitiveView, ResolvableView {
  var identity: Identity
  var content: Content

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let wrapperContext = context.replacingIdentity(with: identity)
    let child = content.resolve(
      in: wrapperContext.child(component: .named("content"))
    )
    return [
      ResolvedNode(
        identity: identity,
        kind: .view("PointerRoute"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        semanticMetadata: .init(participatesInPointerHitTesting: true)
      )
    ]
  }
}
