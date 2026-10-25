extension Rasterizer {
  /// Fills a normalized unit-rect path into the Braille subpixel canvas under
  /// the given winding rule.
  ///
  /// The path is authored in unit `[0,1]×[0,1]` coordinates (frame-relative),
  /// so the unit→subpixel map is simply `(u·subW, v·subH)`: the path stretches
  /// to fill the placed frame. We scale the path first, then flatten in
  /// subpixel space so the curve tolerance is meaningful, then run a
  /// winding-rule scanline fill that reuses ``BrailleCanvas/setPixel(x:y:)``.
  internal func fillPath(
    _ unitPath: Path,
    rule: FillRule,
    into canvas: inout BrailleCanvas
  ) {
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    let polylines =
      unitPath
      .scaledBy(sx: Double(subW), sy: Double(subH))
      .flattened(tolerance: 0.3)
    scanlineFillSubpixels(
      polylines,
      rule: rule,
      subpixelWidth: subW,
      subpixelHeight: subH,
      into: &canvas)
  }

  /// Strokes a normalized unit-rect path's outline into the Braille subpixel
  /// canvas by chaining ``BrailleCanvas/line(from:to:)`` over the flattened
  /// polylines.
  internal func strokePath(
    _ unitPath: Path,
    into canvas: inout BrailleCanvas
  ) {
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    // Strokes map onto the inclusive `[0, sub-1]` range (matching the analytic
    // shapes' `-1` bound) so an edge at unit 1.0 lands on the last valid
    // subpixel instead of being clipped off-grid. Fill uses the full `[0, sub)`
    // range via scanline center-sampling.
    let polylines =
      unitPath
      .scaledBy(sx: Double(max(1, subW - 1)), sy: Double(max(1, subH - 1)))
      .flattened(tolerance: 0.3)
    for polyline in polylines where polyline.count >= 2 {
      for index in 0..<(polyline.count - 1) {
        // A finite path point can lie far outside the frame. Clip the segment
        // far beyond the canvas (segments inside the limit pass unchanged), so
        // rounding cannot trap and the line keeps its direction; the canvas
        // walks only its own subpixels.
        guard
          let segment = SegmentClipping.clipped(
            from: polyline[index], to: polyline[index + 1], within: Self.strokeCoordinateLimit)
        else {
          continue
        }
        canvas.line(
          from: (x: roundToInt(segment.start.x), y: roundToInt(segment.start.y)),
          to: (x: roundToInt(segment.end.x), y: roundToInt(segment.end.y)))
      }
    }
  }

  /// Stroke segments are clipped to this many subpixels from the origin.
  private static let strokeCoordinateLimit = Double(Int.max / 8)

  /// Strokes a border that stays inside the shape: the stroked outline
  /// intersected with the filled interior, so no part of the stroke spills
  /// outside the path. Generalizes the analytic shapes' inset-then-stroke to
  /// arbitrary geometry (mask AND mask) on the subpixel grid.
  internal func strokeBorderPath(
    _ unitPath: Path,
    rule: FillRule,
    into canvas: inout BrailleCanvas
  ) {
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    var fillMask = BrailleCanvas(width: canvas.width, height: canvas.height)
    fillPath(unitPath, rule: rule, into: &fillMask)
    var strokeMask = BrailleCanvas(width: canvas.width, height: canvas.height)
    strokePath(unitPath, into: &strokeMask)

    for sy in 0..<subH {
      for sx in 0..<subW {
        let cellX = sx / 2
        let cellY = sy / 4
        let dotX = sx % 2
        let dotY = sy % 4
        if strokeMask.cell(x: cellX, y: cellY).contains(x: dotX, y: dotY),
          fillMask.cell(x: cellX, y: cellY).contains(x: dotX, y: dotY)
        {
          canvas.setPixel(x: sx, y: sy)
        }
      }
    }
  }

  /// Whether any subpixel of the cell is covered by the same scanline fill
  /// used to paint the path. A clip or tile must not discard a half-covered
  /// cell merely because one representative point lies outside the shape.
  internal func pathContainsCell(
    _ unitPath: Path,
    rule: FillRule,
    cellRelX: Int,
    cellRelY: Int,
    subpixelWidth subW: Int,
    subpixelHeight subH: Int
  ) -> Bool {
    guard subW > 0, subH > 0 else {
      return false
    }
    guard cellRelX >= 0, cellRelY >= 0, cellRelX < subW / 2, cellRelY < subH / 4 else {
      return false
    }
    let polylines = unitPath.scaledBy(sx: Double(subW), sy: Double(subH)).flattened(tolerance: 0.3)
    return visitScanlineSpans(polylines, rule: rule, rows: (cellRelY * 4)..<(cellRelY * 4 + 4)) {
      start, end, _ in
      let first = max(Double(cellRelX * 2), (start - 0.5).rounded(.up))
      return first < Double(cellRelX * 2 + 2) && first + 0.5 < end
    }
  }

  // MARK: - Scanline fill

  private struct ScanEdge {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
    /// +1 when the edge runs in increasing-y, -1 in decreasing-y.
    var direction: Int
  }

  private func scanlineFillSubpixels(
    _ polylines: [[Point]],
    rule: FillRule,
    subpixelWidth subW: Int,
    subpixelHeight subH: Int,
    into canvas: inout BrailleCanvas
  ) {
    _ = visitScanlineSpans(polylines, rule: rule, rows: 0..<subH) { start, end, row in
      fillSpan(from: start, to: end, row: row, subpixelWidth: subW, into: &canvas)
      return false
    }
  }

  /// A cell is covered when any of its subpixel samples would be painted.
  /// Fill and clip use the same flattened edges, half-open crossings and
  /// center sampling, including parity holes and exact boundary ownership.
  private func visitScanlineSpans(
    _ polylines: [[Point]], rule: FillRule, rows: Range<Int>,
    visit: (Double, Double, Int) -> Bool
  ) -> Bool {
    var edges: [ScanEdge] = []
    for polyline in polylines where polyline.count >= 2 {
      var points = polyline
      // Fill always closes each subpath.
      if let first = points.first, let last = points.last, first != last {
        points.append(first)
      }
      for index in 0..<(points.count - 1) {
        let a = points[index]
        let b = points[index + 1]
        guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { continue }
        if a.y == b.y {
          continue  // horizontal edges never cross a scanline
        }
        edges.append(
          ScanEdge(
            x0: a.x, y0: a.y, x1: b.x, y1: b.y,
            direction: b.y > a.y ? 1 : -1))
      }
    }
    guard !edges.isEmpty else { return false }

    for sy in rows {
      let y = Double(sy) + 0.5
      var crossings: [(x: Double, direction: Int)] = []
      for edge in edges {
        let yLow = min(edge.y0, edge.y1)
        let yHigh = max(edge.y0, edge.y1)
        guard y >= yLow, y < yHigh else {
          continue  // half-open interval avoids double counting shared vertices
        }
        let t = (y - edge.y0) / (edge.y1 - edge.y0)
        let x = edge.x0 + t * (edge.x1 - edge.x0)
        crossings.append((x: x, direction: edge.direction))
      }
      guard crossings.count >= 2 else {
        continue
      }
      crossings.sort { $0.x < $1.x }

      var winding = 0
      for index in 0..<(crossings.count - 1) {
        winding += (rule == .nonZero) ? crossings[index].direction : 1
        let inside = (rule == .nonZero) ? (winding != 0) : (winding % 2 != 0)
        guard inside else {
          continue
        }
        if visit(crossings[index].x, crossings[index + 1].x, sy) { return true }
      }
    }
    return false
  }

  /// Lights every subpixel in row `row` whose center lies in `[xStart, xEnd)`.
  private func fillSpan(
    from xStart: Double,
    to xEnd: Double,
    row: Int,
    subpixelWidth subW: Int,
    into canvas: inout BrailleCanvas
  ) {
    guard xEnd > xStart else {
      return
    }
    // Subpixel `sx` has center `sx + 0.5`; include it when the center is in
    // `[xStart, xEnd)`.
    let lo = Int(min(Double(subW), max(0, (xStart - 0.5).rounded(.up))))
    let hi = Int(min(Double(subW), max(0, (xEnd - 0.5).rounded(.up)))) - 1
    guard lo <= hi else {
      return
    }
    for sx in lo...hi {
      canvas.setPixel(x: sx, y: row)
    }
  }

  private func roundToInt(_ value: Double) -> Int {
    SaturatingConversion.int(value, rounding: .toNearestOrAwayFromZero)
  }
}
