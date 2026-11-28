#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import ucrt
#endif

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
    let pxWidth = Int128(frameCells.width) * Int128(metrics.width)
    let pxHeight = Int128(frameCells.height) * Int128(metrics.height)
    let diameterPx = max(0, min(pxWidth, pxHeight))
    let radiusPx = diameterPx / 2
    return SubpixelRadii(
      rx: Int(clamping: radiusPx / Int128(subpixelPxWidth)),
      ry: Int(clamping: radiusPx / Int128(subpixelPxHeight))
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
    let halfWidthPx = (Int128(frameCells.width) * Int128(metrics.width)) / 2
    let halfHeightPx = (Int128(frameCells.height) * Int128(metrics.height)) / 2
    return SubpixelRadii(
      rx: Int(clamping: halfWidthPx / Int128(subpixelPxWidth)),
      ry: Int(clamping: halfHeightPx / Int128(subpixelPxHeight))
    )
  }
}

extension BrailleCanvas {
  /// Retains the full shape's parametric samples even at the flat tip of a
  /// long, thin ellipse. Each quadrant is monotone in both coordinates:
  /// search for the steps crossing the viewport and skip runs of identical
  /// rounded samples. Connecting consecutive distinct samples lights exactly
  /// the same dots as walking the entire quadrant.
  mutating func strokeShapeEllipse(
    centerX cx: Int, centerY cy: Int, radiusX rx: Int, radiusY ry: Int
  ) {
    let width = subpixelWidth
    let height = subpixelHeight
    let (sum, overflow) = rx.addingReportingOverflow(ry)
    guard rx > 0, ry > 0, !overflow, sum <= Int.max / 4,
      !ClippedRaster.usesExactOutline(radiusX: rx, radiusY: ry, width: width, height: height)
    else {
      strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      return
    }
    let steps = 4 * sum
    let quarter = steps / 4
    func sample(_ i: Int) -> CellPoint {
      let angle = (2.0 * .pi) * Double(i) / Double(steps)
      return CellPoint(
        x: SaturatingConversion.adding(cx, Int((Double(rx) * cos(angle)).rounded())),
        y: SaturatingConversion.adding(cy, Int((Double(ry) * sin(angle)).rounded())))
    }
    func first(_ start: Int, _ end: Int, where matches: (CellPoint) -> Bool) -> Int {
      var low = start
      var high = end + 1
      while low < high {
        let middle = low + (high - low) / 2
        if matches(sample(middle)) { high = middle } else { low = middle + 1 }
      }
      return low
    }
    for quadrant in 0..<4 {
      let start = quadrant * quarter
      let end = start + quarter
      let xIncreasing = quadrant >= 2
      let yIncreasing = quadrant == 0 || quadrant == 3
      let xEntry = first(start, end) { xIncreasing ? $0.x >= 0 : $0.x < width }
      let yEntry = first(start, end) { yIncreasing ? $0.y >= 0 : $0.y < height }
      let xExit = first(start, end) { xIncreasing ? $0.x >= width : $0.x < 0 }
      let yExit = first(start, end) { yIncreasing ? $0.y >= height : $0.y < 0 }
      // Include either end of a crossing line even if no endpoint lies inside.
      var index = max(start, max(xEntry, yEntry) - 1)
      let last = min(end, xExit, yExit)
      guard index <= last else { continue }
      var previous = sample(index)
      setPixel(x: previous.x, y: previous.y)
      while index < last {
        index = first(index + 1, last) { $0 != previous }
        guard index <= last else { break }
        let next = sample(index)
        line(from: (previous.x, previous.y), to: (next.x, next.y))
        previous = next
      }
    }
  }
}
