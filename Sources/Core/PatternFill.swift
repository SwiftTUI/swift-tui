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
/// Both ``foreground`` and ``background`` are typed as ``Paint``, so a
/// pattern fill's per-cell color may itself be a gradient — the
/// rasterizer resolves the gradient at each cell's position before
/// writing the glyph.
///
/// ## Supported shapes
///
/// Pattern fills write their glyph on every cell inside the shape's
/// fill region — whether rectangular, rounded, or curved.  On
/// ``Circle``, ``Ellipse``, and ``Capsule``, cell-level containment
/// is tested at each cell's visual center (projected into the same
/// Braille subpixel grid the curved-shape renderer uses), so the
/// glyph is written at exactly the cells the curved-shape rasterizer
/// would otherwise fill.  Because the test is per cell rather than per
/// subpixel, the resulting outline is blocky (no subpixel
/// antialiasing) — that trade-off is intrinsic to writing a
/// whole-cell glyph instead of Braille dots.
public struct PatternFill: ShapeStyle, Equatable, Sendable {
  /// Where a ``PatternFill`` sources its color: a flat color, or a
  /// gradient the rasterizer samples per cell inside the shape's
  /// fill region.
  public enum Paint: Equatable, Sendable {
    case color(Color)
    case linearGradient(LinearGradient)
    case radialGradient(RadialGradient)
  }

  /// The glyph painted at every cell inside the shape.
  public var glyph: Character
  /// The paint used for ``glyph``.
  public var foreground: Paint
  /// Optional cell background paint painted behind ``glyph``.
  public var background: Paint?

  /// Convenience initializer for the common flat-color case.  Kept so
  /// call sites that predate ``Paint`` compile unchanged.
  public init(
    glyph: Character,
    foreground: Color,
    background: Color? = nil
  ) {
    self.glyph = glyph
    self.foreground = .color(foreground)
    self.background = background.map(Paint.color)
  }

  /// Initializer for pattern fills whose foreground or background is a
  /// gradient (or any supported ``Paint``).
  public init(
    glyph: Character,
    foreground: Paint,
    background: Paint? = nil
  ) {
    self.glyph = glyph
    self.foreground = foreground
    self.background = background
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .patternFill(self)
  }
}

extension PatternFill.Paint {
  /// Fade every color component of the paint by `amount`.
  public func opacity(_ amount: Double) -> PatternFill.Paint {
    switch self {
    case .color(let color):
      return .color(color.opacity(amount))
    case .linearGradient(let gradient):
      let stops = gradient.gradient.stops.map {
        Gradient.Stop(color: $0.color.opacity(amount), location: $0.location)
      }
      return .linearGradient(
        LinearGradient(
          gradient: Gradient(stops: stops),
          startPoint: gradient.startPoint,
          endPoint: gradient.endPoint))
    case .radialGradient(let gradient):
      let stops = gradient.gradient.stops.map {
        Gradient.Stop(color: $0.color.opacity(amount), location: $0.location)
      }
      return .radialGradient(
        RadialGradient(
          gradient: Gradient(stops: stops),
          center: gradient.center,
          startRadius: gradient.startRadius,
          endRadius: gradient.endRadius))
    }
  }

  /// A representative scalar color — the first stop of a gradient, or
  /// the flat color.  Used by call sites that can't evaluate a gradient
  /// spatially (snapshot debug dumps, the one-color fallback in
  /// ``resolveStyleColorResult``).
  public var representativeColor: Color? {
    switch self {
    case .color(let color):
      return color
    case .linearGradient(let gradient):
      return gradient.gradient.stops.first?.color
    case .radialGradient(let gradient):
      return gradient.gradient.stops.first?.color
    }
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
