public import SwiftTUICore

extension View {
  /// Runs `action` as the pointer enters, moves within, and exits this view.
  public func onPointerHover(
    _ action: @escaping @MainActor @Sendable (HoverPhase) -> Void
  ) -> some View {
    modifier(
      PointerHoverModifier(
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }
}

@MainActor
public struct PointerHoverModifier: PrimitiveViewModifier, Sendable {
  let authoringContext: ImperativeAuthoringContextSnapshot?
  let action: @MainActor @Sendable (HoverPhase) -> Void

  package init(
    authoringContext: ImperativeAuthoringContextSnapshot? = nil,
    action: @escaping @MainActor @Sendable (HoverPhase) -> Void
  ) {
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    // Key the hover route on the nearest entity-rerooted descendant, like
    // `.gesture(_:)`: the chain node's structural identity embeds enclosing
    // conditional branches, so a branch flip at a stable `.id` would re-key
    // the route and fabricate a fresh enter instead of continuing the hover.
    let routeIdentity = gestureRouteIdentity(for: node)
    let routeID = runtimePrimaryRouteID(for: routeIdentity)
    // Restore the imperative authoring scope when dispatching, matching
    // `Button`/`onKeyPress`: without it a `@State` mutation inside the hover
    // handler is not attributed to an owner node, so it never schedules a frame
    // and the hover-driven state change is not rendered.
    let intake = HandlerDescriptorIntake(
      context: context,
      fallbackSnapshot: authoringContext
    )
    intake.registerPointerHoverHandler(
      routeID: routeID,
      structuralKey: node.identity,
      handler: action
    )
    var hoverMetadata = SemanticMetadata(
      participatesInPointerHitTesting: true,
      allowsHitTesting: true
    )
    if routeIdentity != node.identity {
      hoverMetadata.explicitRouteIdentity = routeIdentity
    }
    node.semanticMetadata = node.semanticMetadata.merging(hoverMetadata)
    return [node]
  }
}
