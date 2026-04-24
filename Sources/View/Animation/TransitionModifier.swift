package import Core

extension View {
  /// Associates a transition with this view for insertion/removal
  /// animation.
  ///
  /// The transition's insertion phase plays when this view first appears
  /// in the resolved tree.  Its removal phase plays when the view is
  /// absent from a subsequent resolve.  During the removal animation
  /// the view is rendered as a non-semantic overlay — it does not
  /// participate in layout, focus, semantics, or interaction.
  public func transition(_ transition: AnyTransition) -> some View {
    modifier(TransitionRegistrationModifier(transition: transition))
  }
}

public struct TransitionRegistrationModifier: PrimitiveViewModifier, Sendable {
  package var transition: AnyTransition

  package init(transition: AnyTransition) {
    self.transition = transition
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let nodes = content.resolveElements(in: context)
    // Register the transition for every emitted identity so the
    // animation controller can look it up during insertion/removal
    // diffing.
    if let sink = TransitionRegistrationStorage.effectiveSink {
      for node in nodes {
        sink.registerTransition(for: node.identity, transition: transition)
      }
    }
    return nodes
  }
}
