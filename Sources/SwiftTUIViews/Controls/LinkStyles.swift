public import SwiftTUICore

/// The interaction state of a standalone or interpolated link.
public struct LinkStyleConfiguration: Sendable {
  public var isInline: Bool
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var isPressed: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot
  public var focusActive: Bool { isFocused && showsFocusEffect }

  /// Constructs a fixture without registering a link action.
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
  case inherited
  case hidden
  case visible(TextLineStyle)
}

/// Appearance merged between the containing text and the link's own label.
public struct LinkStylePresentation: Sendable, Equatable {
  public var foregroundStyle: AnyShapeStyle?
  public var backgroundStyle: AnyShapeStyle?
  public var emphasis: TextStyle.TextEmphasis
  public var underline: LinkUnderlineStyle
  /// `nil` inherits; an explicit value multiplies the containing text's opacity.
  public var opacity: Double?

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
public protocol LinkStyle: Sendable {
  var snapshotLabel: String { get }
  @MainActor
  func resolvePresentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation
}

extension LinkStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyLinkStyleBox: Sendable {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation
  func isEqualForReuse(to other: any AnyLinkStyleBox) -> Bool
}

private struct ConcreteAnyLinkStyleBox<S: LinkStyle>: AnyLinkStyleBox {
  let style: S
  var snapshotLabel: String { style.snapshotLabel }
  @MainActor
  func presentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation {
    style.resolvePresentation(for: configuration)
  }
  func isEqualForReuse(to other: any AnyLinkStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// Type-erased link styling with comparison of its concrete style value.
public struct AnyLinkStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyLinkStyleBox
  public init<S: LinkStyle>(_ style: S) { box = ConcreteAnyLinkStyleBox(style: style) }
  public var description: String { box.snapshotLabel }
  public var debugDescription: String { description }
  public static var automatic: Self { Self(AutomaticLinkStyle()) }
  public static var underlined: Self { Self(UnderlinedLinkStyle()) }
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
public struct AutomaticLinkStyle: LinkStyle {
  public init() {}
  public var snapshotLabel: String { "LinkStyle.automatic" }
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
public struct UnderlinedLinkStyle: LinkStyle {
  public init() {}
  public var snapshotLabel: String { "LinkStyle.underlined" }
  @MainActor
  public func resolvePresentation(for configuration: LinkStyleConfiguration)
    -> LinkStylePresentation
  {
    var presentation = AutomaticLinkStyle().resolvePresentation(for: configuration)
    presentation.foregroundStyle = configuration.styleEnvironment.themeStyle(for: .link)
    return presentation
  }
}

/// Inherits the containing text's foreground and removes its underline.
public struct PlainLinkStyle: LinkStyle {
  public init() {}
  public var snapshotLabel: String { "LinkStyle.plain" }
  @MainActor
  public func resolvePresentation(for configuration: LinkStyleConfiguration)
    -> LinkStylePresentation
  {
    let automatic = AutomaticLinkStyle().resolvePresentation(for: configuration)
    return .init(backgroundStyle: automatic.backgroundStyle, underline: .hidden)
  }
}

extension LinkStyle where Self == AutomaticLinkStyle {
  public static var automatic: Self { .init() }
}
extension LinkStyle where Self == UnderlinedLinkStyle {
  public static var underlined: Self { .init() }
}
extension LinkStyle where Self == PlainLinkStyle {
  public static var plain: Self { .init() }
}
extension AutomaticLinkStyle: ReuseTransparentStyle {}
extension UnderlinedLinkStyle: ReuseTransparentStyle {}
extension PlainLinkStyle: ReuseTransparentStyle {}
