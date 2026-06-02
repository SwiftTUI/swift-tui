package enum RetainedPhaseExtractionProof: Sendable {
  case none
  case wholeTreeIdentical
}

package struct RetainedSemanticExtractionInput: Sendable {
  package var previousPlaced: PlacedNode
  package var previousSnapshot: SemanticSnapshot
  package var proof: RetainedPhaseExtractionProof

  package init(
    previousPlaced: PlacedNode,
    previousSnapshot: SemanticSnapshot,
    proof: RetainedPhaseExtractionProof
  ) {
    self.previousPlaced = previousPlaced
    self.previousSnapshot = previousSnapshot
    self.proof = proof
  }
}

package struct RetainedDrawExtractionInput: Sendable {
  package var previousPlaced: PlacedNode
  package var previousDraw: DrawNode
  package var proof: RetainedPhaseExtractionProof

  package init(
    previousPlaced: PlacedNode,
    previousDraw: DrawNode,
    proof: RetainedPhaseExtractionProof
  ) {
    self.previousPlaced = previousPlaced
    self.previousDraw = previousDraw
    self.proof = proof
  }
}
