/// The stroke configuration for outlines and rules.
///
/// `StrokeStyle` pairs:
/// - a ``BorderSet`` (the glyph palette. See ``BorderSet`` for details.)
/// - a ``LineJoin`` (square corners, or rounded ones where the palette has
///   them)
/// - a ``dash`` pattern and a ``dashPhase``, measured along the outline in
///   cell widths. Changing the phase moves the pattern round the outline.
/// - a numeric `lineWidth` (currently always 1, reserved for future use)
/// - a ``Placement`` (`.outset` reserves a cell on each side for the
///   border. `.inset` draws the border into the outermost
///   cells of the content frame).
///
/// A border, a rectangle stroke and a `Divider` draw through one renderer, so
/// the same style draws the same cells on all three.
///
/// The default (``init(lineWidth:borderSet:placement:lineJoin:dash:dashPhase:)``
/// with no arguments) is a solid ``BorderSet/single`` line with square corners,
/// which is what SwiftUI's default stroke looks like. For rounded corners use
/// ``rounded``, or stroke a `RoundedRectangle`. The built-in controls ask for
/// rounded corners themselves, so they do not depend on this default.
///
/// The default placement is `.inset`, so a stroke does not change layout
/// allocation. Request `.outset` on a view's `border` when the border must
/// reserve cells around content.
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
  /// A `Rectangle` and a view's `border` start at the top-leading corner. A
  /// `RoundedRectangle` starts at the middle of its trailing edge. Both run
  /// clockwise, as in SwiftUI.
  public var dashPhase: Double

  /// The part of the outline the stroke keeps. `Shape.trim(from:to:)` sets it.
  ///
  /// SwiftUI trims the shape, not the stroke style, and so does the public API
  /// here. The interval travels on the style because a trim is the same kind of
  /// thing as a dash: a test on position along the outline.
  package var trim: StrokeTrim?

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
    borderSet: BorderSet = .single,
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
  /// This style, keeping only part of the outline. `nil` keeps all of it.
  package func trimmed(to trim: StrokeTrim?) -> StrokeStyle {
    var copy = self
    copy.trim = trim
    return copy
  }

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
  /// A single line with rounded corners (`╭╮╰╯`).
  public static let rounded = StrokeStyle(borderSet: .rounded)
  public static let heavy = StrokeStyle(borderSet: .heavy)
  public static let single = StrokeStyle(borderSet: .single)
  public static let double = StrokeStyle(borderSet: .double)
  public static let singleDouble = StrokeStyle(borderSet: .singleDouble)
  public static let doubleSingle = StrokeStyle(borderSet: .doubleSingle)
  public static let ascii = StrokeStyle(borderSet: .ascii)
  public static let block = StrokeStyle(borderSet: .block)
  public static let innerHalfBlock = StrokeStyle(borderSet: .innerHalfBlock)
  public static let outerHalfBlock = StrokeStyle(borderSet: .outerHalfBlock)
  public static let hidden = StrokeStyle(borderSet: .hidden)
  /// Reserves no cells and draws nothing. The "no border" value, **not** to be
  /// confused with `Optional<StrokeStyle>.none`.
  public static let none = StrokeStyle(borderSet: .none)
  public static let markdown = StrokeStyle(borderSet: .markdown)
  /// A single line, one cell width on and one off.
  public static let dashed = StrokeStyle(borderSet: .single, dash: [1, 1])
  /// A heavy line, one cell width on and one off.
  public static let dashedHeavy = StrokeStyle(borderSet: .heavy, dash: [1, 1])
}

/// The part of a stroke's outline that is drawn, as fractions of its length.
package struct StrokeTrim: Equatable, Sendable {
  package var from: Double
  package var to: Double

  /// Both fractions are clamped to `0...1`. A value that is not finite reads as
  /// the nearer end, so the interval is always ordered or empty.
  package init(from: Double, to: Double) {
    func clamped(_ value: Double, fallback: Double) -> Double {
      value.isFinite ? min(1, max(0, value)) : fallback
    }
    self.from = clamped(from, fallback: 0)
    self.to = clamped(to, fallback: 1)
  }

  package var isEmpty: Bool {
    !(from < to)
  }
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
