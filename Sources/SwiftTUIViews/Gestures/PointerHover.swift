public import SwiftTUICore

extension View {
  /// Runs `action` as the pointer enters, moves within, and exits this view.
  public func onPointerHover(
    _ action: @escaping @MainActor @Sendable (HoverPhase) -> Void
  ) -> some View {
    modifier(PointerHoverModifier(action: action))
  }
}

@MainActor
public struct PointerHoverModifier: PrimitiveViewModifier, Sendable {
  let action: @MainActor @Sendable (HoverPhase) -> Void

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let routeID = runtimePrimaryRouteID(for: node.identity)
    context.localPointerHandlerRegistry?.registerHover(
      routeID: routeID,
      handler: action
    )
    node.semanticMetadata = node.semanticMetadata.merging(
      SemanticMetadata(
        participatesInPointerHitTesting: true,
        allowsHitTesting: true
      )
    )
    return [node]
  }
}
