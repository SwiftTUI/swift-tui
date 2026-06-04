@_spi(Testing) public import SwiftTUICore

/// A view that renders a geometric shape using fill or stroke operations.
///
/// Like SwiftUI's `Shape` (whose sole requirement is `path(in:)`), the only
/// author-facing requirement is ``geometry``: a conforming type describes its
/// shape and inherits fill/stroke/inset behavior. The rendering plumbing
/// (``kindName`` and ``insetAmount``) is exposed only under the
/// `ShapeRendering` SPI so it can dispatch dynamically through ``InsetShape``
/// without leaking into the public, author-facing surface.
public protocol Shape: View {
  var geometry: ShapeGeometry { get }
  @_spi(ShapeRendering) var kindName: String { get }
  @_spi(ShapeRendering) var insetAmount: Int { get }
}

/// A shape that can be inset geometrically before being rendered.
public protocol InsettableShape: Shape {}

extension Shape {
  public var body: Never {
    fatalError("\(Self.self) is a shape and does not expose a composed body.")
  }

  @_spi(ShapeRendering) public var kindName: String {
    String(describing: Self.self)
  }

  @_spi(ShapeRendering) public var insetAmount: Int {
    0
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: kindName,
        drawPayload: .shape(
          .init(
            geometry: geometry,
            insetAmount: insetAmount,
            operation: .fill(style: nil, mode: .full)
          )
        ),
        in: context
      )
    ]
  }
}
