/// Concrete semantic token colors suitable for host-supplied themes, wrapper
/// transport, and local semantic style resolution.
public struct Theme: Equatable, Sendable, Codable {
  public var foreground: Color
  public var background: Color
  public var tint: Color
  public var separator: Color
  public var selection: Color
  public var placeholder: Color
  public var link: Color
  public var fill: Color
  public var windowBackground: Color
  public var success: Color
  public var warning: Color
  public var danger: Color
  public var info: Color
  public var muted: Color

  public init(
    foreground: Color = try! .hex("#ECEFF4"),
    background: Color = try! .hex("#1E222A"),
    tint: Color = .cyan,
    separator: Color = try! .hex("#4C566A"),
    selection: Color = try! .hex("#2E3440"),
    placeholder: Color = .gray,
    link: Color = .blue,
    fill: Color = try! .hex("#2B303B"),
    windowBackground: Color = try! .hex("#15181E"),
    success: Color = .green,
    warning: Color = .yellow,
    danger: Color = .red,
    info: Color = .cyan,
    muted: Color = .gray
  ) {
    self.foreground = foreground
    self.background = background
    self.tint = tint
    self.separator = separator
    self.selection = selection
    self.placeholder = placeholder
    self.link = link
    self.fill = fill
    self.windowBackground = windowBackground
    self.success = success
    self.warning = warning
    self.danger = danger
    self.info = info
    self.muted = muted
  }

  public static let `default` = Self()

  private enum CodingKeys: String, CodingKey {
    case foreground
    case background
    case tint
    case separator
    case selection
    case placeholder
    case link
    case fill
    case windowBackground
    case success
    case warning
    case danger
    case info
    case muted
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    foreground = try Self.decodeColor(for: .foreground, from: container)
    background = try Self.decodeColor(for: .background, from: container)
    tint = try Self.decodeColor(for: .tint, from: container)
    separator = try Self.decodeColor(for: .separator, from: container)
    selection = try Self.decodeColor(for: .selection, from: container)
    placeholder = try Self.decodeColor(for: .placeholder, from: container)
    link = try Self.decodeColor(for: .link, from: container)
    fill = try Self.decodeColor(for: .fill, from: container)
    windowBackground = try Self.decodeColor(for: .windowBackground, from: container)
    success = try Self.decodeColor(for: .success, from: container)
    warning = try Self.decodeColor(for: .warning, from: container)
    danger = try Self.decodeColor(for: .danger, from: container)
    info = try Self.decodeColor(for: .info, from: container)
    muted = try Self.decodeColor(for: .muted, from: container)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try Self.encodeColor(foreground, for: .foreground, into: &container)
    try Self.encodeColor(background, for: .background, into: &container)
    try Self.encodeColor(tint, for: .tint, into: &container)
    try Self.encodeColor(separator, for: .separator, into: &container)
    try Self.encodeColor(selection, for: .selection, into: &container)
    try Self.encodeColor(placeholder, for: .placeholder, into: &container)
    try Self.encodeColor(link, for: .link, into: &container)
    try Self.encodeColor(fill, for: .fill, into: &container)
    try Self.encodeColor(windowBackground, for: .windowBackground, into: &container)
    try Self.encodeColor(success, for: .success, into: &container)
    try Self.encodeColor(warning, for: .warning, into: &container)
    try Self.encodeColor(danger, for: .danger, into: &container)
    try Self.encodeColor(info, for: .info, into: &container)
    try Self.encodeColor(muted, for: .muted, into: &container)
  }

  public func color(for role: SemanticStyleRole) -> Color {
    switch role {
    case .foreground:
      foreground
    case .background:
      background
    case .tint:
      tint
    case .separator:
      separator
    case .selection:
      selection
    case .placeholder:
      placeholder
    case .link:
      link
    case .fill:
      fill
    case .windowBackground:
      windowBackground
    case .success:
      success
    case .warning:
      warning
    case .danger:
      danger
    case .info:
      info
    case .muted:
      muted
    }
  }

  public func style(for role: SemanticStyleRole) -> AnyShapeStyle {
    .color(color(for: role))
  }

  private static func decodeColor(
    for key: CodingKeys,
    from container: KeyedDecodingContainer<CodingKeys>
  ) throws -> Color {
    let value = try container.decode(String.self, forKey: key)
    return try Color(hex: value)
  }

  private static func encodeColor(
    _ color: Color,
    for key: CodingKeys,
    into container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    try container.encode(color.hexString(), forKey: key)
  }
}

/// The host-owned styling payload that pairs terminal appearance metadata with
/// an optional semantic theme override.
public struct TerminalRenderStyle: Equatable, Sendable, Codable {
  public var appearance: TerminalAppearance
  public var theme: Theme?

  public init(
    appearance: TerminalAppearance,
    theme: Theme? = nil
  ) {
    self.appearance = appearance
    self.theme = theme
  }

  public var resolvedTheme: Theme {
    theme ?? appearance.synthesizedTheme()
  }
}

/// Heap-allocated storage for the large ``TerminalAppearance`` and ``Theme``
/// value types.  Keeping them behind a reference avoids ~5 KB of stack copies
/// at every level of view-tree resolution.
package final class StyleHeavyFieldsStorage: Sendable {
  package let appearance: TerminalAppearance
  package let theme: Theme

  package init(appearance: TerminalAppearance, theme: Theme) {
    self.appearance = appearance
    self.theme = theme
  }
}

/// Styling state captured from the environment during resolve.
public struct StyleEnvironmentSnapshot: Equatable, Sendable {
  /// Boxed storage for the heavy value-type fields (~5 KB to 8 bytes).
  package var heavyFields: StyleHeavyFieldsStorage

  public var appearance: TerminalAppearance { heavyFields.appearance }
  public var theme: Theme { heavyFields.theme }
  public var foregroundStyle: AnyShapeStyle?
  public var tintStyle: AnyShapeStyle?
  public var isEnabled: Bool
  /// Display metrics for the current terminal surface.
  public var cellPixelMetrics: CellPixelMetrics

  public init(
    appearance: TerminalAppearance = .fallback,
    theme: Theme? = nil,
    foregroundStyle: AnyShapeStyle? = nil,
    tintStyle: AnyShapeStyle? = nil,
    isEnabled: Bool = true,
    cellPixelMetrics: CellPixelMetrics = .estimated
  ) {
    self.heavyFields = StyleHeavyFieldsStorage(
      appearance: appearance,
      theme: theme ?? appearance.synthesizedTheme()
    )
    self.foregroundStyle = foregroundStyle
    self.tintStyle = tintStyle
    self.isEnabled = isEnabled
    self.cellPixelMetrics = cellPixelMetrics
  }

  /// Creates a snapshot reusing existing heavy-field storage (no copy).
  package init(
    heavyFields: StyleHeavyFieldsStorage,
    foregroundStyle: AnyShapeStyle?,
    tintStyle: AnyShapeStyle?,
    isEnabled: Bool,
    cellPixelMetrics: CellPixelMetrics = .estimated
  ) {
    self.heavyFields = heavyFields
    self.foregroundStyle = foregroundStyle
    self.tintStyle = tintStyle
    self.isEnabled = isEnabled
    self.cellPixelMetrics = cellPixelMetrics
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.heavyFields === rhs.heavyFields
      || (lhs.appearance == rhs.appearance
        && lhs.theme == rhs.theme
        && lhs.foregroundStyle == rhs.foregroundStyle
        && lhs.tintStyle == rhs.tintStyle
        && lhs.isEnabled == rhs.isEnabled
        && lhs.cellPixelMetrics == rhs.cellPixelMetrics)
  }
}
