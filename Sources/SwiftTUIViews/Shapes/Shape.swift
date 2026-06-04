@_spi(Testing) public import SwiftTUICore

/// A view that renders a geometric shape using fill or stroke operations.
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
