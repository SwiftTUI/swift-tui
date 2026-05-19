/// Stroke settings used when drawing outlines and rules.
///
/// `StrokeStyle` pairs:
/// - a numeric `lineWidth` (currently always 1, reserved for future use)
/// - a ``BorderSet`` (the glyph palette; see ``BorderSet`` for details)
/// - a ``Placement`` (`.outset` reserves a cell on each side for the
///   border to live in; `.inset` draws the border into the outermost
///   cells of the content frame).
///
/// The default (``init(lineWidth:borderSet:placement:)`` with no
/// arguments) produces ``BorderSet/rounded`` glyphs in `.outset`
/// placement. Use this for the framework-canonical look.
///
/// For a single-line look matching pre-2026-04 framework defaults,
/// pass `borderSet: .single` explicitly. For the half-block look
/// matching the previous framework default, pass
/// `borderSet: .outerHalfBlock` - there is no
/// implicit upgrade; what you ask for is what you get drawn.
public struct StrokeStyle: Equatable, Sendable {
  public var lineWidth: Int
  public var borderSet: BorderSet
  public var placement: Placement

  public enum Placement: Equatable, Sendable {
    case outset
    case inset
  }

  public init(
    lineWidth: Int = 1,
    borderSet: BorderSet = .rounded,
    placement: Placement = .outset
  ) {
    self.lineWidth = max(1, lineWidth)
    self.borderSet = borderSet
    self.placement = placement
  }
}

extension StrokeStyle {
  public static let rounded = StrokeStyle(borderSet: .rounded)
  public static let heavy = StrokeStyle(borderSet: .heavy)
  public static let single = StrokeStyle(borderSet: .single)
  public static let double = StrokeStyle(borderSet: .double)
  public static let ascii = StrokeStyle(borderSet: .ascii)
  public static let block = StrokeStyle(borderSet: .block)
  public static let innerHalfBlock = StrokeStyle(borderSet: .innerHalfBlock)
  public static let hidden = StrokeStyle(borderSet: .hidden)
  public static let markdown = StrokeStyle(borderSet: .markdown)
}

/// Per-edge background styling used behind stroked borders.
public struct BorderBackgroundStyle: Equatable, Sendable {
  public var top: AnyShapeStyle?
  public var right: AnyShapeStyle?
  public var bottom: AnyShapeStyle?
  public var left: AnyShapeStyle?

  public init(
    top: AnyShapeStyle? = nil,
    right: AnyShapeStyle? = nil,
    bottom: AnyShapeStyle? = nil,
    left: AnyShapeStyle? = nil
  ) {
    self.top = top
    self.right = right
    self.bottom = bottom
    self.left = left
  }

  public init<S: ShapeStyle>(
    _ style: S
  ) {
    let resolved = AnyShapeStyle(style)
    top = resolved
    right = resolved
    bottom = resolved
    left = resolved
  }

  public init<TB: ShapeStyle, LR: ShapeStyle>(
    topBottom: TB,
    leftRight: LR
  ) {
    top = AnyShapeStyle(topBottom)
    right = AnyShapeStyle(leftRight)
    bottom = AnyShapeStyle(topBottom)
    left = AnyShapeStyle(leftRight)
  }

  public init<T: ShapeStyle, LR: ShapeStyle, B: ShapeStyle>(
    top: T,
    leftRight: LR,
    bottom: B
  ) {
    self.top = AnyShapeStyle(top)
    right = AnyShapeStyle(leftRight)
    self.bottom = AnyShapeStyle(bottom)
    left = AnyShapeStyle(leftRight)
  }

  public init<T: ShapeStyle, R: ShapeStyle, B: ShapeStyle, L: ShapeStyle>(
    top: T,
    right: R,
    bottom: B,
    left: L
  ) {
    self.top = AnyShapeStyle(top)
    self.right = AnyShapeStyle(right)
    self.bottom = AnyShapeStyle(bottom)
    self.left = AnyShapeStyle(left)
  }

  package init(
    all style: AnyShapeStyle?
  ) {
    self.init(
      top: style,
      right: style,
      bottom: style,
      left: style
    )
  }
}

package enum BorderSide: Sendable {
  case top
  case right
  case bottom
  case left
}

extension BorderBackgroundStyle {
  package func backgroundStyle(
    for side: BorderSide
  ) -> AnyShapeStyle? {
    switch side {
    case .top:
      return top
    case .right:
      return right
    case .bottom:
      return bottom
    case .left:
      return left
    }
  }
}
