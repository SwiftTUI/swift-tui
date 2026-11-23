/// The maximum distance from an output column to a requested input column.
public enum CellSampleOffset: Equatable, Sendable {
  case cells(x: Int, y: Int)
  case layerBounds

  /// Permits reads at the output column, including its occupying glyph.
  public static var zero: Self { .cells(x: 0, y: 0) }

  package func window(around point: CellPoint, in bounds: CellRect) -> CellRect {
    guard case .cells(let x, let y) = self else { return bounds }
    let dx = max(0, x)
    let dy = max(0, y)
    let left = max(bounds.origin.x, SaturatingConversion.subtracting(point.x, dx))
    let top = max(bounds.origin.y, SaturatingConversion.subtracting(point.y, dy))
    let right = min(
      bounds.maxX, SaturatingConversion.adding(SaturatingConversion.adding(point.x, dx), 1))
    let bottom = min(
      bounds.maxY, SaturatingConversion.adding(SaturatingConversion.adding(point.y, dy), 1))
    guard right > left, bottom > top else { return .zero }
    return CellRect(
      origin: .init(x: left, y: top), size: .init(width: right - left, height: bottom - top))
  }
}

/// Where a shader may produce cells, in the subject's laid-out coordinate system.
public enum CellDrawingRegion: Equatable, Sendable {
  case source
  case outset(x: Int, y: Int)
  case viewport
  case rect(CellRect)

  package func bounds(source: CellRect, viewport: CellRect) -> CellRect {
    switch self {
    case .source:
      return source.intersection(viewport) ?? .zero
    case .rect(let rect):
      return rect.intersection(viewport) ?? .zero
    case .viewport:
      return viewport
    case .outset(let x, let y):
      let left = max(
        viewport.origin.x, SaturatingConversion.subtracting(source.origin.x, max(0, x)))
      let top = max(viewport.origin.y, SaturatingConversion.subtracting(source.origin.y, max(0, y)))
      let right = min(viewport.maxX, SaturatingConversion.adding(source.maxX, max(0, x)))
      let bottom = min(viewport.maxY, SaturatingConversion.adding(source.maxY, max(0, y)))
      guard right > left, bottom > top else { return .zero }
      return CellRect(
        origin: .init(x: left, y: top), size: .init(width: right - left, height: bottom - top))
    }
  }
}

/// Geometry and display inputs for one placed cell effect. All bounds use local coordinates.
public struct CellEffectContext: Equatable, Sendable {
  public let sourceBounds: CellRect
  public let outputBounds: CellRect
  public let viewport: CellRect
  public let originInRoot: CellPoint
  public let appearance: TerminalAppearance
  public let cellPixelMetrics: CellPixelMetrics

  public init(
    sourceBounds: CellRect, outputBounds: CellRect, viewport: CellRect,
    originInRoot: CellPoint, appearance: TerminalAppearance,
    cellPixelMetrics: CellPixelMetrics = .estimated
  ) {
    self.sourceBounds = sourceBounds
    self.outputBounds = outputBounds
    self.viewport = viewport
    self.originInRoot = originInRoot
    self.appearance = appearance
    self.cellPixelMetrics = cellPixelMetrics
  }

  /// Resolves stored ink and paper in display order over the supplied lower paper.
  public func resolvedColors(
    for paint: CellPaint, emphasis: TextStyle.TextEmphasis = [], over background: Color? = nil
  ) -> (foreground: Color, background: Color) {
    let lower = background ?? appearance.backgroundColor
    var ink = paint.foreground.color(in: appearance) ?? appearance.foregroundColor
    var paper = paint.background.color(in: appearance) ?? lower
    if emphasis.contains(.reverse) { swap(&ink, &paper) }
    let resolvedPaper = paper.composited(over: lower)
    return (ink.composited(over: resolvedPaper), resolvedPaper)
  }
}
