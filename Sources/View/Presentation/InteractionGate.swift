package import Core

extension View {
  package func interactionGate(
    _ availability: InteractionAvailability
  ) -> some View {
    modifier(InteractionGateModifier(availability: availability))
  }
}

package struct InteractionGateModifier: PrimitiveViewModifier, Sendable {
  package var availability: InteractionAvailability

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.semanticMetadata = node.semanticMetadata.merging(
      SemanticMetadata(interactionAvailability: availability)
    )
    return [node]
  }
}
