/// Actual writes into a paint target. A written default space and an unwritten column
/// have identical RasterCell values. This plane exists only while a cell effect needs it.
final class RasterCellCapture {
  var written: [[Bool]]
  let inheritedBackdrop: CellLayer?

  init(size: CellSize, inheritedBackdrop: CellLayer? = nil) {
    written = Array(repeating: Array(repeating: false, count: size.width), count: size.height)
    self.inheritedBackdrop = inheritedBackdrop
  }

  func mark(x: Int, y: Int, width: Int, written value: Bool = true) {
    guard written.indices.contains(y) else { return }
    let start = max(0, x)
    let end = min(written[y].count, SaturatingConversion.adding(x, width))
    guard start < end else { return }
    for column in start..<end { written[y][column] = value }
  }
}

extension Rasterizer {
  /// Retains Swift array snapshots. Writers detach touched rows on their next write.
  func cellLayer(
    cells: [[RasterCell]], capture: RasterCellCapture?, absoluteBounds: CellRect,
    origin: CellPoint, allowsLink: Bool, includeInherited: Bool
  ) -> CellLayer {
    let bounds = absoluteBounds.relative(to: origin)
    let written = capture?.written
    let inherited = includeInherited ? capture?.inheritedBackdrop : nil
    return CellLayer(bounds: bounds, readableBounds: bounds) { point in
      let x = SaturatingConversion.adding(point.x, origin.x)
      let y = SaturatingConversion.adding(point.y, origin.y)
      guard cells.indices.contains(y), cells[y].indices.contains(x) else { return .empty }
      if let written, !written[y][x] {
        return inherited?.sample(at: .init(x: x, y: y)) ?? .empty
      }
      let cell = cells[y][x]
      let lead = cell.continuationLeadX ?? x
      guard cells[y].indices.contains(lead), lead <= x, lead >= absoluteBounds.origin.x else {
        return .empty
      }
      let width = cells[y][lead].spanWidth
      let end = SaturatingConversion.adding(lead, width)
      guard end > x, end <= min(cells[y].count, absoluteBounds.maxX) else { return .empty }
      return lead == x
        ? .glyph(CellGlyph(cell, allowsLink: allowsLink))
        : .continuation(columnsBack: x - lead)
    }
  }
}

extension CellRect {
  func relative(to point: CellPoint) -> Self {
    Self(
      origin: .init(
        x: SaturatingConversion.subtracting(origin.x, point.x),
        y: SaturatingConversion.subtracting(origin.y, point.y)), size: size)
  }
}
