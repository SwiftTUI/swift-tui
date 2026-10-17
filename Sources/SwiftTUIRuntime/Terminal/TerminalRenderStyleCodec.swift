@_spi(Runners) public enum TerminalRenderStyleCodec {
  // Keep this transport schema aligned with swift-tui-web/packages/web/src/WebHostTerminalStyle.ts.
  @_spi(Runners) public static func decodeBase64(
    _ encoded: String
  ) -> TerminalRenderStyle? {
    guard let bytes = StyleTransportBase64.decode(encoded) else {
      return nil
    }

    guard let json = String(validating: bytes, as: UTF8.self) else { return nil }
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

    let reduceMotion: Bool?
    switch object["reduceMotion"] {
    case nil, .some(.null): reduceMotion = nil
    case .some(.string("true")): reduceMotion = true
    case .some(.string("false")): reduceMotion = false
    default: return nil
    }
    let differentiateWithoutColor: Bool?
    switch object["differentiateWithoutColor"] {
    case nil, .some(.null): differentiateWithoutColor = nil
    case .some(.string("true")): differentiateWithoutColor = true
    case .some(.string("false")): differentiateWithoutColor = false
    default: return nil
    }
    let reduceTransparency: Bool?
    switch object["reduceTransparency"] {
    case nil, .some(.null): reduceTransparency = nil
    case .some(.string("true")): reduceTransparency = true
    case .some(.string("false")): reduceTransparency = false
    default: return nil
    }
    let contrast: ColorSchemeContrast?
    switch object["contrast"] {
    case nil, .some(.null): contrast = nil
    case .some(.string(let raw)):
      guard let parsed = ColorSchemeContrast(rawValue: raw) else { return nil }
      contrast = parsed
    default: return nil
    }
    let colorProfile: AccessibilityColorProfile?
    switch object["colorProfile"] {
    case nil, .some(.null): colorProfile = nil
    case .some(.string(let raw)):
      guard let parsed = AccessibilityColorProfile(rawValue: raw) else { return nil }
      colorProfile = parsed
    default: return nil
    }
    return .init(
      appearance: appearance, theme: theme,
      accessibilityPreferences: .init(
        reduceMotion: reduceMotion, contrast: contrast,
        differentiateWithoutColor: differentiateWithoutColor,
        reduceTransparency: reduceTransparency, colorProfile: colorProfile))
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

    guard let alphas = decodeAlphas(object["paletteAlpha"]) else { return nil }
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
        decodedPalette[index] = alphas[key].map { color.withAlpha($0) } ?? color
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
    guard let hex = object[key]?.stringValue, let color = try? Color(hex: hex),
      let alphas = decodeAlphas(object["alpha"])
    else { return nil }
    return alphas[key].map { color.withAlpha($0) } ?? color
  }

  /// Additive string-valued metadata preserves full alpha precision while old
  /// peers continue reading the established RGB hex color fields.
  private static func decodeAlphas(_ value: StyleTransportJSONValue?) -> [String: Double]? {
    guard let value else { return [:] }
    guard let object = value.objectValue else { return nil }
    var result: [String: Double] = [:]
    for (key, value) in object {
      guard let text = value.stringValue, let alpha = Double(text), alpha.isFinite,
        (0...1).contains(alpha)
      else { return nil }
      result[key] = alpha
    }
    return result
  }

  private static func alphaField(_ colors: [(String, Color)], named name: String = "alpha")
    -> String?
  {
    let fields = colors.compactMap { key, color -> String? in
      guard color.alpha != 1 else { return nil }
      return
        "\(styleTransportJSONStringLiteral(key)):\(styleTransportJSONStringLiteral(String(color.alpha)))"
    }
    guard !fields.isEmpty else { return nil }
    return "\(styleTransportJSONStringLiteral(name)):{\(fields.joined(separator: ","))}"
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
    if let reduceMotion = style.reduceMotion {
      // String tokens keep older style parsers usable: they understand only
      // objects, strings and null, and ignore unknown string-valued fields.
      fields.append("\"reduceMotion\":\"\(reduceMotion ? "true" : "false")\"")
    }
    let preferences: [(String, String?)] = [
      ("contrast", style.contrast?.rawValue),
      ("differentiateWithoutColor", style.differentiateWithoutColor.map { $0 ? "true" : "false" }),
      ("reduceTransparency", style.reduceTransparency.map { $0 ? "true" : "false" }),
      ("colorProfile", style.colorProfile?.rawValue),
    ]
    for (key, value) in preferences {
      if let value {
        fields.append(
          "\(styleTransportJSONStringLiteral(key)):\(styleTransportJSONStringLiteral(value))")
      }
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

    var fields = [
      "\"foregroundColor\":\(encodeColor(appearance.foregroundColor))",
      "\"backgroundColor\":\(encodeColor(appearance.backgroundColor))",
      "\"tintColor\":\(encodeColor(appearance.tintColor))",
      "\"palette\":{\(paletteEntries.joined(separator: ","))}",
      "\"colorSchemeContrast\":\(styleTransportJSONStringLiteral(appearance.colorSchemeContrast.rawValue))",
      "\"source\":\(styleTransportJSONStringLiteral(appearance.source.rawValue))",
    ]

    if let alpha = alphaField([
      ("foregroundColor", appearance.foregroundColor),
      ("backgroundColor", appearance.backgroundColor),
      ("tintColor", appearance.tintColor),
    ]) {
      fields.append(alpha)
    }
    if let alpha = alphaField(
      appearance.palette.indexedColors.sorted { $0.key < $1.key }.map {
        (String($0.key), $0.value)
      },
      named: "paletteAlpha"
    ) {
      fields.append(alpha)
    }
    return "{\(fields.joined(separator: ","))}"
  }

  private static func encodeTheme(_ theme: Theme) -> String {
    let colors: [(String, Color)] = [
      ("foreground", theme.foreground),
      ("background", theme.background),
      ("tint", theme.tint),
      ("separator", theme.separator),
      ("selection", theme.selection),
      ("placeholder", theme.placeholder),
      ("link", theme.link),
      ("fill", theme.fill),
      ("windowBackground", theme.windowBackground),
      ("success", theme.success),
      ("warning", theme.warning),
      ("danger", theme.danger),
      ("info", theme.info),
      ("muted", theme.muted),
    ]
    var fields = colors.map { key, color in
      "\(styleTransportJSONStringLiteral(key)):\(encodeColor(color))"
    }
    if let alpha = alphaField(colors) { fields.append(alpha) }
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
