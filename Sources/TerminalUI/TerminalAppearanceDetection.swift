import Core

enum TerminalAppearanceQuery {
  case foreground
  case background
  case palette(index: Int)

  var request: String {
    switch self {
    case .foreground:
      return "\u{001B}]10;?\u{0007}"
    case .background:
      return "\u{001B}]11;?\u{0007}"
    case .palette(let index):
      return "\u{001B}]4;\(index);?\u{0007}"
    }
  }

  private var responsePrefix: String {
    switch self {
    case .foreground:
      return "\u{001B}]10;"
    case .background:
      return "\u{001B}]11;"
    case .palette(let index):
      return "\u{001B}]4;\(index);"
    }
  }

  func extractResponse(
    from bytes: [UInt8]
  ) -> String? {
    guard let response = strictUTF8String(from: bytes),
      let range = response.firstLiteralRange(of: responsePrefix)
    else {
      return nil
    }

    let suffix = response[range.upperBound...]
    if let bellIndex = suffix.firstIndex(of: "\u{0007}") {
      return String(suffix[..<bellIndex])
    }

    let suffixText = String(suffix)
    if let stRange = suffixText.firstLiteralRange(of: "\u{001B}\\") {
      return String(suffixText[..<stRange.lowerBound])
    }

    return nil
  }

  func parseColor(
    from response: String
  ) -> Color? {
    let trimmed = response.trimmedUnicodeWhitespace()
    if let rgbIndex = trimmed.firstLiteralRange(of: "rgb:") {
      return parseRGBSpec(String(trimmed[rgbIndex.upperBound...]))
    }

    return parseHexSpec(trimmed)
  }
}

extension TerminalAppearance {
  static func detect(
    environment: [String: String],
    capabilityProfile: TerminalCapabilityProfile,
    queryColor: ((TerminalAppearanceQuery) throws -> Color?)? = nil
  ) -> Self {
    let heuristic = heuristicAppearance(
      environment: environment,
      capabilityProfile: capabilityProfile
    )

    guard let queryColor else {
      return heuristic
    }

    do {
      let foreground = try queryColor(.foreground) ?? heuristic.foregroundColor
      let background = try queryColor(.background) ?? heuristic.backgroundColor
      var palette = heuristic.palette

      for index in [1, 2, 3, 4, 6, 8] {
        if let color = try queryColor(.palette(index: index)) {
          palette[index] = color
        }
      }

      let tint = palette[4] ?? palette[6] ?? heuristic.tintColor
      return .init(
        foregroundColor: foreground,
        backgroundColor: background,
        tintColor: tint,
        palette: palette,
        source: .activeQuery
      )
    } catch {
      return heuristic
    }
  }

  private static func heuristicAppearance(
    environment: [String: String],
    capabilityProfile _: TerminalCapabilityProfile
  ) -> Self {
    let palette = defaultPalette

    if let colorFGBG = environment["COLORFGBG"] {
      let values =
        colorFGBG
        .split(whereSeparator: { $0 == ";" || $0 == ":" })
        .compactMap { Int($0) }

      if values.count >= 2 {
        let foregroundIndex = values[values.count - 2]
        let backgroundIndex = values[values.count - 1]
        let foreground = palette[foregroundIndex] ?? fallback.foregroundColor
        let background = palette[backgroundIndex] ?? fallback.backgroundColor
        return .init(
          foregroundColor: foreground,
          backgroundColor: background,
          tintColor: palette[4] ?? fallback.tintColor,
          palette: palette,
          source: .environmentHeuristics
        )
      }
    }

    return .init(
      foregroundColor: fallback.foregroundColor,
      backgroundColor: fallback.backgroundColor,
      tintColor: palette[4] ?? fallback.tintColor,
      palette: palette,
      source: .fallback
    )
  }
}

private func parseRGBSpec(
  _ spec: String
) -> Color? {
  let components = spec.split(separator: "/")
  guard components.count == 3 else {
    return nil
  }

  let values = components.compactMap(parseHexComponent)
  guard values.count == 3 else {
    return nil
  }

  return .init(red: values[0], green: values[1], blue: values[2])
}

private func parseHexSpec(
  _ spec: String
) -> Color? {
  let normalized = spec.hasPrefix("#") ? String(spec.dropFirst()) : spec
  guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
    return nil
  }

  return .init(
    red: (value >> 16) & 0xFF,
    green: (value >> 8) & 0xFF,
    blue: value & 0xFF
  )
}

private func parseHexComponent(
  _ raw: Substring
) -> Int? {
  let text = String(raw)
  guard let value = Int(text, radix: 16) else {
    return nil
  }

  let maxValue = Int(powDouble(16, Double(text.count))) - 1
  guard maxValue > 0 else {
    return nil
  }

  return Int((Double(value) / Double(maxValue) * 255).rounded())
}

private func strictUTF8String(
  from bytes: [UInt8]
) -> String? {
  let decoded = String(decoding: bytes, as: UTF8.self)
  return Array(decoded.utf8) == bytes ? decoded : nil
}
