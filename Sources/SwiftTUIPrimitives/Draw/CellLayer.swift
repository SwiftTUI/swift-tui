/// A stored ink or paper channel. Indexed values use the active terminal palette.
public enum CellChannel: Equatable, Sendable {
  case `default`
  case color(Color)
  case indexed(UInt8)

  package var paletteIndex: UInt8? {
    if case .indexed(let index) = self { return index }
    return nil
  }

  package func color(in appearance: TerminalAppearance) -> Color? {
    switch self {
    case .default: return nil
    case .color(let color): return color
    case .indexed(let index):
      let n = Int(index)
      if let color = appearance.palette[n] { return color }
      if n >= 232 { return Color(white: Double(8 + 10 * (n - 232)) / 255) }
      let cube = n - 16
      func component(_ value: Int) -> Double {
        value == 0 ? 0 : Double(55 + 40 * value) / 255
      }
      return Color(
        red: component(cube / 36), green: component(cube / 6 % 6), blue: component(cube % 6))
    }
  }
}

/// Stored ink, paper and whole-glyph coverage.
public struct CellPaint: Equatable, Sendable {
  public var foreground: CellChannel
  public var background: CellChannel
  public var coverage: Double {
    didSet { coverage = Self.normalized(coverage) }
  }

  public init(
    foreground: CellChannel = .default, background: CellChannel = .default, coverage: Double = 1
  ) {
    self.foreground = foreground
    self.background = background
    self.coverage = Self.normalized(coverage)
  }

  private static func normalized(_ value: Double) -> Double {
    value.isNaN ? 0 : min(1, max(0, value))
  }
}

/// A complete glyph and the metadata painted at its lead column.
public struct CellGlyph: Equatable, Sendable {
  public var character: Character {
    didSet { width = cellWidth(of: character) }
  }
  public private(set) var width: Int
  public var paint: CellPaint
  public var emphasis: TextStyle.TextEmphasis
  public var underline: TextLineStyle?
  public var strikethrough: TextLineStyle?
  public private(set) var link: LinkDestination?

  public init(
    _ character: Character, paint: CellPaint = .init(), emphasis: TextStyle.TextEmphasis = [],
    underline: TextLineStyle? = nil, strikethrough: TextLineStyle? = nil
  ) {
    self.character = character
    self.width = cellWidth(of: character)
    self.paint = paint
    self.emphasis = emphasis
    self.underline = underline
    self.strikethrough = strikethrough
  }

  package init(_ cell: RasterCell, allowsLink: Bool) {
    let style = cell.style
    character = cell.character
    width = cell.spanWidth
    paint = CellPaint(
      foreground: style?.foregroundPaletteIndex.map(CellChannel.indexed) ?? style?.foregroundColor
        .map(CellChannel.color) ?? .default,
      background: style?.backgroundPaletteIndex.map(CellChannel.indexed) ?? style?.backgroundColor
        .map(CellChannel.color) ?? .default)
    emphasis = style?.emphasis ?? []
    underline = style?.underlineStyle
    strikethrough = style?.strikethroughStyle
    link = allowsLink ? cell.hyperlink.map { LinkDestination($0) } : nil
    originalOpacity = style?.opacity ?? 1
  }

  package var originalOpacity: Double = 1

  /// Copies the destination carried by a sampled glyph.
  public mutating func copyLink(from glyph: CellGlyph) { link = glyph.link }

  /// Removes the link from this glyph.
  public mutating func removeLink() { link = nil }
}

/// A column's structural contribution to a layer.
public enum CellSample: Equatable, Sendable {
  case empty
  case glyph(CellGlyph)
  case continuation(columnsBack: Int)
}

/// An immutable snapshot with the read window of the current shader invocation.
public struct CellLayer: Sendable {
  public let bounds: CellRect
  public let readableBounds: CellRect
  #if DEBUG
    private var diagnostic: CellReadDiagnostic?
  #endif
  private let read: @Sendable (CellPoint) -> CellSample

  package init(
    bounds: CellRect, readableBounds: CellRect,
    read: @escaping @Sendable (CellPoint) -> CellSample
  ) {
    self.bounds = bounds
    self.readableBounds = readableBounds
    self.read = read
  }

  package func restricted(to window: CellRect, pass: CellEffectPass? = nil) -> Self {
    let layer = Self(
      bounds: bounds, readableBounds: readableBounds.intersection(window) ?? .zero, read: read)
    #if DEBUG
      var checked = layer
      checked.diagnostic = pass?.diagnostic
      return checked
    #else
      return layer
    #endif
  }

  /// Reads the lead, continuation or hole at a column inside the declared window.
  public func sample(at point: CellPoint) -> CellSample {
    guard readableBounds.contains(point) else {
      #if DEBUG
        if bounds.contains(point) { diagnostic?.reportInvalidRead() }
      #endif
      return .empty
    }
    return read(point)
  }

  /// Returns the whole occupying glyph, even when its lead lies outside the read window.
  public func glyph(occupying point: CellPoint) -> CellGlyph? {
    switch sample(at: point) {
    case .glyph(let glyph): return glyph
    case .continuation(let columnsBack):
      let owner = CellPoint(x: SaturatingConversion.subtracting(point.x, columnsBack), y: point.y)
      if case .glyph(let glyph) = read(owner) { return glyph }
      return nil
    case .empty: return nil
    }
  }
}
