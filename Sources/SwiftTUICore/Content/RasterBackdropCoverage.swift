package enum RasterBackdropCoverage: Equatable, Sendable {
  case none
  case full
  case quadrant(mask: UInt8)
  case braille(mask: UInt8)
  case textApproximation
}

package func rasterBackdropCoverage(
  for glyph: Character?,
  spanWidth: Int
) -> RasterBackdropCoverage {
  guard spanWidth > 0, let glyph else {
    return .none
  }

  // ASCII is the common case and never a block or braille glyph: white space
  // (U+0009...U+000D, U+0020) covers nothing and every other ASCII glyph is
  // text.
  if let ascii = singleASCIIByte(of: glyph) {
    return ascii == 0x20 || (0x09...0x0D).contains(ascii) ? .none : .textApproximation
  }

  if glyph.unicodeScalars.allSatisfy(\.properties.isWhitespace) {
    return .none
  }

  if let scalar = glyph.unicodeScalars.first,
    glyph.unicodeScalars.count == 1,
    scalar.value >= 0x2800,
    scalar.value <= 0x28FF
  {
    let mask = UInt8(scalar.value - 0x2800)
    return mask == 0 ? .none : .braille(mask: mask)
  }

  switch glyph {
  case "█", "▓", "▒", "░":
    return .full
  case "▀":
    return .quadrant(mask: 0b0011)
  // Backdrop sampling is quadrant-resolution, so lower fractional blocks use
  // the bottom-row approximation.
  case "▄", "▂":
    return .quadrant(mask: 0b1100)
  case "▌":
    return .quadrant(mask: 0b0101)
  case "▐":
    return .quadrant(mask: 0b1010)
  case "▘":
    return .quadrant(mask: 0b0001)
  case "▝":
    return .quadrant(mask: 0b0010)
  case "▖":
    return .quadrant(mask: 0b0100)
  case "▗":
    return .quadrant(mask: 0b1000)
  case "▚":
    return .quadrant(mask: 0b1001)
  case "▞":
    return .quadrant(mask: 0b0110)
  case "▛":
    return .quadrant(mask: 0b0111)
  case "▜":
    return .quadrant(mask: 0b1011)
  case "▙":
    return .quadrant(mask: 0b1101)
  case "▟":
    return .quadrant(mask: 0b1110)
  default:
    return .textApproximation
  }
}

/// Whether `glyph` covers any part of the backdrop beneath its cells:
/// `rasterBackdropCoverage(for:spanWidth:) != .none`.
@inline(__always)
package func glyphCoversBackdrop(_ glyph: Character, spanWidth: Int) -> Bool {
  rasterBackdropCoverage(for: glyph, spanWidth: spanWidth) != .none
}

/// The single ASCII byte `character` consists of, or `nil` when it is any
/// other cluster (including the two-scalar `"\r\n"`).
@inline(__always)
package func singleASCIIByte(of character: Character) -> UInt8? {
  let utf8 = character.utf8
  guard utf8.count == 1 else {
    return nil
  }
  return utf8.first
}
