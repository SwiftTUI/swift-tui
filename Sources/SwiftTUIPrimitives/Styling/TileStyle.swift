/// A fill style that paints a repeated terminal-cell tile inside a shape's
/// fill region.
///
/// Use ``TileStyle`` when a shape should be filled with glyph texture instead
/// of a flat color. Unlike ``LinearGradient`` and ``RadialGradient``, a tile
/// style writes a non-space character into each cell the shape covers; the
/// rasterizer handles the per-cell walk and shape masking.
///
/// ``Pattern`` validates tile rows at construction time. Patterns are
/// rectangular, non-empty, and restricted to single-cell glyphs, so painting
/// never has to clip wide graphemes or reinterpret raw strings during
/// rasterization.
public struct TileStyle: ShapeStyle, Equatable, Sendable {
  /// A validated terminal-cell tile pattern.
  public struct Pattern: Equatable, Sendable {
    /// The normalized tile rows.
    public let rows: [[Character]]
    /// The pattern size in terminal cells.
    public let size: CellSize

    /// Creates a tile pattern from row strings.
    ///
    /// Rows must be non-empty, rectangular, and composed only of glyphs whose
    /// terminal cell width is exactly one. Invalid patterns are programmer
    /// errors and trap immediately instead of falling back to blank output.
    public init(rows sourceRows: [String]) {
      precondition(!sourceRows.isEmpty, "TileStyle.Pattern requires at least one row")

      var normalizedRows: [[Character]] = []
      var expectedWidth: Int?
      for row in sourceRows {
        precondition(!row.isEmpty, "TileStyle.Pattern rows must not be empty")

        var normalizedRow: [Character] = []
        var rowWidth = 0
        for glyph in row {
          let glyphWidth = cellWidth(of: glyph)
          precondition(
            glyphWidth == 1,
            "TileStyle.Pattern only supports single-cell glyphs"
          )
          normalizedRow.append(glyph)
          rowWidth += glyphWidth
        }

        if let expectedWidth {
          precondition(
            rowWidth == expectedWidth,
            "TileStyle.Pattern rows must have matching terminal-cell widths"
          )
        } else {
          expectedWidth = rowWidth
        }

        normalizedRows.append(normalizedRow)
      }

      let width = expectedWidth ?? 0
      self.rows = normalizedRows
      self.size = CellSize(width: width, height: normalizedRows.count)
    }

    /// Creates a one-cell tile pattern.
    public init(glyph: Character) {
      precondition(
        cellWidth(of: glyph) == 1,
        "TileStyle.Pattern only supports single-cell glyphs"
      )
      self.rows = [[glyph]]
      self.size = CellSize(width: 1, height: 1)
    }

    /// The canonical checker-shade tile pattern.
    public static let checkerShade = Pattern(rows: ["░▒", "▒░"])

    /// Light shade block `░` (U+2591), roughly 25% density.
    public static let lightShade = Pattern(glyph: "░")

    /// Medium shade block `▒` (U+2592), roughly 50% density.
    public static let mediumShade = Pattern(glyph: "▒")

    /// Heavy shade block `▓` (U+2593), roughly 75% density.
    public static let heavyShade = Pattern(glyph: "▓")

    /// Middle-dot dot pattern `·` (U+00B7).
    public static let dots = Pattern(glyph: "·")

    package func character(atX x: Int, y: Int) -> Character {
      let row = rows[wrappedIndex(y, count: size.height)]
      return row[wrappedIndex(x, count: size.width)]
    }

    private func wrappedIndex(_ value: Int, count: Int) -> Int {
      let remainder = value % count
      return remainder >= 0 ? remainder : remainder + count
    }
  }

  /// A paint used by a tile foreground or background.
  public struct Paint: Equatable, Sendable {
    /// The underlying shape style used to resolve the paint color per cell.
    public let style: AnyShapeStyle

    public init(_ style: some ShapeStyle) {
      let erased = AnyShapeStyle(style)
      precondition(
        !erased.containsTileStyle,
        "TileStyle cannot be used as a TileStyle foreground or background"
      )
      self.style = erased
    }
  }

  /// The repeated tile pattern.
  public var pattern: Pattern
  /// The paint used for each tile glyph.
  public var foreground: Paint
  /// Optional cell background paint painted behind each tile glyph.
  public var background: Paint?

  public init(
    _ pattern: Pattern = .checkerShade,
    foreground: some ShapeStyle
  ) {
    self.pattern = pattern
    self.foreground = Paint(foreground)
    self.background = nil
  }

  public init(
    _ pattern: Pattern = .checkerShade,
    foreground: some ShapeStyle,
    background: some ShapeStyle
  ) {
    self.pattern = pattern
    self.foreground = Paint(foreground)
    self.background = Paint(background)
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .tileStyle(self)
  }
}

extension TileStyle.Paint {
  public func opacity(_ amount: Double) -> TileStyle.Paint {
    TileStyle.Paint(style.opacity(amount))
  }

  public var representativeColor: Color? {
    style.representativeTilePaintColor
  }

  public func isInterpolable(to other: TileStyle.Paint) -> Bool {
    style.isInterpolableTilePaint(to: other.style)
  }

  public func interpolated(
    to other: TileStyle.Paint,
    progress t: Double
  ) -> TileStyle.Paint {
    TileStyle.Paint(style.interpolatedTilePaint(to: other.style, progress: t))
  }
}

extension TileStyle {
  package func applyingOpacity(_ amount: Double) -> TileStyle {
    TileStyle(
      pattern: pattern,
      foreground: foreground.opacity(amount),
      background: background?.opacity(amount)
    )
  }

  public func isInterpolable(to other: TileStyle) -> Bool {
    guard pattern == other.pattern else { return false }
    guard foreground.isInterpolable(to: other.foreground) else { return false }
    switch (background, other.background) {
    case (nil, nil):
      return true
    case (let a?, let b?):
      return a.isInterpolable(to: b)
    default:
      return false
    }
  }

  public func interpolated(
    to other: TileStyle,
    progress t: Double
  ) -> TileStyle {
    guard isInterpolable(to: other) else { return other }
    let newForeground = foreground.interpolated(to: other.foreground, progress: t)
    let newBackground: Paint?
    switch (background, other.background) {
    case (nil, nil):
      newBackground = nil
    case (let a?, let b?):
      newBackground = a.interpolated(to: b, progress: t)
    default:
      newBackground = other.background
    }
    return TileStyle(
      pattern: pattern,
      foreground: newForeground,
      background: newBackground
    )
  }

  private init(
    pattern: Pattern,
    foreground: Paint,
    background: Paint?
  ) {
    self.pattern = pattern
    self.foreground = foreground
    self.background = background
  }
}

extension TileStyle: Animatable {
  public var animatableData: EmptyAnimatableData {
    get { EmptyAnimatableData() }
    set { /* intentionally unused */  }
  }
}

extension AnimatablePair
where
  First == Gradient.AnimatableData,
  Second == LinearGradient.EndpointsData
{
  public func isInterpolable(to other: Self) -> Bool {
    first.isInterpolable(to: other.first)
  }
}

extension AnyShapeStyle {
  fileprivate var containsTileStyle: Bool {
    switch self {
    case .tileStyle:
      return true
    case .opacity(let inner, _):
      return inner.containsTileStyle
    case .semantic, .color, .linearGradient, .radialGradient, .terminalChrome:
      return false
    }
  }

  fileprivate var representativeTilePaintColor: Color? {
    switch self {
    case .color(let color):
      return color
    case .linearGradient(let gradient):
      return gradient.gradient.stops.first?.color
    case .radialGradient(let gradient):
      return gradient.gradient.stops.first?.color
    case .opacity(let inner, let amount):
      return inner.representativeTilePaintColor?.opacity(amount)
    case .semantic, .terminalChrome, .tileStyle:
      return nil
    }
  }

  fileprivate func isInterpolableTilePaint(to other: AnyShapeStyle) -> Bool {
    switch (self, other) {
    case (.color, .color):
      return true
    case (.linearGradient(let a), .linearGradient(let b)):
      return a.gradient.stops.count == b.gradient.stops.count
    case (.radialGradient(let a), .radialGradient(let b)):
      return a.gradient.stops.count == b.gradient.stops.count
    default:
      return false
    }
  }

  fileprivate func interpolatedTilePaint(
    to other: AnyShapeStyle,
    progress t: Double
  ) -> AnyShapeStyle {
    switch (self, other) {
    case (.color(var a), .color(let b)):
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .color(a)

    case (.linearGradient(var a), .linearGradient(let b)):
      guard a.animatableData.isInterpolable(to: b.animatableData) else {
        return .linearGradient(b)
      }
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .linearGradient(a)

    case (.radialGradient(var a), .radialGradient(let b)):
      guard
        a.gradient.animatableData.isInterpolable(
          to: b.gradient.animatableData
        )
      else {
        return .radialGradient(b)
      }
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .radialGradient(a)

    default:
      return other
    }
  }
}
