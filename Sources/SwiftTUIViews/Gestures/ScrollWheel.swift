import SwiftTUICore

/// A wheel or trackpad scroll delta delivered to ``View/onScrollWheel(perform:)``.
public struct ScrollWheelEvent: Equatable, Sendable {
  /// Horizontal scroll delta in terminal cells. Positive values move right.
  public var deltaX: Int

  /// Vertical scroll delta in terminal cells. Positive values move down.
  public var deltaY: Int

  public init(deltaX: Int, deltaY: Int) {
    self.deltaX = deltaX
    self.deltaY = deltaY
  }
}

/// The result of handling a scroll-wheel event.
public enum ScrollWheelResult: Equatable, Sendable {
  /// Leave the event available to an enclosing wheel handler or scroll view.
  case ignored

  /// Consume the event at this view.
  case handled
}

extension View {
  /// Handles wheel and trackpad scrolling over this view.
  ///
  /// Return ``ScrollWheelResult/ignored`` when the view cannot move farther so
  /// an enclosing handler or scroll view can consume the event.
  @MainActor
  public func onScrollWheel(
    perform action: @escaping @MainActor @Sendable (ScrollWheelEvent) -> ScrollWheelResult
  ) -> some View {
    modifier(
      ScrollWheelModifier(
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }
}

@MainActor
public struct ScrollWheelModifier: PrimitiveViewModifier, Sendable {
  let authoringContext: ImperativeAuthoringContextSnapshot?
  let action: @MainActor @Sendable (ScrollWheelEvent) -> ScrollWheelResult

  package init(
    authoringContext: ImperativeAuthoringContextSnapshot? = nil,
    action: @escaping @MainActor @Sendable (ScrollWheelEvent) -> ScrollWheelResult
  ) {
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard context.environmentValues.isEnabled else { return [node] }

    let routeIdentity = gestureRouteIdentity(for: node)
    let routeID = runtimePrimaryRouteID(for: routeIdentity)
    let intake = HandlerDescriptorIntake(
      context: context,
      fallbackSnapshot: authoringContext
    )
    intake.registerPointerHandler(routeID: routeID, structuralKey: node.identity) { event in
      guard case .scrolled(let deltaX, let deltaY) = event.kind else {
        return .ignored
      }
      return action(ScrollWheelEvent(deltaX: deltaX, deltaY: deltaY)) == .handled
        ? .claimed
        : .ignored
    }

    var metadata = SemanticMetadata(
      participatesInPointerHitTesting: true,
      allowsHitTesting: true
    )
    if routeIdentity != node.identity {
      metadata.explicitRouteIdentity = routeIdentity
    }
    node.semanticMetadata = node.semanticMetadata.merging(metadata)
    return [node]
  }
}
