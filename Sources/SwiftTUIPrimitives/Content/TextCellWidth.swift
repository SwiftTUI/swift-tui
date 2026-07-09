package func cellWidth(of character: Character) -> Int {
  let scalars = character.unicodeScalars

  // Fast path: single ASCII scalar covers common terminal text and avoids
  // Unicode property lookups for the hot path.
  let first = scalars.first
  guard let first else {
    return 0
  }
  if first.value < 0x80, scalars.dropFirst().isEmpty {
    return first.value == 0 ? 0 : 1
  }

  // Multi-scalar or non-ASCII width is intentionally approximate: it follows
  // the terminal behavior this renderer has historically depended on for
  // emoji, VS16, East Asian wide ranges, and pure zero-width clusters.
  var scalarCount = 0
  var containsEmojiPresentation = false
  var containsEmoji = false
  var containsVS16 = false
  var containsWide = false
  var allZeroWidth = true

  for scalar in scalars {
    scalarCount += 1
    if scalar.properties.isEmojiPresentation {
      containsEmojiPresentation = true
    }
    if scalar.properties.isEmoji {
      containsEmoji = true
    }
    if scalar.value == 0xFE0F {
      containsVS16 = true
    }
    if isWideScalar(scalar) {
      containsWide = true
    }
    if !isZeroWidthScalar(scalar) {
      allZeroWidth = false
    }
  }

  if containsEmojiPresentation || (scalarCount > 1 && containsEmoji) {
    return 2
  }
  if containsVS16 && containsEmoji {
    return 2
  }
  if containsWide {
    return 2
  }
  if allZeroWidth {
    return 0
  }

  return 1
}

private func isZeroWidthScalar(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.properties.generalCategory {
  case .nonspacingMark, .enclosingMark, .format:
    return true
  default:
    return false
  }
}

private func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.value {
  case 0x1100...0x115F,
    0x2329...0x232A,
    0x2E80...0xA4CF,
    0xAC00...0xD7A3,
    0xF900...0xFAFF,
    0xFE10...0xFE19,
    0xFE30...0xFE6F,
    0xFF00...0xFF60,
    0xFFE0...0xFFE6,
    0x1F300...0x1FAFF,
    0x20000...0x3FFFD:
    return true
  default:
    return false
  }
}
