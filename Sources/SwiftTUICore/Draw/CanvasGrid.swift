#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import ucrt
#endif

/// Rasterization grid used by ``CanvasContext`` cell-space drawing.
///
/// A canvas is sized in terminal cells. The grid determines how many logical
/// drawing samples exist inside each terminal cell and which glyph family packs
/// those samples back into one cell during rasterization.
public struct CanvasGrid: Equatable, Hashable, Sendable {
  /// Glyph family used to pack grid samples into terminal cells.
  public enum Style: Equatable, Hashable, Sendable {
    /// Braille dots, two columns by four rows per cell.
    case braille2x4
    /// Octant-style two-by-four subdivision. Currently renders with the same
    /// coverage as Braille while keeping the public grid distinction.
    case octant2x4
    /// Sextant-style two-by-three subdivision.
    case sextant2x3
    /// Unicode quadrant block elements, two columns by two rows per cell.
    case quadrant2x2
    /// Upper/lower half-block glyphs, one column by two rows per cell.
    case verticalHalfBlock
    /// Left/right half-block glyphs, two columns by one row per cell.
    case horizontalHalfBlock
    /// One drawing sample per terminal cell.
    case fullCell
  }

  /// The glyph-packing style for this grid.
  public var style: Style

  public init(style: Style = .braille2x4) {
    self.style = style
  }

  public static let braille2x4 = Self(style: .braille2x4)
  public static let octant2x4 = Self(style: .octant2x4)
  public static let sextant2x3 = Self(style: .sextant2x3)
  public static let quadrant2x2 = Self(style: .quadrant2x2)
  public static let verticalHalfBlock = Self(style: .verticalHalfBlock)
  public static let horizontalHalfBlock = Self(style: .horizontalHalfBlock)
  public static let fullCell = Self(style: .fullCell)

  /// Logical drawing columns inside each terminal cell.
  public var subdivisionsX: Int {
    switch style {
    case .braille2x4, .octant2x4, .sextant2x3, .quadrant2x2, .horizontalHalfBlock:
      return 2
    case .verticalHalfBlock, .fullCell:
      return 1
    }
  }

  /// Logical drawing rows inside each terminal cell.
  public var subdivisionsY: Int {
    switch style {
    case .braille2x4, .octant2x4:
      return 4
    case .sextant2x3:
      return 3
    case .quadrant2x2, .verticalHalfBlock:
      return 2
    case .horizontalHalfBlock, .fullCell:
      return 1
    }
  }
}

package struct CanvasGridBuffer: Equatable, Sendable {
  package let size: CellSize
  package let grid: CanvasGrid
  private var masks: [[UInt16]]

  package init(
    size: CellSize,
    grid: CanvasGrid
  ) {
    self.size = CellSize(
      width: max(0, size.width),
      height: max(0, size.height)
    )
    self.grid = grid
    masks = Array(
      repeating: Array(repeating: 0, count: max(0, size.width)),
      count: max(0, size.height)
    )
  }

  package var pixelWidth: Int {
    size.width * grid.subdivisionsX
  }

  package var pixelHeight: Int {
    size.height * grid.subdivisionsY
  }

  package mutating func setPixel(x: Int, y: Int) {
    guard let index = gridIndex(x: x, y: y) else {
      return
    }
    masks[index.cellY][index.cellX] |= bit(localX: index.localX, localY: index.localY)
  }

  package mutating func clearPixel(x: Int, y: Int) {
    guard let index = gridIndex(x: x, y: y) else {
      return
    }
    masks[index.cellY][index.cellX] &= ~bit(localX: index.localX, localY: index.localY)
  }

  package mutating func line(from: (x: Int, y: Int), to: (x: Int, y: Int)) {
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

  package mutating func strokeRect(x: Int, y: Int, width: Int, height: Int) {
    guard width > 0, height > 0 else {
      return
    }
    for dx in 0..<width {
      setPixel(x: x + dx, y: y)
      if height > 1 {
        setPixel(x: x + dx, y: y + height - 1)
      }
    }
    if height > 2 {
      for dy in 1..<(height - 1) {
        setPixel(x: x, y: y + dy)
        if width > 1 {
          setPixel(x: x + width - 1, y: y + dy)
        }
      }
    }
  }

  package mutating func fillRect(x: Int, y: Int, width: Int, height: Int) {
    guard width > 0, height > 0 else {
      return
    }
    for dy in 0..<height {
      for dx in 0..<width {
        setPixel(x: x + dx, y: y + dy)
      }
    }
  }

  package mutating func strokeCircle(centerX: Int, centerY: Int, radius: Int) {
    guard radius >= 0 else { return }
    if radius == 0 {
      setPixel(x: centerX, y: centerY)
      return
    }
    var x = radius
    var y = 0
    var err = 1 - radius
    while x >= y {
      setPixel(x: centerX + x, y: centerY + y)
      setPixel(x: centerX + y, y: centerY + x)
      setPixel(x: centerX - y, y: centerY + x)
      setPixel(x: centerX - x, y: centerY + y)
      setPixel(x: centerX - x, y: centerY - y)
      setPixel(x: centerX - y, y: centerY - x)
      setPixel(x: centerX + y, y: centerY - x)
      setPixel(x: centerX + x, y: centerY - y)
      y += 1
      if err < 0 {
        err += 2 * y + 1
      } else {
        x -= 1
        err += 2 * (y - x) + 1
      }
    }
  }

  package mutating func fillCircle(centerX: Int, centerY: Int, radius: Int) {
    guard radius >= 0 else { return }
    let r2 = radius * radius
    for dy in -radius...radius {
      let dx = Int(Double(r2 - dy * dy).squareRoot().rounded(.down))
      let y = centerY + dy
      for x in (centerX - dx)...(centerX + dx) {
        setPixel(x: x, y: y)
      }
    }
  }

  package mutating func strokeEllipse(
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int
  ) {
    guard radiusX >= 0, radiusY >= 0 else { return }
    if radiusX == 0 && radiusY == 0 {
      setPixel(x: centerX, y: centerY)
      return
    }
    let steps = max(12, (radiusX + radiusY) * 4)
    var previous: (x: Int, y: Int)?
    for step in 0...steps {
      let theta = 2.0 * Double.pi * Double(step) / Double(steps)
      let point = (
        x: centerX + Int((Double(radiusX) * cos(theta)).rounded()),
        y: centerY + Int((Double(radiusY) * sin(theta)).rounded())
      )
      if let previous {
        line(from: previous, to: point)
      } else {
        setPixel(x: point.x, y: point.y)
      }
      previous = point
    }
  }

  package mutating func fillEllipse(
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int
  ) {
    guard radiusX >= 0, radiusY >= 0 else { return }
    if radiusX == 0 && radiusY == 0 {
      setPixel(x: centerX, y: centerY)
      return
    }
    if radiusX == 0 {
      for dy in -radiusY...radiusY {
        setPixel(x: centerX, y: centerY + dy)
      }
      return
    }
    if radiusY == 0 {
      for dx in -radiusX...radiusX {
        setPixel(x: centerX + dx, y: centerY)
      }
      return
    }
    let radiusYD = Double(radiusY)
    let radiusXD = Double(radiusX)
    for dy in -radiusY...radiusY {
      let t = Double(dy) / radiusYD
      let dxMax = Int((radiusXD * (1.0 - t * t).squareRoot()).rounded(.down))
      let y = centerY + dy
      for dx in -dxMax...dxMax {
        setPixel(x: centerX + dx, y: y)
      }
    }
  }

  package func mask(x: Int, y: Int) -> UInt16 {
    guard y >= 0, y < size.height, x >= 0, x < size.width else {
      return 0
    }
    return masks[y][x]
  }

  package func character(x: Int, y: Int) -> Character? {
    let mask = mask(x: x, y: y)
    guard mask != 0 else {
      return nil
    }
    switch grid.style {
    case .braille2x4, .octant2x4:
      return BrailleCell(mask: UInt8(mask & 0x00FF)).glyph
    case .sextant2x3:
      return Self.sextantGlyph(mask)
    case .quadrant2x2:
      return Self.quadrantGlyph(mask)
    case .verticalHalfBlock:
      return Self.verticalHalfBlockGlyph(mask)
    case .horizontalHalfBlock:
      return Self.horizontalHalfBlockGlyph(mask)
    case .fullCell:
      return "█"
    }
  }

  private func gridIndex(
    x: Int,
    y: Int
  ) -> (cellX: Int, cellY: Int, localX: Int, localY: Int)? {
    guard x >= 0, x < pixelWidth, y >= 0, y < pixelHeight else {
      return nil
    }
    let subdivisionsX = grid.subdivisionsX
    let subdivisionsY = grid.subdivisionsY
    return (
      cellX: x / subdivisionsX,
      cellY: y / subdivisionsY,
      localX: x % subdivisionsX,
      localY: y % subdivisionsY
    )
  }

  private func bit(
    localX: Int,
    localY: Int
  ) -> UInt16 {
    switch grid.style {
    case .braille2x4, .octant2x4:
      return UInt16(BrailleCell.bitMask(x: localX, y: localY) ?? 0)
    case .sextant2x3, .quadrant2x2, .verticalHalfBlock, .horizontalHalfBlock, .fullCell:
      return UInt16(1) << UInt16(localY * grid.subdivisionsX + localX)
    }
  }

  private static func sextantGlyph(
    _ mask: UInt16
  ) -> Character {
    let mask = mask & 0b111111
    switch mask {
    case 0:
      return " "
    case 0b010101:
      return "▌"
    case 0b101010:
      return "▐"
    case 0b111111:
      return "█"
    case 1...20:
      return legacyComputingGlyph(offset: Int(mask - 1))
    case 22...41:
      return legacyComputingGlyph(offset: Int(mask - 2))
    case 43...62:
      return legacyComputingGlyph(offset: Int(mask - 3))
    default:
      return "█"
    }
  }

  private static func legacyComputingGlyph(offset: Int) -> Character {
    Character(UnicodeScalar(0x1FB00 + offset)!)
  }

  private static func verticalHalfBlockGlyph(
    _ mask: UInt16
  ) -> Character {
    switch mask & 0b11 {
    case 0b01: return "▀"
    case 0b10: return "▄"
    default: return "█"
    }
  }

  private static func horizontalHalfBlockGlyph(
    _ mask: UInt16
  ) -> Character {
    switch mask & 0b11 {
    case 0b01: return "▌"
    case 0b10: return "▐"
    default: return "█"
    }
  }

  private static func quadrantGlyph(
    _ mask: UInt16
  ) -> Character {
    switch mask & 0b1111 {
    case 0b0001: return "▘"
    case 0b0010: return "▝"
    case 0b0011: return "▀"
    case 0b0100: return "▖"
    case 0b0101: return "▌"
    case 0b0110: return "▞"
    case 0b0111: return "▛"
    case 0b1000: return "▗"
    case 0b1001: return "▚"
    case 0b1010: return "▐"
    case 0b1011: return "▜"
    case 0b1100: return "▄"
    case 0b1101: return "▙"
    case 0b1110: return "▟"
    default: return "█"
    }
  }
}
