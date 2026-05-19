enum StyleTransportJSONValue {
  case object([String: Self])
  case string(String)
  case null
}

extension StyleTransportJSONValue {
  var objectValue: [String: Self]? {
    guard case .object(let value) = self else {
      return nil
    }
    return value
  }

  var stringValue: String? {
    guard case .string(let value) = self else {
      return nil
    }
    return value
  }
}

struct StyleTransportJSONParser {
  private let scalars: [Unicode.Scalar]
  private var index = 0

  init(
    _ json: String
  ) {
    scalars = Array(json.unicodeScalars)
  }

  mutating func parse() -> StyleTransportJSONValue? {
    skipWhitespace()
    guard let value = parseValue() else {
      return nil
    }
    skipWhitespace()
    guard isAtEnd else {
      return nil
    }
    return value
  }

  private var isAtEnd: Bool {
    index >= scalars.count
  }

  private mutating func skipWhitespace() {
    while index < scalars.count, isStyleTransportWhitespace(scalars[index]) {
      index += 1
    }
  }

  private mutating func parseValue() -> StyleTransportJSONValue? {
    guard index < scalars.count else {
      return nil
    }

    switch scalars[index].value {
    case 0x7B:
      return parseObject()
    case 0x22:
      guard let string = parseString() else {
        return nil
      }
      return .string(string)
    case 0x6E:
      guard parseNull() else {
        return nil
      }
      return .null
    default:
      return nil
    }
  }

  private mutating func parseObject() -> StyleTransportJSONValue? {
    guard consume(0x7B) else {
      return nil
    }

    skipWhitespace()
    if consume(0x7D) {
      return .object([:])
    }

    var object: [String: StyleTransportJSONValue] = [:]
    while true {
      skipWhitespace()
      guard let key = parseString() else {
        return nil
      }

      skipWhitespace()
      guard consume(0x3A) else {
        return nil
      }

      skipWhitespace()
      guard let value = parseValue() else {
        return nil
      }
      object[key] = value

      skipWhitespace()
      if consume(0x7D) {
        return .object(object)
      }

      guard consume(0x2C) else {
        return nil
      }
    }
  }

  private mutating func parseString() -> String? {
    guard consume(0x22) else {
      return nil
    }

    var result = String.UnicodeScalarView()
    while index < scalars.count {
      let scalar = scalars[index]
      index += 1

      switch scalar.value {
      case 0x22:
        return String(result)
      case 0x5C:
        guard let escaped = parseEscapeSequence() else {
          return nil
        }
        result.append(contentsOf: escaped.unicodeScalars)
      default:
        guard scalar.value >= 0x20 else {
          return nil
        }
        result.append(scalar)
      }
    }

    return nil
  }

  private mutating func parseEscapeSequence() -> String? {
    guard index < scalars.count else {
      return nil
    }

    let escape = scalars[index]
    index += 1

    switch escape.value {
    case 0x22:
      return "\""
    case 0x5C:
      return "\\"
    case 0x2F:
      return "/"
    case 0x62:
      return "\u{08}"
    case 0x66:
      return "\u{0C}"
    case 0x6E:
      return "\n"
    case 0x72:
      return "\r"
    case 0x74:
      return "\t"
    case 0x75:
      return parseUnicodeEscape()
    default:
      return nil
    }
  }

  private mutating func parseUnicodeEscape() -> String? {
    guard let firstCodeUnit = parseHexQuad() else {
      return nil
    }

    if (0xD800...0xDBFF).contains(firstCodeUnit) {
      guard consume(0x5C), consume(0x75),
        let secondCodeUnit = parseHexQuad(),
        (0xDC00...0xDFFF).contains(secondCodeUnit)
      else {
        return nil
      }

      let high = firstCodeUnit - 0xD800
      let low = secondCodeUnit - 0xDC00
      let scalarValue = 0x10000 + ((high << 10) | low)
      guard let scalar = Unicode.Scalar(scalarValue) else {
        return nil
      }
      return String(scalar)
    }

    guard !(0xDC00...0xDFFF).contains(firstCodeUnit),
      let scalar = Unicode.Scalar(firstCodeUnit)
    else {
      return nil
    }
    return String(scalar)
  }

  private mutating func parseHexQuad() -> UInt32? {
    guard index + 4 <= scalars.count else {
      return nil
    }

    var value: UInt32 = 0
    for _ in 0..<4 {
      guard let digit = hexDigitValue(scalars[index]) else {
        return nil
      }
      value = (value << 4) | digit
      index += 1
    }
    return value
  }

  private mutating func parseNull() -> Bool {
    consumeSequence([0x6E, 0x75, 0x6C, 0x6C])
  }

  private mutating func consume(
    _ value: UInt32
  ) -> Bool {
    guard index < scalars.count, scalars[index].value == value else {
      return false
    }
    index += 1
    return true
  }

  private mutating func consumeSequence(
    _ values: [UInt32]
  ) -> Bool {
    let originalIndex = index
    for value in values where !consume(value) {
      index = originalIndex
      return false
    }
    return true
  }
}

func styleTransportJSONStringLiteral(
  _ string: String
) -> String {
  var result = "\""

  for scalar in string.unicodeScalars {
    switch scalar.value {
    case 0x22:
      result += "\\\""
    case 0x5C:
      result += "\\\\"
    case 0x08:
      result += "\\b"
    case 0x0C:
      result += "\\f"
    case 0x0A:
      result += "\\n"
    case 0x0D:
      result += "\\r"
    case 0x09:
      result += "\\t"
    case 0x00..<0x20:
      let hex = String(scalar.value, radix: 16, uppercase: true)
      result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
    default:
      result.unicodeScalars.append(scalar)
    }
  }

  result += "\""
  return result
}

private func isStyleTransportWhitespace(
  _ scalar: Unicode.Scalar
) -> Bool {
  switch scalar.value {
  case 0x09, 0x0A, 0x0D, 0x20:
    true
  default:
    false
  }
}

private func hexDigitValue(
  _ scalar: Unicode.Scalar
) -> UInt32? {
  switch scalar.value {
  case 0x30...0x39:
    scalar.value - 0x30
  case 0x41...0x46:
    scalar.value - 0x41 + 10
  case 0x61...0x66:
    scalar.value - 0x61 + 10
  default:
    nil
  }
}
