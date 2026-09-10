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
///
/// This is the value every style configuration carries as its
/// `styleEnvironment`: the detected terminal appearance, the active semantic
/// `Theme`, the ambient foreground and tint paints, whether the styled view is
/// enabled, and the terminal's cell metrics. A style reads it instead of
/// reaching for global state, so the same style renders correctly under a
/// different appearance, theme, or ambient paint.
///
/// Resolve mints one of these per styled control from the environment in
/// effect there. Constructing one directly is for style tests, where the
/// memberwise initializer's defaults stand in for a live host; see the
/// Testing Styles guide.
public struct StyleEnvironmentSnapshot: Equatable, Sendable {
  /// Boxed storage for the heavy value-type fields (~5 KB to 8 bytes).
  package var heavyFields: StyleHeavyFieldsStorage

  /// The detected appearance of the host terminal at the styled view.
  ///
  /// Carries the terminal's foreground, background, and tint colors, its ANSI
  /// palette, the derived contrast level, and how the value was determined.
  /// Prefer `theme` for paints; read this when a style needs the raw terminal
  /// colors or the contrast level.
  public var appearance: TerminalAppearance { heavyFields.appearance }
  /// The active semantic palette.
  ///
  /// The host selects the theme; when it selects none, this is the theme
  /// synthesized from `appearance`. Resolve paints through
  /// `Theme.style(for:)` or `resolvedStyle(for:)` rather than naming literal
  /// colors, so a style follows whatever palette is in effect.
  public var theme: Theme { heavyFields.theme }
  /// The ambient foreground paint at the styled view, or `nil` when the app
  /// set none.
  ///
  /// Written by `foregroundStyle(_:)`. `resolvedStyle(for:)` returns it for
  /// the `.foreground` role, so a style that resolves paints through that
  /// method honors an app-level override without extra work.
  public var foregroundStyle: AnyShapeStyle?
  /// The ambient tint paint at the styled view, or `nil` when the app set
  /// none.
  ///
  /// Written by `tint(_:)`. `resolvedStyle(for:)` returns it for the `.tint`
  /// role, so accent chrome such as a focused border follows it.
  public var tintStyle: AnyShapeStyle?
  /// Whether the styled view accepts interaction.
  ///
  /// The resolved value of `disabled(_:)` at the control, already combined
  /// with every ancestor's value. A style should render a disabled treatment
  /// when this is `false`; it must not try to re-enable the control, which
  /// the primitive owns.
  public var isEnabled: Bool
  /// Display metrics for the current terminal surface.
  ///
  /// Resolved through the environment, this is the metric the host reported.
  /// A snapshot constructed directly, as a style fixture does, gets
  /// `CellPixelMetrics.estimated`, the conventional 8x16 fallback. The value
  /// is advisory: layout, placement, and alignment stay in cells, and a style
  /// uses these metrics only for aspect correction of shapes, motion, or
  /// image sizes.
  public var cellPixelMetrics: CellPixelMetrics

  /// Creates a snapshot, defaulting every field to the no-host baseline.
  ///
  /// Intended for style tests: the defaults describe a terminal no host has
  /// reported on, so a fixture needs to pass only the fields its assertion
  /// depends on. See the Testing Styles guide.
  ///
  /// - Parameters:
  ///   - appearance: The terminal appearance. Defaults to
  ///     `TerminalAppearance.fallback`.
  ///   - theme: The semantic palette, or `nil` to synthesize one from
  ///     `appearance`. Defaults to `nil`.
  ///   - foregroundStyle: The ambient foreground paint, or `nil` for none.
  ///     Defaults to `nil`.
  ///   - tintStyle: The ambient tint paint, or `nil` for none. Defaults to
  ///     `nil`.
  ///   - isEnabled: Whether the styled view accepts interaction. Defaults to
  ///     `true`.
  ///   - cellPixelMetrics: The cell-to-pixel metrics. Defaults to
  ///     `CellPixelMetrics.estimated`.
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

  /// Equality as the reuse gate consumes it, via `EnvironmentSnapshot.==`.
  ///
  /// The boxed-identity check elides only the *heavy* comparison. It must not
  /// short-circuit the light fields: two snapshots share a box whenever
  /// `EnvironmentValues.applying(to:reuseStyle:)` takes its reuse branch, and
  /// that branch fires for every non-style key — including `cellPixelMetrics`,
  /// which `ResolveContext.isStyleKeyPath` does not name and which has a public
  /// setter. Answering `true` there let a serve keep a subtree whose metrics
  /// had changed.
  ///
  /// Deliberately *not* paired with shared boxed storage. Memoizing the box so
  /// equal appearance/theme pairs yield one instance does what it claims —
  /// measured on `gallery-tab-switch`, box mints 1,548 -> 1, identity hits
  /// 63% -> 100%, and slow-path comparisons 4,521 -> 0, every one of which had
  /// found the heavy fields equal — and still moved no wall clock: the gallery
  /// example suite ran 22.63 s median before and 22.30 s after, inside its own
  /// 0.93 s run-to-run spread. The comparison is not on the critical path, so
  /// the sharing is not worth its global mutable slot.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    let heavyFieldsAreEqual =
      lhs.heavyFields === rhs.heavyFields
      || (lhs.appearance == rhs.appearance && lhs.theme == rhs.theme)
    return heavyFieldsAreEqual
      && lhs.foregroundStyle == rhs.foregroundStyle
      && lhs.tintStyle == rhs.tintStyle
      && lhs.isEnabled == rhs.isEnabled
      && lhs.cellPixelMetrics == rhs.cellPixelMetrics
  }
}
