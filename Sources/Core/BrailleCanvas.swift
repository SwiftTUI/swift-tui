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
