public import SwiftTUIVendorFiglet

enum EmbeddedFontStorage {
  static func decode(_ encodedFontData: String, fontName: String) -> [UInt8] {
    guard let bytes = base64Decode(encodedFontData) else {
      preconditionFailure("Embedded font data for \(fontName) is not valid base64")
    }

    return bytes
  }

  /// Foundation-free RFC 4648 base64 decoder. EmbeddedFonts is re-exported into
  /// the Foundation-free library layers (SwiftTUICore / SwiftTUIViews), so it
  /// must not reach for `Foundation.Data(base64Encoded:)`. Returns `nil` for any
  /// input that is not well-formed standard base64.
  static func base64Decode(_ encoded: String) -> [UInt8]? {
    let scalars = Array(encoded.unicodeScalars)
    guard scalars.count.isMultiple(of: 4) else {
      return nil
    }

    var result: [UInt8] = []
    result.reserveCapacity((scalars.count / 4) * 3)

    var index = 0
    while index < scalars.count {
      let first = scalars[index]
      let second = scalars[index + 1]
      let third = scalars[index + 2]
      let fourth = scalars[index + 3]
      let isFinalChunk = index + 4 == scalars.count

      guard first.value != 0x3D, second.value != 0x3D else {
        return nil
      }

      let paddingCount = (third.value == 0x3D ? 1 : 0) + (fourth.value == 0x3D ? 1 : 0)
      if third.value == 0x3D, fourth.value != 0x3D {
        return nil
      }
      if paddingCount > 0, !isFinalChunk {
        return nil
      }

      guard
        let firstValue = base64Value(first),
        let secondValue = base64Value(second)
      else {
        return nil
      }

      let thirdValue: UInt8
      if third.value == 0x3D {
        thirdValue = 0
      } else if let value = base64Value(third) {
        thirdValue = value
      } else {
        return nil
      }

      let fourthValue: UInt8
      if fourth.value == 0x3D {
        fourthValue = 0
      } else if let value = base64Value(fourth) {
        fourthValue = value
      } else {
        return nil
      }

      let combined =
        (UInt32(firstValue) << 18)
        | (UInt32(secondValue) << 12)
        | (UInt32(thirdValue) << 6)
        | UInt32(fourthValue)

      result.append(UInt8((combined >> 16) & 0xFF))
      if third.value != 0x3D {
        result.append(UInt8((combined >> 8) & 0xFF))
      }
      if fourth.value != 0x3D {
        result.append(UInt8(combined & 0xFF))
      }

      index += 4
    }

    return result
  }
}

extension Figlet {
  public init(
    embeddedFont font: EmbeddedFigletFont = .standard,
    configuration: FigletConfiguration = FigletConfiguration()
  ) throws {
    try self.init(
      fontNamed: font.rawValue,
      configuration: configuration,
      fontLibrary: EmbeddedFigletFont.library
    )
  }
}

private func base64Value(_ scalar: Unicode.Scalar) -> UInt8? {
  switch scalar.value {
  case 0x41...0x5A:
    UInt8(scalar.value - 0x41)
  case 0x61...0x7A:
    UInt8(scalar.value - 0x61 + 26)
  case 0x30...0x39:
    UInt8(scalar.value - 0x30 + 52)
  case 0x2B:
    62
  case 0x2F:
    63
  default:
    nil
  }
}
