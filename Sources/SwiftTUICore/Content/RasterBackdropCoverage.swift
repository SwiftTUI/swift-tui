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
  case "▄":
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
