/// Actual writes into a paint target. A written default space and an unwritten column
/// have identical RasterCell values. This plane exists only while a cell effect needs it.
final class RasterCellCapture {
  enum Column {
    case untouched, cleared, painted, replaced
    var hasPaint: Bool { self == .painted || self == .replaced }
  }

  var columns: [[Column]]
  let inheritedBackdrop: CellLayer?
  let viewport: CellRect?
  /// Full logical paint target, in scratch coordinates, across all tiles.
  let paintDomain: CellRect?
  let originInRoot: CellPoint
  let projectsImages: Bool
  let defersCoverage: Bool
  var fractionalCoverage: [CellPoint: Double] = [:]

  init(
    size: CellSize, inheritedBackdrop: CellLayer? = nil, originInRoot: CellPoint = .zero,
    defersCoverage: Bool = false, projectsImages: Bool = false, viewport: CellRect? = nil,
    paintDomain: CellRect? = nil
  ) {
    self.viewport = viewport
    self.paintDomain = paintDomain
    self.projectsImages = projectsImages
    self.originInRoot = originInRoot
    self.defersCoverage = defersCoverage
    columns = Array(repeating: Array(repeating: .untouched, count: size.width), count: size.height)
    self.inheritedBackdrop = inheritedBackdrop
  }

  func mark(x: Int, y: Int, width: Int, written value: Bool = true) {
    guard columns.indices.contains(y) else { return }
    let start = max(0, x)
    let end = min(columns[y].count, SaturatingConversion.adding(x, width))
    guard start < end else { return }
    for column in start..<end {
      if value {
        let previous = columns[y][column]
        columns[y][column] = previous == .cleared || previous == .replaced ? .replaced : .painted
      } else {
        columns[y][column] = .cleared
      }
      if !fractionalCoverage.isEmpty {
        fractionalCoverage.removeValue(forKey: .init(x: column, y: y))
      }
    }
  }
}

extension Rasterizer {
  /// Retains Swift array snapshots. Writers detach touched rows on their next write.
  func cellLayer(
    cells: [[RasterCell]], capture: RasterCellCapture?, absoluteBounds: CellRect,
    origin: CellPoint, allowsLink: Bool, backdropContext: CellEffectContext? = nil
  ) -> CellLayer {
    let bounds = absoluteBounds.relative(to: origin)
    let columns = capture?.columns
    let coverage = capture?.fractionalCoverage ?? [:]
    let inherited = backdropContext == nil ? nil : capture?.inheritedBackdrop
    return CellLayer(bounds: bounds, readableBounds: bounds) { point in
      let x = SaturatingConversion.adding(point.x, origin.x)
      let y = SaturatingConversion.adding(point.y, origin.y)
      let inScratch = cells.indices.contains(y) && cells[y].indices.contains(x)
      if !inScratch || columns?[y][x] == .untouched {
        guard let inherited else { return .empty }
        let point = CellPoint(x: x, y: y)
        let sample = inherited.sample(at: point)
        let lead: Int
        let width: Int
        switch sample {
        case .empty: return .empty
        case .glyph(let glyph):
          lead = x
          width = glyph.width
        case .continuation(let back):
          guard let glyph = inherited.glyph(occupying: point) else { return .empty }
          lead = SaturatingConversion.subtracting(x, back)
          width = glyph.width
        }
        let end = SaturatingConversion.adding(lead, width)
        guard lead >= absoluteBounds.origin.x, end <= absoluteBounds.maxX else { return .empty }
        // Local writes take ownership of complete inherited spans, including
        // the other half of a wide glyph at the edge of a scratch tile.
        if width > 1, let columns, columns.indices.contains(y) {
          let left = max(0, lead)
          let right = min(end, columns[y].count)
          if left < right, columns[y][left..<right].contains(where: { $0 != .untouched }) {
            return .empty
          }
        }
        return sample
      }
      if columns?[y][x] == .cleared { return .empty }
      let cell = cells[y][x]
      let lead = cell.continuationLeadX ?? x
      guard cells[y].indices.contains(lead), lead <= x, lead >= absoluteBounds.origin.x else {
        return .empty
      }
      let width = cells[y][lead].spanWidth
      let end = SaturatingConversion.adding(lead, width)
      guard end > x, end <= min(cells[y].count, absoluteBounds.maxX) else { return .empty }
      if lead != x { return .continuation(columnsBack: x - lead) }
      var glyph = CellGlyph(cell, allowsLink: allowsLink)
      if !coverage.isEmpty, let fraction = coverage[.init(x: x, y: y)] {
        glyph.paint.coverage = fraction
        if let backdropContext {
          // Source readers retain coverage for subsequent masks. Destination
          // readers see the earlier glyph as painted over the enclosing paper.
          let lower = inherited?.glyph(occupying: .init(x: x, y: y))
          let paper =
            lower?.paint.background.color(in: backdropContext.appearance)
            ?? backdropContext.appearance.backgroundColor
          glyph.paint = backdropContext.compositingCoverage(of: glyph, over: paper)
        }
      } else if let backdropContext, columns?[y][x] == .painted,
        let lower = inherited?.glyph(occupying: .init(x: x, y: y))
      {
        // Ordinary sibling paint inherits lower channels. Explicit replacements
        // already name their final channels and retain authored defaults.
        var visible = cell
        let underlay = lower.rasterStyle(for: lower.paint, in: backdropContext.appearance)
        visible.style = (cell.style ?? Self.emptyCompositingStyle).composited(over: underlay)
        glyph = CellGlyph(visible, allowsLink: allowsLink)
      }
      return .glyph(glyph)
    }
  }
}

extension CellRect {
  package func relative(to point: CellPoint) -> Self {
    Self(
      origin: .init(
        x: SaturatingConversion.subtracting(origin.x, point.x),
        y: SaturatingConversion.subtracting(origin.y, point.y)), size: size)
  }
}
