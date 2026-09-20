/// The stroke configuration for outlines and rules.
///
/// `StrokeStyle` pairs:
/// - a numeric `lineWidth` (currently always 1, reserved for future use)
/// - a ``BorderSet`` (the glyph palette. See ``BorderSet`` for details.)
/// - a ``Placement`` (`.outset` reserves a cell on each side for the
///   border. `.inset` draws the border into the outermost
///   cells of the content frame).
///
/// The default (``init(lineWidth:borderSet:placement:)`` with no
/// arguments) produces ``BorderSet/rounded`` glyphs in `.inset`
/// placement, so a stroke does not change layout allocation. Request
/// `.outset` explicitly when the border must reserve cells around content.
///
/// For a single-line look matching pre-2026-04 framework defaults,
/// pass `borderSet: .single` explicitly. For the half-block look
/// matching the previous framework default, pass
/// `borderSet: .outerHalfBlock`. No implicit upgrade occurs.
/// The renderer draws the specified border set.
public struct StrokeStyle: Equatable, Sendable {
  public var lineWidth: Int
  public var borderSet: BorderSet
  public var placement: Placement

  /// How the stroke turns a corner.
  ///
  /// ``LineJoin/round`` draws the arc glyphs (`╭╮╰╯`) where the glyph palette
  /// has them, which in Unicode is the light weight only. A shape whose
  /// geometry is rounded, such as `RoundedRectangle`, draws them with either
  /// join.
  public var lineJoin: LineJoin

  /// The lengths of the painted and unpainted segments of a dashed stroke.
  ///
  /// One unit is the width of a cell. A cell is about twice as tall as it is
  /// wide, so a vertical cell is about two units long and a dash is the same
  /// physical length on every edge. An empty array is a solid stroke. An odd
  /// count repeats to make an even one.
  ///
  /// A line glyph palette draws a dash end that falls inside a cell as a
  /// half-line (`╴╶╵╷`). The cells of an unpainted segment are left as they
  /// were, so content under a gap stays visible.
  public var dash: [Double]

  /// How far into the dash pattern the stroke starts, in the same units as
  /// ``dash``.
  ///
  /// A `Rectangle` and a `View/border(_:set:placement:sides:)` start at the
  /// top-leading corner. A `RoundedRectangle` starts at the middle of its
  /// trailing edge. Both run clockwise, as in SwiftUI.
  public var dashPhase: Double

  public enum Placement: Equatable, Sendable {
    case outset
    case inset
  }

  public enum LineJoin: Equatable, Sendable {
    /// Square corners (`┌┐└┘`).
    case miter
    /// Rounded corners (`╭╮╰╯`) where the glyph palette has them.
    case round
  }

  public init(
    lineWidth: Int = 1,
    borderSet: BorderSet = .rounded,
    placement: Placement = .inset,
    lineJoin: LineJoin = .miter,
    dash: [Double] = [],
    dashPhase: Double = 0
  ) {
    self.lineWidth = max(1, lineWidth)
    self.borderSet = borderSet
    self.placement = placement
    self.lineJoin = lineJoin
    self.dash = dash
    self.dashPhase = dashPhase
  }
}

extension StrokeStyle {
  /// The dash the stroke draws.
  ///
  /// `BorderSet.dashed` and `BorderSet.dashedHeavy` carry their rhythm as a
  /// second glyph in each edge string. A stroke draws one glyph per palette
  /// entry, so such a set dashes one unit on and one unit off instead, unless
  /// the stroke names its own pattern.
  package var effectiveDash: [Double] {
    dash.isEmpty && borderSet.impliesDash ? [1, 1] : dash
  }
}

extension BorderSet {
  package var impliesDash: Bool {
    top.count > 1 || bottom.count > 1 || left.count > 1 || right.count > 1
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
