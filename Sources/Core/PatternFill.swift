/// A fill style that paints a specific glyph at every cell in the
/// shape's fill region, colored with a foreground and an optional
/// background.
///
/// Use ``PatternFill`` when a shape should be filled with a repeating
/// glyph pattern (for example, a shading block `░`/`▒`/`▓` for
/// layered "density" regions, or a dot `·` for subtle texture)
/// instead of a flat color.  Unlike ``LinearGradient`` and
/// ``RadialGradient``, a pattern fill writes a non-space character
/// into each cell the shape covers; the rasterizer handles the per-
/// cell walk and shape masking.
///
/// ## Supported shapes
///
/// Pattern fills render their glyph on ``Rectangle`` and
/// ``RoundedRectangle``.  On curved shapes (``Circle``, ``Ellipse``,
/// ``Capsule``) the rasterizer currently falls back to rendering a
/// solid-colored Braille disc using ``PatternFill/foreground`` — the
/// glyph is not written.  This is a known limitation of the Braille
/// subpixel renderer; a future milestone may extend curved-shape
/// filling to honor pattern glyphs at cell resolution.
public struct PatternFill: ShapeStyle, Equatable, Sendable {
  /// The glyph painted at every cell inside the shape.
  public var glyph: Character
  /// The foreground color used for ``glyph``.
  public var foreground: Color
  /// Optional cell background color painted behind ``glyph``.
  public var background: Color?

  public init(
    glyph: Character,
    foreground: Color,
    background: Color? = nil
  ) {
    self.glyph = glyph
    self.foreground = foreground
    self.background = background
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .patternFill(self)
  }
}

extension PatternFill {
  /// Light shade block `░` (U+2591) — roughly 25% density.
  public static let lightShade = PatternFill(glyph: "░", foreground: .white)

  /// Medium shade block `▒` (U+2592) — roughly 50% density.
  public static let mediumShade = PatternFill(glyph: "▒", foreground: .white)

  /// Heavy shade block `▓` (U+2593) — roughly 75% density.
  public static let heavyShade = PatternFill(glyph: "▓", foreground: .white)

  /// Middle-dot dot pattern `·` (U+00B7).
  public static let dots = PatternFill(glyph: "·", foreground: .white)
}
