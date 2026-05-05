@_spi(Testing) public import SwiftTUICore

/// Displays a foreign cell grid inside the normal SwiftTUI draw pipeline.
///
/// The payload is sampled during rasterization. The view itself fills its
/// proposed size, matching `Canvas` and shape primitives.
public struct ForeignSurface<Payload: ForeignSurfacePayload>: View, ResolvableView {
  public let payload: Payload

  public init(payload: Payload) {
    self.payload = payload
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: "ForeignSurface",
        drawPayload: .foreignSurface(payload),
        in: context
      )
    ]
  }
}
