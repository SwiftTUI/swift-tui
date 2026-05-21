/// Grouped metadata for draw-relevant properties of a resolved node.
package struct NodeDrawInfo: Equatable, Sendable {
  package var drawMetadata: DrawMetadata
  package var drawEffects: DrawEffects
  package var drawPayload: DrawPayload

  package init(
    drawMetadata: DrawMetadata = DrawMetadata(),
    drawEffects: DrawEffects = .init(),
    drawPayload: DrawPayload = .none
  ) {
    self.drawMetadata = drawMetadata
    self.drawEffects = drawEffects
    self.drawPayload = drawPayload
  }
}

extension ResolvedNode {
  /// Grouped draw metadata for this node.
  package var drawInfo: NodeDrawInfo {
    get {
      NodeDrawInfo(
        drawMetadata: drawMetadata,
        drawEffects: drawEffects,
        drawPayload: drawPayload
      )
    }
    set {
      drawMetadata = newValue.drawMetadata
      drawEffects = newValue.drawEffects
      drawPayload = newValue.drawPayload
    }
  }
}
