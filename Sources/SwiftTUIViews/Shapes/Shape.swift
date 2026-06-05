@_spi(Testing) public import SwiftTUICore

/// A view that renders a geometric shape using fill or stroke operations.
///
/// The shape a conformer describes is ``geometry`` — the one requirement most
/// shapes implement. ``kindName`` and ``insetAmount`` are rendering plumbing
/// with defaults, so a conforming type normally implements only ``geometry``.
/// They remain real (defaulted) requirements rather than SPI so that types
/// *outside* this module can conform: an `@_spi` requirement has no visible
/// default witness across a module boundary, which would force every external
/// shape to restate them. `insetAmount` must also dispatch dynamically through
/// ``InsetShape``, so it cannot be a non-requirement helper.
public protocol Shape: View {
  var geometry: ShapeGeometry { get }
  var kindName: String { get }
  var insetAmount: Int { get }
}

/// A shape that can be inset geometrically before being rendered.
public protocol InsettableShape: Shape {}

extension Shape {
  public var body: Never {
    fatalError("\(Self.self) is a shape and does not expose a composed body.")
  }

  public var kindName: String {
    String(describing: Self.self)
  }

  public var insetAmount: Int {
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
