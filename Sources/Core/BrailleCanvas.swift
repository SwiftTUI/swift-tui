#if canImport(Darwin)
  public import Darwin  // macOS, iOS, tvOS, watchOS
#elseif canImport(Glibc)
  public import Glibc  // Linux, Android
#elseif canImport(WASILibc)
  public import WASILibc  // WebAssembly (WASI)
#elseif canImport(ucrt)
  public import ucrt  // Windows
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

  private static func bit(x: Int, y: Int) -> UInt8? {
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
  public mutating func line(from: (x: Int, y: Int), to: (x: Int, y: Int)) {
    // Bresenham's line algorithm. Standard implementation.
    var x0 = from.x
    var y0 = from.y
    let x1 = to.x
    let y1 = to.y
    let dx = abs(x1 - x0)
    let sx = x0 < x1 ? 1 : -1
    let dy = -abs(y1 - y0)
    let sy = y0 < y1 ? 1 : -1
    var error = dx + dy

    while true {
      setPixel(x: x0, y: y0)
      if x0 == x1, y0 == y1 { break }
      let e2 = 2 * error
      if e2 >= dy {
        if x0 == x1 { break }
        error += dy
        x0 += sx
      }
      if e2 <= dx {
        if y0 == y1 { break }
        error += dx
        y0 += sy
      }
    }
  }

  /// Draws the outline of a rectangle with top-left at `(x, y)` and size
  /// `(w, h)` in subpixels.
  public mutating func strokeRect(x: Int, y: Int, width w: Int, height h: Int) {
    guard w > 0, h > 0 else { return }
    // Top and bottom
    for dx in 0..<w {
      setPixel(x: x + dx, y: y)
      if h > 1 {
        setPixel(x: x + dx, y: y + h - 1)
      }
    }
    // Left and right (skip corners already drawn)
    if h > 2 {
      for dy in 1..<(h - 1) {
        setPixel(x: x, y: y + dy)
        if w > 1 {
          setPixel(x: x + w - 1, y: y + dy)
        }
      }
    }
  }

  /// Fills a rectangle in subpixels.
  public mutating func fillRect(x: Int, y: Int, width w: Int, height h: Int) {
    guard w > 0, h > 0 else { return }
    for dy in 0..<h {
      for dx in 0..<w {
        setPixel(x: x + dx, y: y + dy)
      }
    }
  }

  /// Draws the outline of a circle centered at `(cx, cy)` with the given
  /// radius, in subpixels. Uses the midpoint circle algorithm.
  public mutating func strokeCircle(centerX cx: Int, centerY cy: Int, radius: Int) {
    guard radius >= 0 else { return }
    if radius == 0 {
      setPixel(x: cx, y: cy)
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
  public mutating func fillCircle(centerX cx: Int, centerY cy: Int, radius: Int) {
    guard radius >= 0 else { return }
    // Simple scanline fill: for each row in [cy-radius, cy+radius], fill
    // the horizontal span from cx - Δx to cx + Δx where Δx = sqrt(r² - dy²).
    let r2 = radius * radius
    for dy in -radius...radius {
      let dx = Int(Double(r2 - dy * dy).squareRoot().rounded(.down))
      let y = cy + dy
      for x in (cx - dx)...(cx + dx) {
        setPixel(x: x, y: y)
      }
    }
  }

  /// Fills an ellipse centered at `(cx, cy)` with x-radius `rx` and
  /// y-radius `ry`, in subpixels.
  ///
  /// Uses a scanline fill driven by the parametric ellipse equation
  /// `(x/rx)² + (y/ry)² ≤ 1`. Out-of-range dots are clipped by the
  /// underlying `setPixel` call.
  public mutating func fillEllipse(
    centerX cx: Int,
    centerY cy: Int,
    radiusX rx: Int,
    radiusY ry: Int
  ) {
    guard rx >= 0, ry >= 0 else { return }
    if rx == 0 && ry == 0 {
      setPixel(x: cx, y: cy)
      return
    }
    if rx == 0 {
      for dy in -ry...ry {
        setPixel(x: cx, y: cy + dy)
      }
      return
    }
    if ry == 0 {
      for dx in -rx...rx {
        setPixel(x: cx + dx, y: cy)
      }
      return
    }
    let ryD = Double(ry)
    let rxD = Double(rx)
    for dy in -ry...ry {
      let t = Double(dy) / ryD
      let dxMax = Int((rxD * (1.0 - t * t).squareRoot()).rounded(.down))
      let y = cy + dy
      for dx in -dxMax...dxMax {
        setPixel(x: cx + dx, y: y)
      }
    }
  }

  /// Draws the outline of an ellipse centered at `(cx, cy)` with
  /// x-radius `rx` and y-radius `ry`, in subpixels.
  ///
  /// Samples the parametric form `(cx + rx·cos θ, cy + ry·sin θ)` with
  /// enough steps that adjacent samples are at most one pixel apart.
  public mutating func strokeEllipse(
    centerX cx: Int,
    centerY cy: Int,
    radiusX rx: Int,
    radiusY ry: Int
  ) {
    guard rx >= 0, ry >= 0 else { return }
    if rx == 0 && ry == 0 {
      setPixel(x: cx, y: cy)
      return
    }
    if rx == 0 {
      for dy in -ry...ry {
        setPixel(x: cx, y: cy + dy)
      }
      return
    }
    if ry == 0 {
      for dx in -rx...rx {
        setPixel(x: cx + dx, y: cy)
      }
      return
    }
    // 4 · (rx + ry) samples is enough for a smooth closed curve on any
    // reasonable canvas size; the minimum of 32 avoids gaps for tiny
    // ellipses where the arithmetic bound would round down to something
    // too small to close the perimeter.
    let steps = max(32, 4 * (rx + ry))
    let twoPi = 2.0 * 3.14159265358979323846
    let rxD = Double(rx)
    let ryD = Double(ry)
    for i in 0..<steps {
      let angle = twoPi * Double(i) / Double(steps)
      let x = cx + Int((rxD * cos(angle)).rounded())
      let y = cy + Int((ryD * sin(angle)).rounded())
      setPixel(x: x, y: y)
    }
  }
}
