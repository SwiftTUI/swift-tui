public enum TerminalControlMessage: Equatable, Sendable {
  case resize(Size)
  case style(TerminalRenderStyle)
}

package struct ControlMessageParser {
  private static let introducer: UInt8 = 0x1E
  private var bufferedCommand: [UInt8]? = nil

  package init() {}

  package mutating func feed(
    _ bytes: [UInt8]
  ) -> (payload: [UInt8], messages: [TerminalControlMessage]) {
    var payload: [UInt8] = []
    payload.reserveCapacity(bytes.count)
    var messages: [TerminalControlMessage] = []

    for byte in bytes {
      if bufferedCommand != nil {
        if byte == 0x0A {
          if let message = parseBufferedCommand() {
            messages.append(message)
          }
          bufferedCommand = nil
        } else {
          bufferedCommand?.append(byte)
        }
        continue
      }

      if byte == Self.introducer {
        bufferedCommand = []
        continue
      }

      payload.append(byte)
    }

    return (payload, messages)
  }

  private func parseBufferedCommand() -> TerminalControlMessage? {
    guard let bufferedCommand else {
      return nil
    }

    let text = String(decoding: bufferedCommand, as: UTF8.self)
    if let message = parseResizeCommand(text) {
      return message
    }

    if let message = parseStyleCommand(text) {
      return message
    }

    return nil
  }

  private func parseResizeCommand(
    _ text: String
  ) -> TerminalControlMessage? {
    let components = text.split(separator: ":")
    guard components.count == 3, components[0] == "resize",
      let width = Int(components[1]),
      let height = Int(components[2])
    else {
      return nil
    }

    return .resize(
      .init(
        width: max(1, width),
        height: max(1, height)
      )
    )
  }

  private func parseStyleCommand(
    _ text: String
  ) -> TerminalControlMessage? {
    let prefix = "style:"
    guard text.hasPrefix(prefix) else {
      return nil
    }

    let encoded = String(text.dropFirst(prefix.count))
    guard let style = TerminalRenderStyleCodec.decodeBase64(encoded) else {
      return nil
    }
    return .style(style)
  }
}

package enum TerminalRenderStyleCodec {
  // Keep this transport schema aligned with GUI/WebTUIGUI/src/WebTUITerminalStyle.ts.
  package static func decodeBase64(
    _ encoded: String
  ) -> TerminalRenderStyle? {
    guard let bytes = StyleTransportBase64.decode(encoded) else {
      return nil
    }

    let json = String(decoding: bytes, as: UTF8.self)
    var parser = StyleTransportJSONParser(json)
    guard let value = parser.parse() else {
      return nil
    }

    return decodeStyle(from: value)
  }

  package static func encodeBase64(
    _ style: TerminalRenderStyle
  ) -> String? {
    let json = encodeStyle(style)
    return StyleTransportBase64.encode(Array(json.utf8))
  }

  private static func decodeStyle(
    from value: StyleTransportJSONValue
  ) -> TerminalRenderStyle? {
    guard
      let object = value.objectValue,
      let appearanceObject = object["appearance"]?.objectValue
    else {
      return nil
    }

    guard let appearance = decodeAppearance(from: appearanceObject) else {
      return nil
    }

    let theme: ThemeColors?
    switch object["theme"] {
    case nil, .some(.null):
      theme = nil
    case .some(let value):
      guard let themeObject = value.objectValue else {
        return nil
      }
      guard let decodedTheme = decodeTheme(from: themeObject) else {
        return nil
      }
      theme = decodedTheme
    }

    return .init(
      appearance: appearance,
      theme: theme
    )
  }

  private static func decodeAppearance(
    from object: [String: StyleTransportJSONValue]
  ) -> TerminalAppearance? {
    guard
      let foregroundColor = decodeColor(named: "foregroundColor", from: object),
      let backgroundColor = decodeColor(named: "backgroundColor", from: object),
      let tintColor = decodeColor(named: "tintColor", from: object),
      let colorScheme = decodeEnum(
        named: "colorScheme",
        from: object,
        as: ColorScheme.self
      ),
      let colorSchemeContrast = decodeEnum(
        named: "colorSchemeContrast",
        from: object,
        as: ColorSchemeContrast.self
      ),
      let source = decodeEnum(
        named: "source",
        from: object,
        as: AppearanceSource.self
      )
    else {
      return nil
    }

    let palette: [Int: Color]
    switch object["palette"] {
    case nil, .some(.null):
      palette = [:]
    case .some(let value):
      guard let paletteObject = value.objectValue else {
        return nil
      }
      var decodedPalette: [Int: Color] = [:]
      decodedPalette.reserveCapacity(paletteObject.count)
      for (key, colorValue) in paletteObject {
        guard
          let index = Int(key),
          let hex = colorValue.stringValue,
          let color = try? Color(hex: hex)
        else {
          return nil
        }
        decodedPalette[index] = color
      }
      palette = decodedPalette
    }

    return .init(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      tintColor: tintColor,
      palette: palette,
      colorScheme: colorScheme,
      colorSchemeContrast: colorSchemeContrast,
      source: source
    )
  }

  private static func decodeTheme(
    from object: [String: StyleTransportJSONValue]
  ) -> ThemeColors? {
    guard
      let foreground = decodeColor(named: "foreground", from: object),
      let background = decodeColor(named: "background", from: object),
      let tint = decodeColor(named: "tint", from: object),
      let separator = decodeColor(named: "separator", from: object),
      let selection = decodeColor(named: "selection", from: object),
      let placeholder = decodeColor(named: "placeholder", from: object),
      let link = decodeColor(named: "link", from: object),
      let fill = decodeColor(named: "fill", from: object),
      let windowBackground = decodeColor(named: "windowBackground", from: object),
      let success = decodeColor(named: "success", from: object),
      let warning = decodeColor(named: "warning", from: object),
      let danger = decodeColor(named: "danger", from: object),
      let info = decodeColor(named: "info", from: object),
      let muted = decodeColor(named: "muted", from: object)
    else {
      return nil
    }

    return .init(
      foreground: foreground,
      background: background,
      tint: tint,
      separator: separator,
      selection: selection,
      placeholder: placeholder,
      link: link,
      fill: fill,
      windowBackground: windowBackground,
      success: success,
      warning: warning,
      danger: danger,
      info: info,
      muted: muted
    )
  }

  private static func decodeColor(
    named key: String,
    from object: [String: StyleTransportJSONValue]
  ) -> Color? {
    guard let hex = object[key]?.stringValue else {
      return nil
    }
    return try? Color(hex: hex)
  }

  private static func decodeEnum<Value: RawRepresentable>(
    named key: String,
    from object: [String: StyleTransportJSONValue],
    as _: Value.Type
  ) -> Value? where Value.RawValue == String {
    guard let rawValue = object[key]?.stringValue else {
      return nil
    }
    return Value(rawValue: rawValue)
  }

  private static func encodeStyle(
    _ style: TerminalRenderStyle
  ) -> String {
    var fields = ["\"appearance\":\(encodeAppearance(style.appearance))"]
    if let theme = style.theme {
      fields.append("\"theme\":\(encodeTheme(theme))")
    }
    return "{\(fields.joined(separator: ","))}"
  }

  private static func encodeAppearance(
    _ appearance: TerminalAppearance
  ) -> String {
    let paletteEntries = appearance.palette
      .sorted { lhs, rhs in
        lhs.key < rhs.key
      }
      .map { key, color in
        "\(styleTransportJSONStringLiteral(String(key))):\(encodeColor(color))"
      }

    let fields = [
      "\"foregroundColor\":\(encodeColor(appearance.foregroundColor))",
      "\"backgroundColor\":\(encodeColor(appearance.backgroundColor))",
      "\"tintColor\":\(encodeColor(appearance.tintColor))",
      "\"palette\":{\(paletteEntries.joined(separator: ","))}",
      "\"colorScheme\":\(styleTransportJSONStringLiteral(appearance.colorScheme.rawValue))",
      "\"colorSchemeContrast\":\(styleTransportJSONStringLiteral(appearance.colorSchemeContrast.rawValue))",
      "\"source\":\(styleTransportJSONStringLiteral(appearance.source.rawValue))",
    ]

    return "{\(fields.joined(separator: ","))}"
  }

  private static func encodeTheme(
    _ theme: ThemeColors
  ) -> String {
    let fields = [
      "\"foreground\":\(encodeColor(theme.foreground))",
      "\"background\":\(encodeColor(theme.background))",
      "\"tint\":\(encodeColor(theme.tint))",
      "\"separator\":\(encodeColor(theme.separator))",
      "\"selection\":\(encodeColor(theme.selection))",
      "\"placeholder\":\(encodeColor(theme.placeholder))",
      "\"link\":\(encodeColor(theme.link))",
      "\"fill\":\(encodeColor(theme.fill))",
      "\"windowBackground\":\(encodeColor(theme.windowBackground))",
      "\"success\":\(encodeColor(theme.success))",
      "\"warning\":\(encodeColor(theme.warning))",
      "\"danger\":\(encodeColor(theme.danger))",
      "\"info\":\(encodeColor(theme.info))",
      "\"muted\":\(encodeColor(theme.muted))",
    ]

    return "{\(fields.joined(separator: ","))}"
  }

  private static func encodeColor(
    _ color: Color
  ) -> String {
    styleTransportJSONStringLiteral(
      color.hexString(letterCase: .lowercase)
    )
  }
}

private enum StyleTransportJSONValue {
  case object([String: Self])
  case string(String)
  case null
}

extension StyleTransportJSONValue {
  fileprivate var objectValue: [String: Self]? {
    guard case .object(let value) = self else {
      return nil
    }
    return value
  }

  fileprivate var stringValue: String? {
    guard case .string(let value) = self else {
      return nil
    }
    return value
  }
}

private struct StyleTransportJSONParser {
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

private enum StyleTransportBase64 {
  private static let alphabet = Array(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
  )

  static func encode(
    _ bytes: [UInt8]
  ) -> String {
    guard !bytes.isEmpty else {
      return ""
    }

    var result: [UInt8] = []
    result.reserveCapacity(((bytes.count + 2) / 3) * 4)

    var index = 0
    while index < bytes.count {
      let first = Int(bytes[index])
      let second = index + 1 < bytes.count ? Int(bytes[index + 1]) : 0
      let third = index + 2 < bytes.count ? Int(bytes[index + 2]) : 0
      let combined = (first << 16) | (second << 8) | third

      result.append(alphabet[(combined >> 18) & 0x3F])
      result.append(alphabet[(combined >> 12) & 0x3F])
      if index + 1 < bytes.count {
        result.append(alphabet[(combined >> 6) & 0x3F])
      } else {
        result.append(UInt8(ascii: "="))
      }
      if index + 2 < bytes.count {
        result.append(alphabet[combined & 0x3F])
      } else {
        result.append(UInt8(ascii: "="))
      }

      index += 3
    }

    return String(decoding: result, as: UTF8.self)
  }

  static func decode(
    _ encoded: String
  ) -> [UInt8]? {
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

      let paddingCount: Int =
        (third.value == 0x3D ? 1 : 0)
        + (fourth.value == 0x3D ? 1 : 0)

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

private func styleTransportJSONStringLiteral(
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

private func base64Value(
  _ scalar: Unicode.Scalar
) -> UInt8? {
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
