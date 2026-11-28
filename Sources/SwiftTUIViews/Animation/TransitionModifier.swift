import SwiftTUICore

extension View {
  /// Associates a transition with this view for insertion/removal
  /// animation.
  ///
  /// The transition's insertion phase plays when this view first appears
  /// in the resolved tree.  Its removal phase plays when the view is
  /// absent from a subsequent resolve.  During the removal animation
  /// the view is rendered as a non-semantic overlay; it does not
  /// participate in layout, focus, semantics, or interaction.
  public func transition(_ transition: AnyTransition) -> some View {
    modifier(TransitionRegistrationModifier(transition: transition))
  }
}

public struct TransitionRegistrationModifier: IterativePrimitiveViewModifier, Sendable {
  package var transition: AnyTransition

  package init(transition: AnyTransition) {
    self.transition = transition
  }

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    // A transition with a body channel resolves its body in the identity
    // phase, in this modifier's own context, the way a composed modifier's
    // body resolves; the content sits behind the boundary node the body's
    // `content` placement emits. A transition without one resolves the
    // content directly and adds no node.
    let elements: ResolveWork<[ResolvedNode]>
    if let bodyBox = transition.bodyBox {
      elements = bodyBox.resolveElementsWork(
        content: TransitionContentSource(content),
        phase: .identity,
        in: context
      )
    } else {
      elements = content.resolveElementsWork(in: context)
    }
    return elements.map { nodes in
      // Register the transition for every emitted identity so the
      // animation controller can look it up during insertion/removal
      // diffing.
      //
      // The registration deliberately keys on the enclosing evaluation host's
      // node id when the child resolves value-only: subtree re-stamping aliases
      // value children onto the host anyway, and only a nodeID that is live in
      // the committed tree survives the collection barrier's prune. The
      // registered *identity* is what the adopted-slot removal/insertion
      // channels key conditional-presence detection on.
      if let sink = TransitionRegistrationStorage.effectiveSink {
        // A transition with a body registers with what the animation engine
        // needs to evaluate another phase of that body after this resolve:
        // this context without its graph, and the boundaries that enclose
        // the content in the trees just emitted.
        let registered = transition.registeringBody(in: context, emitting: nodes)
        // The node whose evaluation declares the transition. An emitted
        // node can have a graph node of its own (each view of a body with
        // several roots does, and so does a view with state of its own
        // under a transition over several views), and an evaluation of that
        // node alone does not run this modifier. The sink keeps such a
        // registration while this node stays in the graph without declaring
        // it again, and the emitted node still emits the view it was made
        // for. Only a node of this resolve's own graph is named: the sink
        // asks that graph whether the node is still there.
        let hostNodeID = ViewNodeContext.current?.viewNodeID
        let declaringNodeID =
          ViewNodeContext.current.flatMap { current in
            current.ownerGraph === context.viewGraph ? current.viewNodeID : nil
          }
        for node in nodes {
          sink.registerTransition(
            for: node.identity,
            viewNodeID: node.viewNodeID ?? hostNodeID,
            declaringNodeID: declaringNodeID,
            transition: registered
          )
        }
      }
      return nodes
    }
  }
}
