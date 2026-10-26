extension Rasterizer {
  internal func sample(
    _ gradient: LinearGradient,
    in bounds: CellRect,
    x: Int,
    y: Int
  ) -> Color? {
    let stops = gradient.gradient.stops
    guard let first = stops.first else {
      return nil
    }
    guard stops.count > 1, bounds.size.width > 0, bounds.size.height > 0 else {
      return first.color
    }

    let start = (x: gradient.startPoint.x, y: gradient.startPoint.y)
    let end = (x: gradient.endPoint.x, y: gradient.endPoint.y)
    let point = (
      x: Double(x - bounds.origin.x) + 0.5,
      y: Double(y - bounds.origin.y) + 0.5
    )
    let normalizedPoint = (
      x: point.x / Double(max(1, bounds.size.width)),
      y: point.y / Double(max(1, bounds.size.height))
    )

    let axis = (x: end.x - start.x, y: end.y - start.y)
    let axisLengthSquared = (axis.x * axis.x) + (axis.y * axis.y)
    let t: Double
    if axisLengthSquared == 0 {
      t = 0
    } else {
      let offset = (x: normalizedPoint.x - start.x, y: normalizedPoint.y - start.y)
      t = min(
        1,
        max(
          0,
          ((offset.x * axis.x) + (offset.y * axis.y)) / axisLengthSquared
        )
      )
    }

    if t <= first.location {
      return first.color
    }
    if let last = stops.last, t >= last.location {
      return last.color
    }

    for index in 0..<(stops.count - 1) {
      let lower = stops[index]
      let upper = stops[index + 1]
      guard t >= lower.location, t <= upper.location else {
        continue
      }

      let range = max(0.0001, upper.location - lower.location)
      let localT = (t - lower.location) / range
      return lower.color.interpolated(to: upper.color, progress: localT)
    }

    return stops.last?.color
  }

  /// - Parameter aspectRatio: Cell height divided by cell width, from the
  ///   resolved style environment's ``CellPixelMetrics``.
  internal func sample(
    _ gradient: RadialGradient,
    in bounds: CellRect,
    aspectRatio: Double,
    x: Int,
    y: Int
  ) -> Color? {
    let stops = gradient.gradient.stops
    guard let first = stops.first else {
      return nil
    }
    guard stops.count > 1, bounds.size.width > 0, bounds.size.height > 0 else {
      return first.color
    }

    // Center in cell-space coordinates (not normalized).
    let center = (
      x: Double(bounds.origin.x) + gradient.center.x * Double(bounds.size.width),
      y: Double(bounds.origin.y) + gradient.center.y * Double(bounds.size.height)
    )

    // Distance from the sample cell's center to the gradient center.
    // Vertical offsets are scaled by the cell aspect ratio so falloff is
    // measured in device-pixel space rather than raw cell space: a terminal
    // cell is roughly twice as tall as it is wide, so an uncorrected
    // distance paints a circle as a ~2:1 vertical ellipse.  This matches how
    // `Circle` and `Capsule` correct curved geometry through
    // ``CellPixelMetrics``.  Radii stay denominated in horizontal cells, so
    // the horizontal reach of an existing gradient is unchanged and only the
    // vertical over-reach is corrected.
    let px = Double(x) + 0.5
    let py = Double(y) + 0.5
    let dx = px - center.x
    let dy = (py - center.y) * aspectRatio
    let distance = (dx * dx + dy * dy).squareRoot()

    // Normalize to [0, 1] using startRadius and endRadius.  Guard the
    // degenerate case where endRadius == startRadius so we always pin
    // to the end color without a divide-by-zero.
    let denominator = max(0.0001, gradient.endRadius - gradient.startRadius)
    let tRaw = (distance - gradient.startRadius) / denominator
    let t = min(1, max(0, tRaw))

    if t <= first.location {
      return first.color
    }
    if let last = stops.last, t >= last.location {
      return last.color
    }

    for index in 0..<(stops.count - 1) {
      let lower = stops[index]
      let upper = stops[index + 1]
      guard t >= lower.location, t <= upper.location else {
        continue
      }
      let range = max(0.0001, upper.location - lower.location)
      let localT = (t - lower.location) / range
      return lower.color.interpolated(to: upper.color, progress: localT)
    }

    return stops.last?.color
  }

  /// The part of `rect` a stroke along it can paint, in `rect`-local cells:
  /// the surface narrowed by `clip`, widened by a few cells so that a wide
  /// glyph starting just outside still reaches its visible half. Empty when
  /// none of it is visible. A track walks only this window, so a stroke
  /// around a rectangle far larger than the surface costs only its visible
  /// cells (STUI-796); every cell left out would be clipped by its write.
  internal func strokeWindow(
    for rect: CellRect,
    cells: [[RasterCell]],
    clip: CellRect?
  ) -> CellRect {
    let surface = CellRect(
      origin: .zero, size: .init(width: cells.first?.count ?? 0, height: cells.count))
    let margin = 4
    guard let paintable = intersect(surface, clip),
      let visible = intersect(
        CellRect(
          origin: .init(
            x: SaturatingConversion.subtracting(paintable.origin.x, margin),
            y: SaturatingConversion.subtracting(paintable.origin.y, margin)),
          size: .init(
            width: SaturatingConversion.adding(paintable.size.width, 2 * margin),
            height: SaturatingConversion.adding(paintable.size.height, 2 * margin))),
        rect)
    else {
      return .zero
    }
    return CellRect(
      origin: .init(
        x: SaturatingConversion.subtracting(visible.origin.x, rect.origin.x),
        y: SaturatingConversion.subtracting(visible.origin.y, rect.origin.y)),
      size: visible.size)
  }

  internal func intersect(
    _ lhs: CellRect?,
    _ rhs: CellRect?
  ) -> CellRect? {
    switch (lhs, rhs) {
    case (nil, nil):
      return nil
    case (let rect?, nil), (nil, let rect?):
      return rect
    case (let lhsRect?, let rhsRect?):
      return intersect(lhsRect, rhsRect)
    }
  }

  internal func intersect(
    _ lhs: CellRect,
    _ rhs: CellRect
  ) -> CellRect? {
    let minX = max(lhs.origin.x, rhs.origin.x)
    let minY = max(lhs.origin.y, rhs.origin.y)
    let maxX = min(lhs.maxX, rhs.maxX)
    let maxY = min(lhs.maxY, rhs.maxY)

    guard maxX > minX, maxY > minY else {
      return nil
    }

    return CellRect(
      origin: CellPoint(x: minX, y: minY),
      size: CellSize(
        width: SaturatingConversion.subtracting(maxX, minX),
        height: SaturatingConversion.subtracting(maxY, minY))
    )
  }

  /// Thin single-character adapter over ``BorderSet`` used by the
  /// shape-stroke path and rule painter, which deal in single `Character`
  /// values rather than the multi-rune edge strings that power the
  /// layout-aware border path. Derived glyphs fall back to a space if the
  /// underlying edge is empty (``BorderSet/none`` style).
  internal func write(
    _ character: Character,
    width: Int = 1,
    style: ResolvedTextStyle? = nil,
    hyperlink: String? = nil,
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    // Incremental repaint clamps writes to the EXACT dirty-row set (F125):
    // the paint walk culls by the dirty hull, so a node spanning two
    // disjoint dirty bands reaches rows between them — rows that were
    // never cleared and still hold the prior frame's composited cells.
    // Re-writing there double-applies translucent composition and the
    // surface drifts a step per incremental frame. `nil` (fresh raster)
    // never clamps.
    if let dirtyRows, !dirtyRows.contains(y) {
      return
    }
    let glyphWidth = max(1, width)
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }
    if let clip {
      guard x >= clip.origin.x,
        x + glyphWidth <= clip.maxX,
        y >= clip.origin.y,
        y < clip.maxY
      else {
        return
      }
    }

    let composedBlock = compositeVerticalBlockCell(
      RasterCell(character: character, spanWidth: glyphWidth, style: style, hyperlink: hyperlink),
      over: cells[y][x], blendMode: blendMode)
    let underlayStyle = cells[y][x].style
    let finalStyle: ResolvedTextStyle?
    if let composedBlock {
      finalStyle = composedBlock.style
    } else {
      switch (style, underlayStyle) {
      case (nil, nil):
        finalStyle = nil
      case (let overlayStyle?, nil):
        finalStyle = overlayStyle.isDefault ? nil : overlayStyle
      case (nil, let underlayStyle?):
        let compositedStyle = Self.emptyCompositingStyle.composited(
          over: underlayStyle,
          blendMode: blendMode
        )
        finalStyle = compositedStyle.isDefault ? nil : compositedStyle
      case (let overlayStyle?, let underlayStyle?):
        let compositedStyle = overlayStyle.composited(
          over: underlayStyle,
          blendMode: blendMode
        )
        finalStyle = compositedStyle.isDefault ? nil : compositedStyle
      }

    }

    for offset in 0..<glyphWidth {
      let targetX = x + offset
      guard targetX >= 0, targetX < cells[y].count else {
        continue
      }
      clearExistingGlyph(atX: targetX, y: y, cells: &cells)
    }

    cells[y][x] = RasterCell(
      character: composedBlock?.character ?? character,
      spanWidth: glyphWidth,
      style: finalStyle,
      hyperlink: hyperlink
    )

    if glyphWidth > 1 {
      for offset in 1..<glyphWidth {
        let targetX = x + offset
        guard targetX >= 0, targetX < cells[y].count else {
          continue
        }
        cells[y][targetX] = RasterCell(
          character: " ",
          spanWidth: 0,
          continuationLeadX: x,
          style: finalStyle,
          hyperlink: hyperlink
        )
      }
    }

    if rasterBackdropCoverage(for: character, spanWidth: glyphWidth) != .none
      || (style?.backgroundColor?.alpha ?? 0) > 0
    {
      presentationRecorder?.appendCellFragment(
        from: cells,
        x: x,
        y: y,
        width: glyphWidth,
        effects: presentationEffects
      )
    }
  }

  internal func clearExistingGlyph(
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]]
  ) {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }

    let cell = cells[y][x]
    if let leadX = cell.continuationLeadX {
      clearLeadGlyph(atX: leadX, y: y, cells: &cells)
      return
    }

    if cell.spanWidth > 1 {
      clearLeadGlyph(atX: x, y: y, cells: &cells)
      return
    }

    cells[y][x] = .empty
  }

  internal func clearLeadGlyph(
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]]
  ) {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }

    let spanWidth = max(1, cells[y][x].spanWidth)
    for offset in 0..<spanWidth {
      let targetX = x + offset
      guard targetX >= 0, targetX < cells[y].count else {
        continue
      }
      cells[y][targetX] = .empty
    }
  }
}
