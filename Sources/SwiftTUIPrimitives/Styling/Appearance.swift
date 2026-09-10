import Synchronization

/// Single-slot memo for ``TerminalAppearance/synthesizedTheme()``. The
/// derivation is pure but expensive (~13 theme entries behind contrast-safety
/// searches), and resolve re-runs it every time a style-key environment edit
/// re-mints `StyleEnvironmentSnapshot` — dozens of times per frame with an
/// identical appearance. One slot suffices: a session presents one live
/// appearance at a time (light/dark flips replace it wholesale), and bounded
/// storage cannot grow under palette-animating hosts.
private let synthesizedThemeMemo = Mutex<(appearance: TerminalAppearance, theme: Theme)?>(nil)

/// The effective contrast level of the terminal appearance.
public enum ColorSchemeContrast: String, Equatable, Sendable, Codable {
  case standard
  case increased
}

/// How a terminal appearance value was determined.
public enum AppearanceSource: String, Equatable, Sendable, Codable {
  case activeQuery
  case environmentHeuristics
  case fallback
  case override
}

/// A semantic prominence hint for emphasized controls.
public enum ControlProminence: Hashable, Sendable {
  /// The ordinary emphasis level: neutral surfaces and borders.
  case standard
  /// Raised emphasis: built-in chrome fills the control with the accent tone
  /// and picks a contrasting foreground.
  case increased
}

/// A semantic role for buttons and other acceptance or cancellation actions.
public enum ButtonRole: Hashable, Sendable {
  /// Backs out of the current step without applying it. Built-in chrome tones
  /// it neutral.
  case cancel
  /// Performs an action that discards or destroys data. Built-in chrome tones
  /// it with the theme's danger color.
  case destructive
  /// Dismisses the surface the button is in. Built-in chrome tones it
  /// neutral, like `cancel`.
  case close
  /// Accepts and applies the current step. Built-in chrome tones it with the
  /// theme accent, the same tone an unroled button gets.
  case confirm
}

/// The resolved chrome used to render a focused or interactive control.
public struct ControlChrome: Equatable, Sendable {
  /// The paint for the control's text and glyphs.
  public var foregroundStyle: AnyShapeStyle
  /// The paint filling the cells behind the control's content.
  public var contentBackgroundStyle: AnyShapeStyle
  /// The paint for the control's border glyphs.
  public var borderForegroundStyle: AnyShapeStyle
  /// The paint filling the cells the border occupies, or `nil` to leave them
  /// unfilled. `nil` in every chrome the built-in resolvers return.
  public var borderBackgroundStyle: BorderBackgroundStyle?
  /// The opacity to render the control at, from 0 to 1.
  ///
  /// `1` in every state except disabled, where the built-in resolvers return
  /// `0.6`.
  public var opacity: Double

  /// Creates a control chrome value.
  ///
  /// - Parameters:
  ///   - foregroundStyle: The paint for text and glyphs.
  ///   - contentBackgroundStyle: The paint behind the content.
  ///   - borderForegroundStyle: The paint for border glyphs.
  ///   - borderBackgroundStyle: The paint behind the border cells, or `nil`.
  ///     Defaults to `nil`.
  ///   - opacity: The render opacity from 0 to 1. Defaults to `1`.
  public init(
    foregroundStyle: AnyShapeStyle,
    contentBackgroundStyle: AnyShapeStyle,
    borderForegroundStyle: AnyShapeStyle,
    borderBackgroundStyle: BorderBackgroundStyle? = nil,
    opacity: Double = 1
  ) {
    self.foregroundStyle = foregroundStyle
    self.contentBackgroundStyle = contentBackgroundStyle
    self.borderForegroundStyle = borderForegroundStyle
    self.borderBackgroundStyle = borderBackgroundStyle
    self.opacity = opacity
  }

  /// An alias for `contentBackgroundStyle`, for call sites that name the
  /// content fill simply the background.
  public var backgroundStyle: AnyShapeStyle {
    contentBackgroundStyle
  }

  /// An alias for `borderForegroundStyle`, for call sites that pass one paint
  /// to a border modifier.
  public var borderStyle: AnyShapeStyle {
    borderForegroundStyle
  }
}

/// The resolved chrome used to render a container such as a group box.
public struct ContainerChrome: Equatable, Sendable {
  /// The paint for the container's own text and glyphs, such as its label.
  public var foregroundStyle: AnyShapeStyle
  /// The paint for the container's border glyphs.
  public var borderStyle: AnyShapeStyle

  /// Creates a container chrome value.
  ///
  /// - Parameters:
  ///   - foregroundStyle: The paint for the container's text and glyphs.
  ///   - borderStyle: The paint for the container's border glyphs.
  public init(
    foregroundStyle: AnyShapeStyle,
    borderStyle: AnyShapeStyle
  ) {
    self.foregroundStyle = foregroundStyle
    self.borderStyle = borderStyle
  }
}

/// The resolved visual appearance of the current terminal session.
public struct TerminalPalette:
  Equatable, Sendable, Codable, ExpressibleByDictionaryLiteral
{
  public var black: Color
  public var red: Color
  public var green: Color
  public var yellow: Color
  public var blue: Color
  public var magenta: Color
  public var cyan: Color
  public var white: Color
  public var brightBlack: Color
  public var brightRed: Color
  public var brightGreen: Color
  public var brightYellow: Color
  public var brightBlue: Color
  public var brightMagenta: Color
  public var brightCyan: Color
  public var brightWhite: Color

  public init(
    black: Color,
    red: Color,
    green: Color,
    yellow: Color,
    blue: Color,
    magenta: Color,
    cyan: Color,
    white: Color,
    brightBlack: Color,
    brightRed: Color,
    brightGreen: Color,
    brightYellow: Color,
    brightBlue: Color,
    brightMagenta: Color,
    brightCyan: Color,
    brightWhite: Color
  ) {
    self.black = black
    self.red = red
    self.green = green
    self.yellow = yellow
    self.blue = blue
    self.magenta = magenta
    self.cyan = cyan
    self.white = white
    self.brightBlack = brightBlack
    self.brightRed = brightRed
    self.brightGreen = brightGreen
    self.brightYellow = brightYellow
    self.brightBlue = brightBlue
    self.brightMagenta = brightMagenta
    self.brightCyan = brightCyan
    self.brightWhite = brightWhite
  }

  public init(
    indexedColors: [Int: Color],
    defaults: Self = .default
  ) {
    self = defaults
    for (index, color) in indexedColors {
      self[index] = color
    }
  }

  public init(
    dictionaryLiteral elements: (Int, Color)...
  ) {
    self.init(indexedColors: Dictionary(uniqueKeysWithValues: elements))
  }

  public static let `default` = Self(
    black: try! .init(hex: "#20242C"),
    red: try! .init(hex: "#E05757"),
    green: try! .init(hex: "#61C67B"),
    yellow: try! .init(hex: "#EBB33C"),
    blue: try! .init(hex: "#5BA3FF"),
    magenta: try! .init(hex: "#B46EFF"),
    cyan: try! .init(hex: "#56B6C2"),
    white: try! .init(hex: "#ECEFF4"),
    brightBlack: try! .init(hex: "#8C92AC"),
    brightRed: try! .init(hex: "#FF7B72"),
    brightGreen: try! .init(hex: "#7EE787"),
    brightYellow: try! .init(hex: "#F2CC60"),
    brightBlue: try! .init(hex: "#79C0FF"),
    brightMagenta: try! .init(hex: "#D2A8FF"),
    brightCyan: try! .init(hex: "#7DE2D1"),
    brightWhite: .white
  )

  public subscript(index: Int) -> Color? {
    get {
      switch index {
      case 0:
        black
      case 1:
        red
      case 2:
        green
      case 3:
        yellow
      case 4:
        blue
      case 5:
        magenta
      case 6:
        cyan
      case 7:
        white
      case 8:
        brightBlack
      case 9:
        brightRed
      case 10:
        brightGreen
      case 11:
        brightYellow
      case 12:
        brightBlue
      case 13:
        brightMagenta
      case 14:
        brightCyan
      case 15:
        brightWhite
      default:
        nil
      }
    }
    set {
      guard let newValue else {
        return
      }

      switch index {
      case 0:
        black = newValue
      case 1:
        red = newValue
      case 2:
        green = newValue
      case 3:
        yellow = newValue
      case 4:
        blue = newValue
      case 5:
        magenta = newValue
      case 6:
        cyan = newValue
      case 7:
        white = newValue
      case 8:
        brightBlack = newValue
      case 9:
        brightRed = newValue
      case 10:
        brightGreen = newValue
      case 11:
        brightYellow = newValue
      case 12:
        brightBlue = newValue
      case 13:
        brightMagenta = newValue
      case 14:
        brightCyan = newValue
      case 15:
        brightWhite = newValue
      default:
        break
      }
    }
  }

  public var indexedColors: [Int: Color] {
    [
      0: black,
      1: red,
      2: green,
      3: yellow,
      4: blue,
      5: magenta,
      6: cyan,
      7: white,
      8: brightBlack,
      9: brightRed,
      10: brightGreen,
      11: brightYellow,
      12: brightBlue,
      13: brightMagenta,
      14: brightCyan,
      15: brightWhite,
    ]
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let encoded = try container.decode([String: String].self)
    var indexed: [Int: Color] = [:]
    indexed.reserveCapacity(encoded.count)
    for (key, hex) in encoded {
      guard let index = Int(key) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Palette keys must be integers."
        )
      }
      indexed[index] = try Color(hex: hex)
    }
    self.init(indexedColors: indexed)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(
      Dictionary(
        uniqueKeysWithValues: indexedColors.map { index, color in
          (String(index), color.hexString())
        }
      )
    )
  }
}

public struct TerminalAppearance: Equatable, Sendable, Codable {
  public var foregroundColor: Color
  public var backgroundColor: Color
  public var tintColor: Color
  public var palette: TerminalPalette
  public var colorSchemeContrast: ColorSchemeContrast
  public var source: AppearanceSource

  /// Creates a terminal appearance explicitly.
  public init(
    foregroundColor: Color,
    backgroundColor: Color,
    tintColor: Color,
    palette: TerminalPalette = TerminalAppearance.defaultPalette,
    colorSchemeContrast: ColorSchemeContrast? = nil,
    source: AppearanceSource = .fallback
  ) {
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
    self.tintColor = tintColor
    self.palette = palette
    self.colorSchemeContrast =
      colorSchemeContrast
      ?? TerminalAppearance.derivedColorSchemeContrast(
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor
      )
    self.source = source
  }

  public static let fallback = Self(
    foregroundColor: try! .init(hex: "#ECEFF4"),
    backgroundColor: try! .init(hex: "#1E222A"),
    tintColor: .cyan,
    source: .fallback
  )

  public static let defaultPalette = TerminalPalette.default

  /// Derives the semantic theme exposed to higher-level styling APIs.
  ///
  /// This function memoizes the theme by appearance value equality.
  /// The derivation is pure, so an unchanged appearance returns the last theme.
  /// This is the steady state.
  /// Style-key environment changes create new snapshots more often than the
  /// appearance itself changes.
  public func synthesizedTheme() -> Theme {
    if let cached = synthesizedThemeMemo.withLock({ $0 }), cached.appearance == self {
      return cached.theme
    }
    let theme = deriveSynthesizedTheme()
    synthesizedThemeMemo.withLock { $0 = (appearance: self, theme: theme) }
    return theme
  }

  private func deriveSynthesizedTheme() -> Theme {
    let separator = backgroundColor.mixed(with: foregroundColor, amount: separatorMixAmount)
    let fill = elevatedSurface(
      from: backgroundColor,
      amount: 0.08
    )
    let windowBackground = elevatedSurface(
      from: backgroundColor,
      amount: 0.04,
      invert: true
    )
    let muted = backgroundColor.mixed(with: foregroundColor, amount: mutedMixAmount)
    let placeholder = backgroundColor.mixed(with: foregroundColor, amount: placeholderMixAmount)
    let safeTint = contrastSafe(
      tintColor,
      against: backgroundColor,
      minimumContrast: 3,
      fallback: fallbackTint
    )
    let selection = contrastSafe(
      backgroundColor.mixed(with: safeTint, amount: selectionMixAmount),
      against: backgroundColor,
      minimumContrast: 1.35,
      fallback: elevatedSurface(from: backgroundColor, amount: 0.14)
    )

    return .init(
      foreground: foregroundColor,
      background: backgroundColor,
      tint: safeTint,
      separator: separator,
      selection: selection,
      placeholder: placeholder,
      link:
        contrastSafe(
          roleColor(for: 4, fallback: safeTint), against: backgroundColor, minimumContrast: 3,
          fallback: safeTint),
      fill: fill,
      windowBackground: windowBackground,
      success:
        contrastSafe(
          roleColor(for: 2, fallback: .green), against: backgroundColor, minimumContrast: 2.5,
          fallback: .green),
      warning:
        contrastSafe(
          roleColor(for: 3, fallback: .yellow), against: backgroundColor, minimumContrast: 2.5,
          fallback: .yellow),
      danger:
        contrastSafe(
          roleColor(for: 1, fallback: .red), against: backgroundColor, minimumContrast: 2.5,
          fallback: .red),
      info:
        contrastSafe(
          roleColor(for: 6, fallback: .cyan), against: backgroundColor, minimumContrast: 2.5,
          fallback: .cyan),
      muted: muted
    )
  }

  private enum CodingKeys: String, CodingKey {
    case foregroundColor
    case backgroundColor
    case tintColor
    case palette
    case colorSchemeContrast
    case source
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let foregroundHex = try container.decode(String.self, forKey: .foregroundColor)
    let backgroundHex = try container.decode(String.self, forKey: .backgroundColor)
    let tintHex = try container.decode(String.self, forKey: .tintColor)
    let palette = try container.decodeIfPresent(TerminalPalette.self, forKey: .palette) ?? .default

    self.init(
      foregroundColor: try Color(hex: foregroundHex),
      backgroundColor: try Color(hex: backgroundHex),
      tintColor: try Color(hex: tintHex),
      palette: palette,
      colorSchemeContrast: try container.decode(
        ColorSchemeContrast.self,
        forKey: .colorSchemeContrast
      ),
      source: try container.decode(AppearanceSource.self, forKey: .source)
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(foregroundColor.hexString(), forKey: .foregroundColor)
    try container.encode(backgroundColor.hexString(), forKey: .backgroundColor)
    try container.encode(tintColor.hexString(), forKey: .tintColor)
    try container.encode(
      palette,
      forKey: .palette
    )
    try container.encode(colorSchemeContrast, forKey: .colorSchemeContrast)
    try container.encode(source, forKey: .source)
  }
}

extension TerminalAppearance {
  public static func derivedColorSchemeContrast(
    foregroundColor: Color,
    backgroundColor: Color
  ) -> ColorSchemeContrast {
    foregroundColor.contrastRatio(to: backgroundColor) >= 7 ? .increased : .standard
  }
}

extension TerminalAppearance {
  private var backgroundDarkness: Double {
    min(1, max(0, 1 - backgroundColor.relativeLuminance))
  }

  private func interpolatedAmount(
    dark: Double,
    light: Double
  ) -> Double {
    light + ((dark - light) * backgroundDarkness)
  }

  private var separatorMixAmount: Double {
    interpolatedAmount(dark: 0.22, light: 0.28)
  }

  private var mutedMixAmount: Double {
    interpolatedAmount(dark: 0.52, light: 0.6)
  }

  private var placeholderMixAmount: Double {
    interpolatedAmount(dark: 0.36, light: 0.44)
  }

  private var selectionMixAmount: Double {
    interpolatedAmount(dark: 0.3, light: 0.2)
  }

  private var fallbackTint: Color {
    .blue.mixed(with: .cyan, amount: backgroundDarkness)
  }

  private func roleColor(
    for index: Int,
    fallback: Color
  ) -> Color {
    palette[index] ?? fallback
  }

  private func elevatedSurface(
    from base: Color,
    amount: Double,
    invert: Bool = false
  ) -> Color {
    let luminance = min(1, max(0, base.relativeLuminance))
    let lightenStrength = amount * (invert ? luminance : 1 - luminance)
    let darkenStrength = amount * (invert ? 1 - luminance : luminance)
    return
      base
      .mixed(with: .white, amount: lightenStrength)
      .mixed(with: .black, amount: darkenStrength)
  }

}

extension StyleEnvironmentSnapshot {
  /// Resolves a semantic role to a paint, honoring the ambient foreground and
  /// tint overrides carried by this snapshot.
  ///
  /// The built-in control chrome resolves its foreground through this method,
  /// so a third-party style that calls it matches built-in foreground
  /// resolution: an explicit `foregroundStyle(_:)` or `tint(_:)` in the
  /// environment wins for `.foreground` and `.tint`; every other role comes
  /// from the theme.
  public func resolvedStyle(
    for role: SemanticStyleRole
  ) -> AnyShapeStyle {
    switch role {
    case .foreground:
      foregroundStyle ?? theme.style(for: role)
    case .tint:
      tintStyle ?? theme.style(for: role)
    default:
      theme.style(for: role)
    }
  }

  package func themeStyle(
    for role: SemanticStyleRole
  ) -> AnyShapeStyle {
    theme.style(for: role)
  }

  /// Resolves semantic chrome for a styled control using this snapshot's palette.
  ///
  /// Under increased prominence the selected surface is not distinguished:
  /// `isSelected` has no effect there, and the fill follows only the pressed,
  /// focused, or idle state.
  public func controlChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    isSelected: Bool = false,
    prominence: ControlProminence = .standard,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    let tone = chromeTone(for: role)
    let neutralSurface = themeStyle(for: .background)
    // Focused and selected standard-prominence controls share the selected
    // row surface. The increased-prominence branch below returns before
    // either surface is read, so it needs no accent arm here.
    let focusedSurface = AnyShapeStyle(.terminalRow(tone, isSelected: true))
    let selectedSurface = focusedSurface
    let neutralBorder = AnyShapeStyle(.terminalBorder(.neutral))
    let focusedBorder = AnyShapeStyle(.terminalBorder(tone))

    if !isEnabled {
      return .init(
        foregroundStyle: themeStyle(for: .placeholder),
        contentBackgroundStyle: neutralSurface,
        borderForegroundStyle: neutralBorder,
        opacity: 0.6
      )
    }

    if prominence == .increased {
      let idleFillStyle = AnyShapeStyle(.terminalAccent(tone))
      let focusedFillStyle = AnyShapeStyle(.terminalRow(tone, isSelected: true))
      let pressedFillStyle = AnyShapeStyle(.terminalSurface(tone))
      let fillStyle =
        if isPressed {
          pressedFillStyle
        } else if isFocused {
          focusedFillStyle
        } else {
          idleFillStyle
        }

      return .init(
        foregroundStyle: contrastingForegroundStyle(on: fillStyle),
        contentBackgroundStyle: fillStyle,
        borderForegroundStyle: focusedBorder
      )
    }

    if isSelected {
      return .init(
        foregroundStyle: resolvedStyle(for: .foreground),
        contentBackgroundStyle: selectedSurface,
        borderForegroundStyle: focusedBorder
      )
    }

    if isFocused || isPressed {
      return .init(
        foregroundStyle: resolvedStyle(for: .foreground),
        contentBackgroundStyle: focusedSurface,
        borderForegroundStyle: focusedBorder
      )
    }

    return .init(
      foregroundStyle: resolvedStyle(for: .foreground),
      contentBackgroundStyle: neutralSurface,
      borderForegroundStyle: neutralBorder
    )
  }

  /// Resolves semantic chrome for a styled interactive row.
  public func rowChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    isSelected: Bool = false,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    let tone = chromeTone(for: role)
    let idleBackground = themeStyle(for: .background)
    let activeBackground = AnyShapeStyle(.terminalRow(tone, isSelected: true))
    let activeBorder = AnyShapeStyle(.terminalBorder(tone))
    let idleBorder = AnyShapeStyle(.terminalBorder(.neutral))

    if !isEnabled {
      return .init(
        foregroundStyle: themeStyle(for: .placeholder),
        contentBackgroundStyle: idleBackground,
        borderForegroundStyle: idleBorder,
        opacity: 0.6
      )
    }

    if isPressed || isFocused || isSelected {
      return .init(
        foregroundStyle: resolvedStyle(for: .foreground),
        contentBackgroundStyle: activeBackground,
        borderForegroundStyle: activeBorder
      )
    }

    return .init(
      foregroundStyle: resolvedStyle(for: .foreground),
      contentBackgroundStyle: idleBackground,
      borderForegroundStyle: idleBorder
    )
  }

  /// Resolves semantic chrome for a group box using this snapshot's palette.
  ///
  /// The built-in bordered group box style uses this for its foreground and
  /// border paints: a neutral border at standard prominence, the accent tone
  /// at increased prominence. A custom ``GroupBoxStyle`` can call it to match
  /// the theme without re-deriving the tones.
  ///
  /// - Parameter prominence: The control prominence in effect for the box.
  /// - Returns: The foreground and border paints for the box chrome.
  public func groupBoxChrome(
    prominence: ControlProminence = .standard
  ) -> ContainerChrome {
    let tone: TerminalTone = prominence == .increased ? .accent : .neutral
    return .init(
      foregroundStyle: resolvedStyle(for: .foreground),
      borderStyle: AnyShapeStyle(.terminalBorder(tone))
    )
  }

  private func contrastingForegroundStyle(
    on style: AnyShapeStyle
  ) -> AnyShapeStyle {
    guard
      let backgroundColor = resolveStyleColor(
        style: style,
        theme: theme,
        appearance: appearance
      )
    else {
      return resolvedStyle(for: .foreground)
    }

    let whiteContrast = Color.white.contrastRatio(to: backgroundColor)
    let blackContrast = Color.black.contrastRatio(to: backgroundColor)
    return .color(whiteContrast >= blackContrast ? .white : .black)
  }

  private func chromeTone(
    for role: ButtonRole?
  ) -> TerminalTone {
    switch role {
    case .destructive:
      .danger
    case .cancel, .close:
      .neutral
    case .confirm, nil:
      .accent
    }
  }
}

func contrastSafe(
  _ color: Color,
  against background: Color,
  minimumContrast: Double,
  fallback: Color
) -> Color {
  color.contrastRatio(to: background) >= minimumContrast ? color : fallback
}
