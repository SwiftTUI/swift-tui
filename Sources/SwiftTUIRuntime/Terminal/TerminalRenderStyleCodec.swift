@_spi(Runners) public enum TerminalRenderStyleCodec {
  // Keep this transport schema aligned with Platforms/Web/src/WebHostTerminalStyle.ts.
  @_spi(Runners) public static func decodeBase64(
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

  @_spi(Runners) public static func encodeBase64(
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

    let theme: Theme?
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

    let palette: TerminalPalette
    switch object["palette"] {
    case nil, .some(.null):
      palette = .default
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
      palette = .init(indexedColors: decodedPalette)
    }

    return .init(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      tintColor: tintColor,
      palette: palette,
      colorSchemeContrast: colorSchemeContrast,
      source: source
    )
  }

  private static func decodeTheme(
    from object: [String: StyleTransportJSONValue]
  ) -> Theme? {
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
      .indexedColors
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
      "\"colorSchemeContrast\":\(styleTransportJSONStringLiteral(appearance.colorSchemeContrast.rawValue))",
      "\"source\":\(styleTransportJSONStringLiteral(appearance.source.rawValue))",
    ]

    return "{\(fields.joined(separator: ","))}"
  }

  private static func encodeTheme(
    _ theme: Theme
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
