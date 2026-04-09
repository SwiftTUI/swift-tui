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
    TransitionViewModifier(content: self, transition: transition)
  }
}

package struct TransitionViewModifier<Content: View>: View, ResolvableView {
  package var content: Content
  package var transition: AnyTransition

  package init(content: Content, transition: AnyTransition) {
    self.content = content
    self.transition = transition
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let nodes = content.resolveElements(in: context)
    // Register the transition for every emitted identity so the
    // animation controller can look it up during insertion/removal
    // diffing.
    if let sink = TransitionRegistrationStorage.currentSink {
      for node in nodes {
        sink.registerTransition(for: node.identity, transition: transition)
      }
    }
    return nodes
  }
}
