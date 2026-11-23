/// Value-semantic ordered scratch. Reads observe previous writes. Snapshots retain
/// their original rows and complete glyphs after the buffer changes.
public struct CellEffectBuffer: Sendable {
  public let bounds: CellRect
  private let initial: CellLayer?
  private var edits: [CellPoint: CellSample] = [:]

  /// Creates an empty layer in the supplied coordinate system.
  public init(bounds: CellRect) {
    self.bounds = bounds
    initial = nil
  }

  package init(bounds: CellRect, source: CellLayer) {
    self.bounds = bounds
    initial = source
  }

  /// Returns the structural contribution at a column. Outside the buffer it is empty.
  public func sample(at point: CellPoint) -> CellSample {
    guard bounds.contains(point) else { return .empty }
    if let edit = edits[point] { return edit }
    guard let initial else { return .empty }
    let sample = initial.sample(at: point)
    switch sample {
    case .empty: return .empty
    case .glyph(let glyph):
      return glyph.width <= bounds.maxX - point.x ? sample : .empty
    case .continuation(let back):
      guard back <= point.x - bounds.origin.x,
        let glyph = initial.glyph(occupying: point),
        glyph.width - back <= bounds.maxX - point.x
      else { return .empty }
      return sample
    }
  }

  /// Writes one whole glyph, clearing both ends of every span it intersects.
  public mutating func set(_ glyph: CellGlyph, at point: CellPoint) {
    guard bounds.contains(point), glyph.width > 0, glyph.width <= bounds.maxX - point.x else {
      return
    }
    for offset in 0..<glyph.width { clear(at: .init(x: point.x + offset, y: point.y)) }
    edits[point] = .glyph(glyph)
    for offset in 1..<glyph.width {
      edits[.init(x: point.x + offset, y: point.y)] = .continuation(columnsBack: offset)
    }
  }

  /// Clears the entire glyph occupying a column.
  public mutating func clear(at point: CellPoint) {
    guard bounds.contains(point) else { return }
    let lead: CellPoint
    switch sample(at: point) {
    case .empty: return
    case .glyph: lead = point
    case .continuation(let back): lead = .init(x: point.x - back, y: point.y)
    }
    guard case .glyph(let glyph) = sample(at: lead) else { return }
    for offset in 0..<glyph.width {
      edits[.init(x: lead.x + offset, y: lead.y)] = .empty
    }
  }

  /// Copies a rectangle from a stable source, including its holes. Partial glyphs
  /// at either edge do not contribute. The two origins specify the translation.
  public mutating func blit(_ source: CellLayer, from rect: CellRect, to origin: CellPoint) {
    guard let read = rect.intersection(source.readableBounds) else { return }
    let translated = CellRect(
      origin: .init(
        x: SaturatingConversion.adding(origin.x, read.origin.x - rect.origin.x),
        y: SaturatingConversion.adding(origin.y, read.origin.y - rect.origin.y)),
      size: read.size)
    guard let output = translated.intersection(bounds) else { return }
    for y in output.origin.y..<output.maxY {
      let sy = SaturatingConversion.adding(read.origin.y, y - translated.origin.y)
      var x = output.origin.x
      while x < output.maxX {
        let sx = SaturatingConversion.adding(read.origin.x, x - translated.origin.x)
        let point = CellPoint(x: x, y: y)
        if case .glyph(let glyph) = source.sample(at: .init(x: sx, y: sy)),
          glyph.width > 0, glyph.width <= output.maxX - x, glyph.width <= read.maxX - sx
        {
          set(glyph, at: point)
          x += glyph.width
        } else {
          clear(at: point)
          x += 1
        }
      }
    }
  }

  /// Returns an immutable view of the current contents.
  public func snapshot() -> CellLayer {
    CellLayer(bounds: bounds, readableBounds: bounds) { point in self.sample(at: point) }
  }
}
