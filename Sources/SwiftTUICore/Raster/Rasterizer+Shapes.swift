extension Rasterizer {
  package struct SubpixelRadii: Equatable {
    package let rx: Int
    package let ry: Int
  }

  /// Given a cell frame and the current cell-pixel metrics, computes the
  /// largest pixel-true circle's radii in Braille sub-pixel units.
  /// Sub-pixel dimensions are `cellPixelMetrics.width / 2` and
  /// `cellPixelMetrics.height / 4`.
  package static func subpixelCircleRadii(
    frameCells: CellSize,
    metrics: CellPixelMetrics
  ) -> SubpixelRadii {
    let subpixelPxWidth = max(1, metrics.width / 2)
    let subpixelPxHeight = max(1, metrics.height / 4)
    let pxWidth = frameCells.width * metrics.width
    let pxHeight = frameCells.height * metrics.height
    let diameterPx = max(0, min(pxWidth, pxHeight))
    let radiusPx = diameterPx / 2
    return SubpixelRadii(
      rx: radiusPx / subpixelPxWidth,
      ry: radiusPx / subpixelPxHeight
    )
  }

  /// Converts a frame's pixel semi-axes to Braille sub-pixel units. Both
  /// solid fills and cell masks subtract one for inclusive-bound semantics.
  package static func subpixelEllipseRadii(
    frameCells: CellSize,
    metrics: CellPixelMetrics
  ) -> SubpixelRadii {
    let subpixelPxWidth = max(1, metrics.width / 2)
    let subpixelPxHeight = max(1, metrics.height / 4)
    let halfWidthPx = (frameCells.width * metrics.width) / 2
    let halfHeightPx = (frameCells.height * metrics.height) / 2
    return SubpixelRadii(
      rx: halfWidthPx / subpixelPxWidth,
      ry: halfHeightPx / subpixelPxHeight
    )
  }
}
