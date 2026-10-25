#if canImport(Darwin)
  import Darwin  // macOS, iOS, tvOS, watchOS
#elseif canImport(Glibc)
  import Glibc  // Linux
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc  // WebAssembly (WASI)
#elseif canImport(ucrt)
  import ucrt  // Windows
#endif

/// A single Braille cell's 2×4 subpixel mask.
///
/// Dots are addressed by (x, y) where `x ∈ {0, 1}` and `y ∈ {0, 1, 2, 3}`.
/// The rendered glyph is `U+2800 + mask`, so an empty mask renders as
/// the blank Braille glyph and a fully-set mask renders as `⣿`.
public struct BrailleCell: Equatable, Sendable {
  public private(set) var mask: UInt8

  public init() {
    mask = 0
  }

  public init(mask: UInt8) {
    self.mask = mask
  }

  /// Sets the dot at `(x, y)` in the cell's 2×4 subpixel grid.
  /// Out-of-range coordinates are silently ignored.
  public mutating func set(x: Int, y: Int) {
    guard let bit = Self.bit(x: x, y: y) else { return }
    mask |= bit
  }

  /// Clears the dot at `(x, y)`.
  public mutating func clear(x: Int, y: Int) {
    guard let bit = Self.bit(x: x, y: y) else { return }
    mask &= ~bit
  }

  /// Whether the dot at `(x, y)` is set.
  public func contains(x: Int, y: Int) -> Bool {
    guard let bit = Self.bit(x: x, y: y) else { return false }
    return mask & bit != 0
  }

  /// The rendered Braille glyph for this cell.
  public var glyph: Character {
    Character(UnicodeScalar(0x2800 + Int(mask))!)
  }

  package static func bitMask(x: Int, y: Int) -> UInt8? {
    switch (x, y) {
    case (0, 0): return 0x01
    case (0, 1): return 0x02
    case (0, 2): return 0x04
    case (0, 3): return 0x40
    case (1, 0): return 0x08
    case (1, 1): return 0x10
    case (1, 2): return 0x20
    case (1, 3): return 0x80
    default: return nil
    }
  }

  private static func bit(x: Int, y: Int) -> UInt8? {
    bitMask(x: x, y: y)
  }
}

/// A 2D Braille subpixel canvas sized in terminal cells.
///
/// Each cell holds a 2×4 dot grid, so a canvas of `(width: W, height: H)`
/// cells has a subpixel resolution of `(2W, 4H)`. Drawing primitives take
/// subpixel coordinates and set the corresponding dots.
public struct BrailleCanvas: Equatable, Sendable {
  public let width: Int  // cells
  public let height: Int  // cells
  public private(set) var cells: [[BrailleCell]]

  public init(width: Int, height: Int) {
    self.width = max(0, width)
    self.height = max(0, height)
    self.cells = Array(
      repeating: Array(repeating: BrailleCell(), count: max(0, width)),
      count: max(0, height)
    )
  }

  /// Subpixel dimensions: `(width * 2, height * 4)`.
  public var subpixelWidth: Int { width * 2 }
  public var subpixelHeight: Int { height * 4 }

  /// Reads the cell at the given (cell-space) coordinates. Returns an
  /// empty cell for out-of-range queries rather than trapping.
  public func cell(x: Int, y: Int) -> BrailleCell {
    guard y >= 0, y < height, x >= 0, x < width else { return BrailleCell() }
    return cells[y][x]
  }

  /// Sets a single subpixel dot at `(x, y)` in the `(subpixelWidth,
  /// subpixelHeight)` grid. Out-of-range coordinates are ignored.
  public mutating func setPixel(x: Int, y: Int) {
    guard x >= 0, x < subpixelWidth, y >= 0, y < subpixelHeight else { return }
    let cellX = x / 2
    let cellY = y / 4
    let dotX = x % 2
    let dotY = y % 4
    cells[cellY][cellX].set(x: dotX, y: dotY)
  }

  /// Clears the subpixel dot at `(x, y)`.
  public mutating func clearPixel(x: Int, y: Int) {
    guard x >= 0, x < subpixelWidth, y >= 0, y < subpixelHeight else { return }
    let cellX = x / 2
    let cellY = y / 4
    let dotX = x % 2
    let dotY = y % 4
    cells[cellY][cellX].clear(x: dotX, y: dotY)
  }

  /// Draws a line from `(x0, y0)` to `(x1, y1)` using Bresenham's algorithm.
  /// Subpixel coordinates. Out-of-range dots are clipped.
  ///
  /// Any `Int` endpoints are accepted: only the steps inside the canvas are
  /// visited, and they light the same dots the unclipped walk would.
  public mutating func line(from: (x: Int, y: Int), to: (x: Int, y: Int)) {
    ClippedRaster.line(from: from, to: to, width: subpixelWidth, height: subpixelHeight) {
      setPixel(x: $0, y: $1)
    }
  }

  /// Draws the outline of a rectangle with top-left at `(x, y)` and size
  /// `(w, h)` in subpixels. Out-of-range dots are clipped.
  public mutating func strokeRect(x: Int, y: Int, width w: Int, height h: Int) {
    ClippedRaster.strokeRect(
      x: x, y: y, width: w, height: h, bufferWidth: subpixelWidth, bufferHeight: subpixelHeight
    ) { setPixel(x: $0, y: $1) }
  }

  /// Fills a rectangle in subpixels. Out-of-range dots are clipped.
  public mutating func fillRect(x: Int, y: Int, width w: Int, height h: Int) {
    ClippedRaster.fillRect(
      x: x, y: y, width: w, height: h, bufferWidth: subpixelWidth, bufferHeight: subpixelHeight
    ) { setPixel(x: $0, y: $1) }
  }

  /// Draws the outline of a circle centered at `(cx, cy)` with the given
  /// radius, in subpixels. Uses the midpoint circle algorithm.
  ///
  /// Out-of-range dots are clipped. A circle too large for the midpoint walk
  /// to be bounded by the canvas draws the visible part of its outline
  /// column by column and row by row instead.
  public mutating func strokeCircle(centerX cx: Int, centerY cy: Int, radius: Int) {
    guard radius >= 0 else { return }
    if radius == 0 {
      setPixel(x: cx, y: cy)
      return
    }
    let width = subpixelWidth
    let height = subpixelHeight
    guard
      ClippedRaster.boundingBoxMeetsBuffer(
        centerX: cx, centerY: cy, radiusX: radius, radiusY: radius, width: width, height: height)
    else { return }
    guard
      ClippedRaster.usesExactOutline(
        radiusX: radius, radiusY: radius, width: width, height: height)
    else {
      ClippedRaster.ellipseOutline(
        centerX: cx, centerY: cy, radiusX: radius, radiusY: radius, width: width, height: height
      ) { setPixel(x: $0, y: $1) }
      return
    }
    var x = radius
    var y = 0
    var err = 1 - radius
    while x >= y {
      setPixel(x: cx + x, y: cy + y)
      setPixel(x: cx + y, y: cy + x)
      setPixel(x: cx - y, y: cy + x)
      setPixel(x: cx - x, y: cy + y)
      setPixel(x: cx - x, y: cy - y)
      setPixel(x: cx - y, y: cy - x)
      setPixel(x: cx + y, y: cy - x)
      setPixel(x: cx + x, y: cy - y)
      y += 1
      if err < 0 {
        err += 2 * y + 1
      } else {
        x -= 1
        err += 2 * (y - x) + 1
      }
    }
  }

  /// Fills a disc centered at `(cx, cy)` with the given radius.
  ///
  /// A scanline fill: each row `cy + dy` spans `cx ± floor(sqrt(r² - dy²))`.
  /// Only canvas rows are visited, and out-of-range dots are clipped.
  public mutating func fillCircle(centerX cx: Int, centerY cy: Int, radius: Int) {
    ClippedRaster.fillCircle(
      centerX: cx, centerY: cy, radius: radius, width: subpixelWidth, height: subpixelHeight
    ) { setPixel(x: $0, y: $1) }
  }

  /// Fills an ellipse centered at `(cx, cy)` with x-radius `rx` and
  /// y-radius `ry`, in subpixels.
  ///
  /// Uses a scanline fill driven by the parametric ellipse equation
  /// `(x/rx)² + (y/ry)² ≤ 1`. Only canvas rows are visited, and out-of-range
  /// dots are clipped.
  public mutating func fillEllipse(
    centerX cx: Int,
    centerY cy: Int,
    radiusX rx: Int,
    radiusY ry: Int
  ) {
    ClippedRaster.fillEllipse(
      centerX: cx, centerY: cy, radiusX: rx, radiusY: ry, width: subpixelWidth,
      height: subpixelHeight
    ) { setPixel(x: $0, y: $1) }
  }

  /// Draws the outline of an ellipse centered at `(cx, cy)` with
  /// x-radius `rx` and y-radius `ry`, in subpixels.
  ///
  /// Samples the parametric form `(cx + rx·cos θ, cy + ry·sin θ)` with
  /// enough steps that adjacent samples are at most one pixel apart.
  /// Out-of-range dots are clipped. An ellipse too large to walk whole
  /// computes only the samples near the canvas, so it lights the same dots.
  ///
  /// Two outlines are approximated instead:
  /// - the sharp end of a very flat ellipse, where more samples would reach
  ///   the canvas than the largest whole walk takes;
  /// - radii that sum past `Int.max / 4`.
  ///
  /// These light, in each column and row the outline crosses, the dot
  /// nearest the crossing. That can differ from the walk by a dot near each
  /// crossing.
  public mutating func strokeEllipse(
    centerX cx: Int,
    centerY cy: Int,
    radiusX rx: Int,
    radiusY ry: Int
  ) {
    guard rx >= 0, ry >= 0 else { return }
    let width = subpixelWidth
    let height = subpixelHeight
    if rx == 0 || ry == 0 {
      // A point, or the axis segment between the two extremes.
      ClippedRaster.fillEllipse(
        centerX: cx, centerY: cy, radiusX: rx, radiusY: ry, width: width, height: height
      ) { setPixel(x: $0, y: $1) }
      return
    }
    guard
      ClippedRaster.boundingBoxMeetsBuffer(
        centerX: cx, centerY: cy, radiusX: rx, radiusY: ry, width: width, height: height)
    else { return }
    guard ClippedRaster.usesExactOutline(radiusX: rx, radiusY: ry, width: width, height: height)
    else {
      let walked = ClippedRaster.parametricOutline(
        centerX: cx, centerY: cy, radiusX: rx, radiusY: ry, minimumSteps: 32, width: width,
        height: height
      ) { setPixel(x: $0, y: $1) }
      if !walked {
        ClippedRaster.ellipseOutline(
          centerX: cx, centerY: cy, radiusX: rx, radiusY: ry, width: width, height: height
        ) { setPixel(x: $0, y: $1) }
      }
      return
    }
    // 4 · (rx + ry) samples is enough for a smooth closed curve on any
    // reasonable canvas size; the minimum of 32 avoids gaps for tiny
    // ellipses where the arithmetic bound would round down to something
    // too small to close the perimeter.
    let steps = max(32, 4 * (rx + ry))
    let twoPi = 2.0 * .pi
    let rxD = Double(rx)
    let ryD = Double(ry)
    var previous: (x: Int, y: Int)?
    for i in 0...steps {
      let angle = twoPi * Double(i) / Double(steps)
      let x = cx + Int((rxD * cos(angle)).rounded())
      let y = cy + Int((ryD * sin(angle)).rounded())
      if let previous { line(from: previous, to: (x, y)) } else { setPixel(x: x, y: y) }
      previous = (x, y)
    }
  }
}
