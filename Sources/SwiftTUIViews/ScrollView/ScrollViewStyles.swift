public import SwiftTUICore

/// The scroll primitive's axes, permitted indicators, and host capabilities.
public struct ScrollViewStyleConfiguration: Sendable {
  public var axes: Axis.Set
  public var visibleIndicatorAxes: Axis.Set
  public var focusedIndicatorAxes: Axis.Set
  public var allowsDirectManipulation: Bool
  public var isEnabled: Bool
  public var showsFocusEffect: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a fixture without registering scrolling or focus handlers.
  @_spi(StyleFixtures)
  public init(
    axes: Axis.Set, visibleIndicatorAxes: Axis.Set, focusedIndicatorAxes: Axis.Set,
    allowsDirectManipulation: Bool, isEnabled: Bool, showsFocusEffect: Bool = true,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.axes = axes
    self.visibleIndicatorAxes = visibleIndicatorAxes
    self.focusedIndicatorAxes = focusedIndicatorAxes
    self.allowsDirectManipulation = allowsDirectManipulation
    self.isEnabled = isEnabled
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
  }
}

/// Indicator and container appearance; scrolling, clipping, and visibility stay primitive-owned.
public struct ScrollViewStylePresentation: Sendable, Equatable {
  public var snapshotLabel: String
  public var contentInsets: EdgeInsets
  public var verticalIndicatorGlyph: String
  public var horizontalIndicatorGlyph: String
  public var indicatorStyle: AnyShapeStyle
  public var focusedIndicatorStyle: AnyShapeStyle
  public var backgroundStyle: AnyShapeStyle?
  public var opacity: Double
  public var reservesIndicatorSpace: Bool

  public init(
    snapshotLabel: String, contentInsets: EdgeInsets = .zero,
    verticalIndicatorGlyph: String = "▐", horizontalIndicatorGlyph: String = "▂",
    indicatorStyle: AnyShapeStyle = .semantic(.muted),
    focusedIndicatorStyle: AnyShapeStyle = .semantic(.tint),
    backgroundStyle: AnyShapeStyle? = nil, opacity: Double = 1,
    reservesIndicatorSpace: Bool = true
  ) {
    self.snapshotLabel = snapshotLabel
    self.contentInsets = contentInsets
    self.verticalIndicatorGlyph = verticalIndicatorGlyph
    self.horizontalIndicatorGlyph = horizontalIndicatorGlyph
    self.indicatorStyle = indicatorStyle
    self.focusedIndicatorStyle = focusedIndicatorStyle
    self.backgroundStyle = backgroundStyle
    self.opacity = opacity
    self.reservesIndicatorSpace = reservesIndicatorSpace
  }
}

/// Supplies appearance while the scroll view owns its layout and input behavior.
public protocol ScrollViewStyle: Sendable {
  var snapshotLabel: String { get }
  @MainActor
  func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
}

extension ScrollViewStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyScrollViewStyleBox: Sendable {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: ScrollViewStyleConfiguration) -> ScrollViewStylePresentation
  func isEqualForReuse(to other: any AnyScrollViewStyleBox) -> Bool
}

private struct ConcreteAnyScrollViewStyleBox<S: ScrollViewStyle>: AnyScrollViewStyleBox {
  let style: S
  var snapshotLabel: String { style.snapshotLabel }
  @MainActor
  func presentation(for configuration: ScrollViewStyleConfiguration) -> ScrollViewStylePresentation
  {
    style.resolvePresentation(for: configuration)
  }
  func isEqualForReuse(to other: any AnyScrollViewStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// Type-erased scroll styling with comparison of its concrete style value.
public struct AnyScrollViewStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyScrollViewStyleBox
  public init<S: ScrollViewStyle>(_ style: S) { box = ConcreteAnyScrollViewStyleBox(style: style) }
  public var description: String { box.snapshotLabel }
  public var debugDescription: String { description }
  public static var automatic: Self { Self(AutomaticScrollViewStyle()) }
  public static var minimal: Self { Self(MinimalScrollViewStyle()) }

  @MainActor
  package func presentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    box.presentation(for: configuration)
  }
}

extension AnyScrollViewStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// Preserves the current indicator glyphs, reserved tracks, and theme treatment.
public struct AutomaticScrollViewStyle: ScrollViewStyle {
  public init() {}
  public var snapshotLabel: String { "ScrollViewStyle.automatic" }
  @MainActor
  public func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    let environment = configuration.styleEnvironment
    return .init(
      snapshotLabel: snapshotLabel,
      focusedIndicatorStyle: configuration.showsFocusEffect
        ? environment.controlChrome(isEnabled: configuration.isEnabled, isFocused: true).borderStyle
        : .semantic(.tint),
      opacity: environment.controlChrome(isEnabled: configuration.isEnabled, isFocused: false)
        .opacity)
  }
}

/// Draws a muted thumb over the content without reserving an indicator track.
public struct MinimalScrollViewStyle: ScrollViewStyle {
  public init() {}
  public var snapshotLabel: String { "ScrollViewStyle.minimal" }
  @MainActor
  public func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    var presentation = AutomaticScrollViewStyle().resolvePresentation(for: configuration)
    presentation.snapshotLabel = snapshotLabel
    presentation.reservesIndicatorSpace = false
    return presentation
  }
}

extension ScrollViewStyle where Self == AutomaticScrollViewStyle {
  public static var automatic: Self { .init() }
}
extension ScrollViewStyle where Self == MinimalScrollViewStyle {
  public static var minimal: Self { .init() }
}
extension AutomaticScrollViewStyle: ReuseTransparentStyle {}
extension MinimalScrollViewStyle: ReuseTransparentStyle {}
