/// Grouped metadata for draw-relevant properties of a resolved node.
package struct NodeDrawInfo: Equatable, Sendable {
  package var drawMetadata: DrawMetadata
  package var drawPayload: DrawPayload

  package init(
    drawMetadata: DrawMetadata = DrawMetadata(),
    drawPayload: DrawPayload = .none
  ) {
    self.drawMetadata = drawMetadata
    self.drawPayload = drawPayload
  }
}

extension ResolvedNode {
  /// Grouped draw metadata for this node.
  package var drawInfo: NodeDrawInfo {
    get {
      NodeDrawInfo(
        drawMetadata: drawMetadata,
        drawPayload: drawPayload
      )
    }
    set {
      drawMetadata = newValue.drawMetadata
      drawPayload = newValue.drawPayload
    }
  }
}
