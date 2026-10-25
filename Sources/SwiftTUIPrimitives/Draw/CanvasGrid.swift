#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import ucrt
#endif

/// Rasterization grid used by ``CanvasContext`` cell-space drawing.
///
/// A canvas is sized in terminal cells.
/// The grid sets the number of logical drawing samples in each terminal cell.
/// It also selects the glyph family that packs those samples into one cell during rasterization.
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

  /// The primitives below accept any `Int` geometry: they visit only
  /// samples inside the buffer (see `ClippedRaster`) and light the same
  /// samples the unclipped walks would.
  package mutating func line(from: (x: Int, y: Int), to: (x: Int, y: Int)) {
    ClippedRaster.line(from: from, to: to, width: pixelWidth, height: pixelHeight) {
      setPixel(x: $0, y: $1)
    }
  }

  package mutating func strokeRect(x: Int, y: Int, width: Int, height: Int) {
    ClippedRaster.strokeRect(
      x: x, y: y, width: width, height: height, bufferWidth: pixelWidth,
      bufferHeight: pixelHeight
    ) { setPixel(x: $0, y: $1) }
  }

  package mutating func fillRect(x: Int, y: Int, width: Int, height: Int) {
    ClippedRaster.fillRect(
      x: x, y: y, width: width, height: height, bufferWidth: pixelWidth,
      bufferHeight: pixelHeight
    ) { setPixel(x: $0, y: $1) }
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
    let width = pixelWidth
    let height = pixelHeight
    guard
      ClippedRaster.boundingBoxMeetsBuffer(
        centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY, width: width,
        height: height)
    else { return }
    guard
      ClippedRaster.usesExactOutline(
        radiusX: radiusX, radiusY: radiusY, width: width, height: height)
    else {
      ClippedRaster.ellipseOutline(
        centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY, width: width,
        height: height
      ) { setPixel(x: $0, y: $1) }
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
    ClippedRaster.fillEllipse(
      centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY,
      width: pixelWidth, height: pixelHeight
    ) { setPixel(x: $0, y: $1) }
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
