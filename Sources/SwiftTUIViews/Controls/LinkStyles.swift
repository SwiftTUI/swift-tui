public import SwiftTUICore

/// The interaction state of a standalone or interpolated link.
///
/// A link style receives only render state: there is no captured content slot,
/// because the link's own label stays with the primitive and the style answers
/// with a ``LinkStylePresentation`` instead of a body.
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public struct LinkStyleConfiguration: Sendable {
  /// Whether the link is interpolated into surrounding ``Text`` rather than
  /// standing on its own.
  ///
  /// An inline link renders as runs merged into the containing text, so a style
  /// that changes size-affecting attributes should keep an inline link readable
  /// beside the words around it.
  public var isInline: Bool
  /// Whether the link accepts activation. A disabled link still renders; the
  /// built-ins dim it and, except for ``UnderlinedLinkStyle``, drop its link
  /// color.
  public var isEnabled: Bool
  /// Whether the link owns keyboard focus, regardless of whether a focus
  /// treatment is allowed.
  public var isFocused: Bool
  /// Whether the environment permits a focus treatment; `focusEffectDisabled()`
  /// clears it while the link stays focused.
  public var showsFocusEffect: Bool
  /// Whether the link is in its pressed state for this pass.
  public var isPressed: Bool
  /// The resolved style environment for this pass: the theme, its semantic
  /// colors (including the link color), the enablement flag, and the chrome
  /// helpers a custom style uses to match the built-in treatments.
  public var styleEnvironment: StyleEnvironmentSnapshot
  /// Whether the link is focused and the focus effect is enabled.
  ///
  /// Read this rather than combining `isFocused` and `showsFocusEffect`
  /// yourself: a link under `focusEffectDisabled()` still activates from the
  /// keyboard but must not draw a focus treatment.
  public var focusActive: Bool { isFocused && showsFocusEffect }

  /// Constructs a fixture without registering a link action.
  ///
  /// This is also the framework's own construction path; the parameters mirror
  /// the stored properties in declaration order (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    isInline: Bool, isEnabled: Bool, isFocused: Bool, showsFocusEffect: Bool,
    isPressed: Bool, styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.isInline = isInline
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.styleEnvironment = styleEnvironment
  }
}

/// Distinguishes inheriting an underline from explicitly removing it.
public enum LinkUnderlineStyle: Sendable, Equatable {
  /// Keeps whatever underline the containing text already applies.
  case inherited
  /// Removes the underline, even when the containing text is underlined.
  case hidden
  /// Draws the given line style, overriding the containing text.
  case visible(TextLineStyle)
}

/// Appearance merged between the containing text and the link's own label.
///
/// Every field is a delta over the inherited text style: leave a field at its
/// inheriting default and the containing text's value survives. The primitive
/// merges the result into the link's runs, so a presentation changes appearance
/// only, never the destination, the action, or the semantics.
public struct LinkStylePresentation: Sendable, Equatable {
  /// The link's text color, or `nil` to inherit the containing text's
  /// foreground.
  public var foregroundStyle: AnyShapeStyle?
  /// The background painted behind the link's runs, or `nil` for none. The
  /// built-ins set it only while the link is focused or pressed.
  public var backgroundStyle: AnyShapeStyle?
  /// Emphasis added to the link's runs. It accumulates with the containing
  /// text's emphasis rather than replacing it.
  public var emphasis: TextStyle.TextEmphasis
  /// How the link's underline is drawn: inherited, hidden, or an explicit line
  /// style.
  public var underline: LinkUnderlineStyle
  /// `nil` inherits; an explicit value multiplies the containing text's opacity.
  ///
  /// The value must be finite and between zero and one. An out-of-range opacity
  /// is discarded: the field falls back to `nil`, so the link inherits instead
  /// of dimming, and the render is reported as a partially invalid presentation
  /// (`style.invalidPresentation`).
  public var opacity: Double?

  /// Creates a presentation from the fields that differ from the containing
  /// text.
  ///
  /// Every parameter defaults to its inheriting value: no foreground, no
  /// background, no added emphasis, an inherited underline, and inherited
  /// opacity.
  public init(
    foregroundStyle: AnyShapeStyle? = nil, backgroundStyle: AnyShapeStyle? = nil,
    emphasis: TextStyle.TextEmphasis = [], underline: LinkUnderlineStyle = .inherited,
    opacity: Double? = nil
  ) {
    self.foregroundStyle = foregroundStyle
    self.backgroundStyle = backgroundStyle
    self.emphasis = emphasis
    self.underline = underline
    self.opacity = opacity
  }
}

/// Styles link runs without changing their destination, action, or semantics.
///
/// A link style is a presentation-value style, not a body-producing one: it
/// answers ``LinkStyle/resolvePresentation(for:)`` with a
/// ``LinkStylePresentation`` that the primitive merges into the link's text
/// runs. The focus stop, the activation route, the destination, and the
/// accessibility semantics stay with the primitive.
///
/// Apply a style with `linkStyle(_:)`. The value is stored in the environment
/// for the subtree, so the nearest modifier wins, and it reaches both standalone
/// links and links interpolated into ``Text``. The built-ins are
/// ``AnyLinkStyle/automatic``, ``AnyLinkStyle/underlined``, and
/// ``AnyLinkStyle/plain``; `.automatic` and `.underlined` render identically for
/// an enabled link and differ only when the link is disabled.
///
/// A conforming type must be `Sendable`.
///
/// ```swift
/// struct BracketLinkStyle: LinkStyle {
///   func resolvePresentation(for configuration: LinkStyleConfiguration)
///     -> LinkStylePresentation
///   {
///     LinkStylePresentation(
///       foregroundStyle: AnyShapeStyle(.warning),
///       emphasis: .bold,
///       underline: .hidden,
///       opacity: configuration.focusActive ? 1 : 0.8
///     )
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol LinkStyle: Sendable {
  /// The label reported for this style in snapshots and diagnostics.
  ///
  /// The default implementation returns the reflected type name. It is
  /// diagnostic text: reuse and identity never depend on its value.
  var snapshotLabel: String { get }
  /// Resolves the appearance of the link's runs for the current pass.
  ///
  /// Return only the fields that should differ from the containing text; the
  /// rest are inherited. The method is called for each pass in which the link
  /// renders, so it must be a pure function of `configuration`.
  ///
  /// - Parameter configuration: The link's render state for this pass.
  /// - Returns: The appearance merged into the link's runs.
  @MainActor
  func resolvePresentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation
}

extension LinkStyle {
  /// The reflected name of the conforming type, used when a style does not
  /// supply a label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyLinkStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation
}

extension ConcreteStyleBox: AnyLinkStyleBox where S: LinkStyle {
  var snapshotLabel: String { style.snapshotLabel }
  @MainActor
  func presentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation {
    style.resolvePresentation(for: configuration)
  }
}

/// Type-erased link styling with comparison of its concrete style value.
///
/// This is the value the environment carries: `linkStyle(_:)` wraps a concrete
/// style in it before storing it for the subtree. The built-ins are exposed as
/// statics here as well as on ``LinkStyle`` itself.
public struct AnyLinkStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyLinkStyleBox
  /// Wraps a concrete link style for storage in the environment.
  ///
  /// - Parameter style: The concrete style to erase.
  public init<S: LinkStyle>(_ style: S) { box = ConcreteStyleBox(style: style) }
  /// The wrapped style's `snapshotLabel`.
  public var description: String { box.snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { description }
  /// The default link treatment: the theme's link color with a solid underline,
  /// a row background while focused or pressed, and the placeholder color at
  /// 0.6 opacity when disabled. For an enabled link it renders exactly like
  /// ``AnyLinkStyle/underlined``.
  public static var automatic: Self { Self(AutomaticLinkStyle()) }
  /// The theme's link color with a solid underline. It differs from
  /// ``AnyLinkStyle/automatic`` only when the link is disabled, where it keeps
  /// the link color under the same dimming instead of falling back to the
  /// placeholder color.
  public static var underlined: Self { Self(UnderlinedLinkStyle()) }
  /// Inherits the containing text's foreground and hides the underline, keeping
  /// the focus and press background and the disabled dimming.
  public static var plain: Self { Self(PlainLinkStyle()) }

  @MainActor
  package func presentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation {
    box.presentation(for: configuration)
  }
}

extension AnyLinkStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// Preserves the current theme's link foreground, underline, and focus treatment.
///
/// An enabled link is drawn in the theme's link color with a solid underline,
/// and takes the accent row background while it is focused or pressed. A
/// disabled link falls back to the theme's placeholder color at 0.6 opacity.
/// For an enabled link this is
/// indistinguishable from ``UnderlinedLinkStyle``.
public struct AutomaticLinkStyle: LinkStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "LinkStyle.automatic" }
  /// Resolves the theme link chrome into a presentation: link foreground, solid
  /// underline, a background only while focused or pressed, and the chrome's
  /// dimming opacity.
  ///
  /// - Parameter configuration: The link's render state for this pass.
  /// - Returns: The theme-derived link appearance.
  @MainActor
  public func resolvePresentation(for configuration: LinkStyleConfiguration)
    -> LinkStylePresentation
  {
    let chrome = resolvedLinkButtonChrome(
      styleEnvironment: configuration.styleEnvironment, isEnabled: configuration.isEnabled,
      isFocused: configuration.isFocused, showsFocusEffect: configuration.showsFocusEffect,
      isPressed: configuration.isPressed)
    return .init(
      foregroundStyle: chrome.foregroundStyle,
      backgroundStyle: configuration.focusActive || configuration.isPressed
        ? chrome.backgroundStyle : nil,
      underline: .visible(.init(pattern: .solid)), opacity: chrome.opacity)
  }
}

/// Uses semantic link color and a solid underline.
///
/// It takes the ``AutomaticLinkStyle`` presentation and forces the foreground to
/// the theme's link color. For an enabled link that is the color automatic
/// already resolved, so the two are indistinguishable; the difference shows on a
/// disabled link, which keeps the link color under the dimming opacity instead
/// of turning to the placeholder color.
public struct UnderlinedLinkStyle: LinkStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "LinkStyle.underlined" }
  /// Resolves the automatic presentation and replaces its foreground with the
  /// theme's link color, keeping the underline, background, and opacity.
  ///
  /// - Parameter configuration: The link's render state for this pass.
  /// - Returns: The link-colored, underlined appearance.
  @MainActor
  public func resolvePresentation(for configuration: LinkStyleConfiguration)
    -> LinkStylePresentation
  {
    var presentation = AutomaticLinkStyle().resolvePresentation(for: configuration)
    presentation.foregroundStyle = configuration.styleEnvironment.themeStyle(for: .link)
    return presentation
  }
}

/// Inherits the containing text's foreground and removes its underline. The
/// focus and press background and the disabled dimming still apply, so a
/// disabled plain link dims exactly like a disabled automatic one.
public struct PlainLinkStyle: LinkStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "LinkStyle.plain" }
  /// Resolves a presentation with no foreground of its own and a hidden
  /// underline, carrying over the automatic background and opacity.
  ///
  /// - Parameter configuration: The link's render state for this pass.
  /// - Returns: The inheriting, underline-free appearance.
  @MainActor
  public func resolvePresentation(for configuration: LinkStyleConfiguration)
    -> LinkStylePresentation
  {
    let automatic = AutomaticLinkStyle().resolvePresentation(for: configuration)
    return .init(
      backgroundStyle: automatic.backgroundStyle, underline: .hidden,
      opacity: automatic.opacity)
  }
}

extension LinkStyle where Self == AutomaticLinkStyle {
  /// The ``AutomaticLinkStyle`` value, so `.automatic` resolves wherever a
  /// concrete ``LinkStyle`` is expected.
  public static var automatic: Self { .init() }
}
extension LinkStyle where Self == UnderlinedLinkStyle {
  /// The ``UnderlinedLinkStyle`` value, so `.underlined` resolves wherever a
  /// concrete ``LinkStyle`` is expected.
  public static var underlined: Self { .init() }
}
extension LinkStyle where Self == PlainLinkStyle {
  /// The ``PlainLinkStyle`` value, so `.plain` resolves wherever a concrete
  /// ``LinkStyle`` is expected.
  public static var plain: Self { .init() }
}
extension AutomaticLinkStyle: ReuseTransparentStyle {}
extension UnderlinedLinkStyle: ReuseTransparentStyle {}
extension PlainLinkStyle: ReuseTransparentStyle {}
