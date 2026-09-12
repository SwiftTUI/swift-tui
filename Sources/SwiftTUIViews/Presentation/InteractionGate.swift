import SwiftTUICore

extension View {
  package func interactionGate(
    _ availability: InteractionAvailability
  ) -> some View {
    modifier(InteractionGateModifier(availability: availability))
  }
}

package struct InteractionGateModifier: IterativePrimitiveViewModifier, Sendable {
  package var availability: InteractionAvailability

  package func makeResolveWork<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      var node = completed
      node.semanticMetadata = node.semanticMetadata.merging(
        SemanticMetadata(interactionAvailability: availability)
      )
      return [node]

    }
  }
}
