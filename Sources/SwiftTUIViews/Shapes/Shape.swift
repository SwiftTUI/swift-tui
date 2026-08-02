@_spi(Testing) public import SwiftTUICore

/// A view that renders a geometric shape using fill or stroke operations.
///
/// Conform by implementing **either** ``path(in:)`` (SwiftUI-style — return the
/// outline for the proposed rect) **or** ``geometry`` (one of the analytic
/// primitive cases). Bidirectional defaults connect these functions.
/// A custom shape that implements only `path(in:)` gets a `.path` ``geometry`` value.
/// A primitive that implements only `geometry` gets a generated `path(in:)` value.
/// Implement at least one. If you implement neither, the defaults recurse.
///
/// ``kindName`` and ``insetAmount`` are rendering plumbing with defaults, so a
/// conforming type normally never touches them. They are plain (defaulted)
/// requirements rather than SPI. Thus, types *outside* this module can conform.
/// An `@_spi` requirement has no visible default witness across a module boundary.
/// `insetAmount` must also dispatch dynamically through
/// ``InsetShape``, so it cannot be a non-requirement helper.
///
/// The runtime evaluates `path(in:)` against the unit rectangle (`0,0,1,1`) during resolve.
/// During rasterization, it scales the normalized path into the placed frame.
/// Thus, a custom shape is relative to its frame and stretches to fill it.
/// The shape does not use the pixel-aspect correction that ``Circle`` uses.
public protocol Shape: View {
  var geometry: ShapeGeometry { get }
  func path(in rect: Rect) -> Path
  var kindName: String { get }
  var insetAmount: Int { get }
}

/// A shape that can be inset geometrically before being rendered.
public protocol InsettableShape: Shape {}

extension Shape {
  public var body: Never {
    fatalError("\(Self.self) is a shape and does not expose a composed body.")
  }

  /// The default ``geometry`` for a shape that defines ``path(in:)``.
  /// It evaluates the path against the unit rectangle one time.
  /// Then it carries the path as normalized `.path` geometry with a nonzero fill.
  /// Analytic primitives override this behavior.
  public var geometry: ShapeGeometry {
    .path(
      BoxedPath(path(in: Rect(origin: Point(x: 0, y: 0), size: Size(width: 1, height: 1)))),
      .nonZero)
  }

  /// Default ``path(in:)`` for a shape defined by ``geometry``: synthesize the
  /// outline from the analytic primitive (or return a carried `.path` scaled
  /// into `rect`). Custom shapes override this.
  public func path(in rect: Rect) -> Path {
    switch geometry {
    case .rectangle:
      return Path(rect)
    case .roundedRectangle(let cornerRadius):
      return Path(roundedRect: rect, cornerRadius: Double(cornerRadius))
    case .circle:
      let diameter = min(rect.size.width, rect.size.height)
      let inset = Rect(
        origin: Point(
          x: rect.origin.x + (rect.size.width - diameter) / 2,
          y: rect.origin.y + (rect.size.height - diameter) / 2),
        size: Size(width: diameter, height: diameter))
      return Path(ellipseIn: inset)
    case .ellipse:
      return Path(ellipseIn: rect)
    case .capsule:
      return Path(
        roundedRect: rect,
        cornerRadius: min(rect.size.width, rect.size.height) / 2)
    case .path(let boxed, _):
      return boxed.path
        .scaledBy(sx: rect.size.width, sy: rect.size.height)
        .translatedBy(dx: rect.origin.x, dy: rect.origin.y)
    }
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
