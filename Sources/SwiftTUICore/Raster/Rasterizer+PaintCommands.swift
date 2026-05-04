extension Rasterizer {
  internal func paintFill(
    in bounds: CellRect,
    geometry: ShapeGeometry,
    insetAmount: Int,
    style: AnyShapeStyle,
    mode: ShapeFillMode,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let shapeBounds = insetBounds(bounds, by: max(0, insetAmount), strokeBorder: true)
    guard shapeBounds.size.width > 0, shapeBounds.size.height > 0 else {
      return
    }
    let colorMode = resolvedColorMode(
      from: style,
      environment: environment
    )

    // A nil constant color means the fill is fully transparent — skip painting.
    if case .constant(nil) = colorMode {
      return
    }

    // Curved shapes normally use a Braille subpixel canvas so their
    // edges antialias onto the 2x4 dot grid. Tile styles are the
    // exception: they need per-cell glyph writes, so they fall through
    // to the general cell-walking loop below (which calls
    // `shapeContains`, and that now knows about curved geometry).
    switch geometry {
    case .circle, .ellipse, .capsule:
      if case .tile = colorMode {
        break
      }
      paintBrailleShape(
        geometry: geometry,
        shapeBounds: shapeBounds,
        colorMode: colorMode,
        stroke: false,
        environment: environment,
        cells: &cells,
        clip: clip
      )
      return
    case .rectangle, .roundedRectangle:
      break
    }

    // Detect whether this fill carries alpha for the tint path.
    let constantColor: Color?
    let isTranslucent: Bool
    let tileStyle: TileStyle?
    switch colorMode {
    case .constant(let color):
      constantColor = color
      isTranslucent = (color?.alpha ?? 0) < 1
      tileStyle = nil
    case .sampled, .sampledRadial:
      constantColor = nil
      // Sampled (gradient) fills may have per-stop alpha.
      isTranslucent = false
      tileStyle = nil
    case .tile(let tile):
      constantColor = nil
      isTranslucent = false
      tileStyle = tile
    }

    for y in shapeBounds.origin.y..<(shapeBounds.origin.y + shapeBounds.size.height) {
      var x = shapeBounds.origin.x
      let rowEnd = shapeBounds.origin.x + shapeBounds.size.width
      while x < rowEnd {
        guard
          shapeContains(
            pointX: x,
            pointY: y,
            in: shapeBounds,
            geometry: geometry,
            fillMode: mode
          )
        else {
          x += 1
          continue
        }

        if let tileStyle {
          // Tile style: overwrite the cell with the pattern glyph using
          // the tile's foreground and optional background, resolved per
          // cell so gradient paints sample at the current point.
          let localX = x - shapeBounds.origin.x
          let localY = y - shapeBounds.origin.y
          write(
            tileStyle.pattern.character(atX: localX, y: localY),
            style: resolvedTileCellStyle(
              tileStyle,
              bounds: shapeBounds,
              sampleX: x,
              sampleY: y,
              environment: environment
            ),
            atX: x,
            y: y,
            cells: &cells,
            clip: clip
          )
          x += 1
          continue
        }

        if isTranslucent {
          // Translucent constant fill: tint existing cell in-place.
          if let color = constantColor, color.alpha > 0 {
            tintCell(atX: x, y: y, with: color, cells: &cells, clip: clip)
          }
        } else if let constantColor {
          // Opaque constant fill: overwrite cell.
          let resolvedStyle = ResolvedTextStyle(backgroundColor: constantColor)
          write(
            " ",
            style: resolvedStyle.isDefault ? nil : resolvedStyle,
            atX: x,
            y: y,
            cells: &cells,
            clip: clip
          )
        } else {
          // Sampled (gradient) fill: resolve per-cell.
          let fillColor = resolveColor(
            from: colorMode,
            bounds: shapeBounds,
            sampleX: x,
            sampleY: y
          )
          if let fillColor, fillColor.alpha < 1 {
            if fillColor.alpha > 0 {
              tintCell(atX: x, y: y, with: fillColor, cells: &cells, clip: clip)
            }
          } else {
            write(
              " ",
              style: resolvedBackgroundTextStyle(
                colorMode: colorMode,
                bounds: shapeBounds,
                x: x,
                y: y
              ),
              atX: x,
              y: y,
              cells: &cells,
              clip: clip
            )
          }
        }
        x += 1
      }
    }
  }

  /// Paints a ``Canvas`` view's drawing into the raster buffer.
  ///
  /// Canvas is the arbitrary-drawing escape hatch that sits alongside
  /// the shape pipeline: the layout engine reserves the cell frame, and
  /// here we build a ``CanvasContext`` sized to those cells, invoke the
  /// user's drawing, and copy its direct-cell and grid-glyph layers into
  /// the raster buffer.
  internal func paintCanvasDrawing(
    in bounds: CellRect,
    payload: CanvasPayload,
    foregroundStyle: AnyShapeStyle,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?
  ) {
    let cellW = bounds.size.width
    let cellH = bounds.size.height
    guard cellW > 0, cellH > 0 else {
      return
    }

    let initialForeground =
      resolveColor(
        from: foregroundStyle,
        environment: environment,
        bounds: bounds,
        sampleX: bounds.origin.x,
        sampleY: bounds.origin.y
      )
      ?? environment.theme.foreground

    var context = CanvasContext(
      canvas: CanvasGridBuffer(
        size: CellSize(width: cellW, height: cellH),
        grid: payload.grid
      ),
      foreground: initialForeground,
      background: nil
    )
    guard context.size.width > 0, context.size.height > 0 else {
      return
    }
    payload.drawing.draw(into: &context)

    let originX = bounds.origin.x
    let originY = bounds.origin.y

    // Direct cells paint first so Braille drawing can layer foreground
    // dots over dense per-cell backgrounds.
    for cellY in 0..<cellH {
      for cellX in 0..<cellW {
        guard let cell = context.directCells[cellY][cellX] else {
          continue
        }
        let cellStyle = ResolvedTextStyle(
          foregroundColor: cell.foreground,
          backgroundColor: cell.background
        )
        write(
          cell.character,
          style: cellStyle.isDefault ? nil : cellStyle,
          atX: originX + cellX,
          y: originY + cellY,
          cells: &cells,
          clip: clip
        )
      }
    }

    // Walk the grid canvas and emit a glyph for every cell the drawing
    // touched. Styled sample writes carry one style per terminal cell;
    // unstyled cells fall back to the context's final foreground/background
    // values.
    let finalForeground = context.foreground
    let finalBackground = context.background
    let fallbackStyle = ResolvedTextStyle(
      foregroundColor: finalForeground,
      backgroundColor: finalBackground
    )

    for cellY in 0..<cellH {
      for cellX in 0..<cellW {
        guard let character = context.canvas.character(x: cellX, y: cellY) else {
          continue
        }
        let resolvedStyle = context.gridCellStyles[cellY][cellX] ?? fallbackStyle
        let styleToWrite: ResolvedTextStyle? =
          resolvedStyle.isDefault ? nil : resolvedStyle
        write(
          character,
          style: styleToWrite,
          atX: originX + cellX,
          y: originY + cellY,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  /// Rasterizes a curved shape (`.circle`, `.ellipse`, `.capsule`)
  /// into the Braille subpixel canvas and writes each non-blank cell
  /// into the raster buffer with the resolved foreground color.
  ///
  /// - Parameter stroke: When `true` draws the outline only; otherwise
  ///   fills the interior.
  internal func paintBrailleShape(
    geometry: ShapeGeometry,
    shapeBounds: CellRect,
    colorMode: ResolvedShapeColorMode,
    stroke: Bool,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    backgroundStyle: BorderBackgroundStyle? = nil
  ) {
    let cellW = shapeBounds.size.width
    let cellH = shapeBounds.size.height
    guard cellW > 0, cellH > 0 else {
      return
    }

    var canvas = BrailleCanvas(width: cellW, height: cellH)
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    // Center the shape in the subpixel grid.  `(subW - 1) / 2` keeps
    // the anchor on an integer subpixel even for odd/even widths.
    let cx = (subW - 1) / 2
    let cy = (subH - 1) / 2

    switch geometry {
    case .circle:
      let radii = Self.subpixelCircleRadii(
        frameCells: CellSize(width: cellW, height: cellH),
        metrics: environment.cellPixelMetrics
      )
      // Preserve the (min-1)/2 inclusive-bound semantics of the pre-correction
      // code: at 8x16 metrics, radii.rx == radii.ry == old `(min(subW, subH) - 1) / 2 + 1`
      // (integer off-by-one irrelevant here — we subtract 1 to keep the
      // outline inside the (0...sub-1) coordinate range).
      let rx = max(0, radii.rx - 1)
      let ry = max(0, radii.ry - 1)
      if stroke {
        canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      } else {
        canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      }
    case .ellipse:
      // Compute semi-axes in pixel space, then convert back to sub-pixel
      // coordinates using the current sub-pixel dimensions. The `-1` preserves
      // inclusive-bound semantics so the outline stays within (0...sub-1).
      // At 8x16 metrics (the default), this reproduces the pre-correction
      // output exactly because sub-pixels are square.
      let metrics = environment.cellPixelMetrics
      let subpixelPxWidth = max(1, metrics.width / 2)
      let subpixelPxHeight = max(1, metrics.height / 4)
      let halfWidthPx = (cellW * metrics.width) / 2
      let halfHeightPx = (cellH * metrics.height) / 2
      let rx = max(0, halfWidthPx / subpixelPxWidth - 1)
      let ry = max(0, halfHeightPx / subpixelPxHeight - 1)
      if stroke {
        canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      } else {
        canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      }
    case .capsule:
      drawCapsule(into: &canvas, stroke: stroke, metrics: environment.cellPixelMetrics)
    case .rectangle, .roundedRectangle:
      // Not reachable: the caller dispatches these to the cell-aligned
      // paint path.  We still need the case for exhaustiveness.
      return
    }

    // Walk each Braille cell and emit the glyph with the shape's
    // resolved foreground color.  Empty cells (mask == 0) are skipped
    // so we don't overwrite anything already on the surface.
    let originX = shapeBounds.origin.x
    let originY = shapeBounds.origin.y
    let backgroundColor: Color? =
      backgroundStyle
      .flatMap { $0.backgroundStyle(for: .top) }
      .flatMap { style in
        resolveColor(
          from: resolvedColorMode(from: style, environment: environment),
          bounds: shapeBounds,
          sampleX: originX,
          sampleY: originY
        )
      }

    for cellY in 0..<cellH {
      for cellX in 0..<cellW {
        let cell = canvas.cell(x: cellX, y: cellY)
        guard cell.mask != 0 else {
          continue
        }
        let targetX = originX + cellX
        let targetY = originY + cellY
        let foregroundColor = resolveColor(
          from: colorMode,
          bounds: shapeBounds,
          sampleX: targetX,
          sampleY: targetY
        )
        let resolved = ResolvedTextStyle(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor
        )
        write(
          cell.glyph,
          style: resolved.isDefault ? nil : resolved,
          atX: targetX,
          y: targetY,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  /// Draws a capsule into the Braille canvas. A wide capsule (pxWidth >=
  /// pxHeight in pixel space) has a rectangular body flanked by two
  /// aspect-corrected half-ellipses at the left and right ends; a tall
  /// capsule has its semi-ellipses at the top and bottom.
  internal func drawCapsule(
    into canvas: inout BrailleCanvas,
    stroke: Bool,
    metrics: CellPixelMetrics
  ) {
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    if subW == 1 || subH == 1 {
      // Degenerate: just fill/stroke the whole strip.
      canvas.fillRect(x: 0, y: 0, width: subW, height: subH)
      return
    }

    // Derive cell frame dimensions from the Braille canvas (2 subpixels
    // wide, 4 tall per cell). These are always exact on a well-formed
    // canvas; ceiling-style derivation guards against degenerate inputs.
    let cellW = max(1, (subW + 1) / 2)
    let cellH = max(1, (subH + 3) / 4)
    let subpixelPxWidth = max(1, metrics.width / 2)
    let subpixelPxHeight = max(1, metrics.height / 4)
    let pxWidth = cellW * metrics.width
    let pxHeight = cellH * metrics.height
    // Cap pixel radius = shortest pixel axis / 2 (same as Circle).
    let capRadiusPx = min(pxWidth, pxHeight) / 2
    // Subpixel radii for the cap, preserving the old (-1) inclusive-bound
    // clamp so bit-identity at 8x16 metrics holds.
    let rx = max(0, capRadiusPx / subpixelPxWidth - 1)
    let ry = max(0, capRadiusPx / subpixelPxHeight - 1)

    if pxWidth >= pxHeight {
      // Wide capsule: caps on left/right, body connects horizontally.
      let cy = (subH - 1) / 2
      let leftCx = rx
      let rightCx = subW - 1 - rx
      if stroke {
        // Two half-ellipses plus the two horizontal body edges.
        canvas.strokeEllipse(centerX: leftCx, centerY: cy, radiusX: rx, radiusY: ry)
        canvas.strokeEllipse(centerX: rightCx, centerY: cy, radiusX: rx, radiusY: ry)
        // Top and bottom body edges between the two centers.
        if rightCx > leftCx {
          for x in leftCx...rightCx {
            canvas.setPixel(x: x, y: cy - ry)
            canvas.setPixel(x: x, y: cy + ry)
          }
        }
      } else {
        canvas.fillEllipse(centerX: leftCx, centerY: cy, radiusX: rx, radiusY: ry)
        canvas.fillEllipse(centerX: rightCx, centerY: cy, radiusX: rx, radiusY: ry)
        if rightCx > leftCx {
          let bodyWidth = rightCx - leftCx + 1
          canvas.fillRect(
            x: leftCx,
            y: max(0, cy - ry),
            width: bodyWidth,
            height: min(subH, 2 * ry + 1)
          )
        }
      }
    } else {
      // Tall capsule: caps on top/bottom, body connects vertically.
      let cx = (subW - 1) / 2
      let topCy = ry
      let bottomCy = subH - 1 - ry
      if stroke {
        canvas.strokeEllipse(centerX: cx, centerY: topCy, radiusX: rx, radiusY: ry)
        canvas.strokeEllipse(centerX: cx, centerY: bottomCy, radiusX: rx, radiusY: ry)
        if bottomCy > topCy {
          for y in topCy...bottomCy {
            canvas.setPixel(x: cx - rx, y: y)
            canvas.setPixel(x: cx + rx, y: y)
          }
        }
      } else {
        canvas.fillEllipse(centerX: cx, centerY: topCy, radiusX: rx, radiusY: ry)
        canvas.fillEllipse(centerX: cx, centerY: bottomCy, radiusX: rx, radiusY: ry)
        if bottomCy > topCy {
          let bodyHeight = bottomCy - topCy + 1
          canvas.fillRect(
            x: max(0, cx - rx),
            y: topCy,
            width: min(subW, 2 * rx + 1),
            height: bodyHeight
          )
        }
      }
    }
  }

  internal func tintCell(
    atX x: Int,
    y: Int,
    with overlay: Color,
    cells: inout [[RasterCell]],
    clip: CellRect?
  ) {
    if let clip {
      guard
        x >= clip.origin.x,
        x < clip.origin.x + clip.size.width,
        y >= clip.origin.y,
        y < clip.origin.y + clip.size.height
      else {
        return
      }
    }
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }
    var cell = cells[y][x]
    cell.style = (cell.style ?? .init()).tinted(with: overlay)
    cells[y][x] = cell
  }

}
