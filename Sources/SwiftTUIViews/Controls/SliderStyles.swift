public import SwiftTUICore

/// Defines the visual composition of a ``Slider``.
public protocol SliderStyle: Sendable {
  associatedtype Body: View
  var snapshotLabel: String { get }
  @ViewBuilder @MainActor
  func makeBody(configuration: SliderStyleConfiguration) -> Body
  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _sliderStyleValueTypeWitness: Void { get }
}

extension SliderStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }
  @_documentation(visibility: internal)
  public static var _sliderStyleValueTypeWitness: Void { () }
}

extension SliderStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message: "SwiftTUI styles must be value types; a class cannot conform to SliderStyle"
  )
  public static var _sliderStyleValueTypeWitness: Void { () }
}

/// Authored content, normalized state, and primitive-owned routes for a ``SliderStyle``.
public struct SliderStyleConfiguration: Sendable {
  /// Captured authored label content.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload
    package init<V: View>(
      authoringContext: AuthoringContext?, @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }
    /// Captures content for a style fixture.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// Captured framework-formatted value content.
  public struct ValueLabel: View, Sendable {
    package let payload: CapturedSubviewPayload
    package init<V: View>(
      authoringContext: AuthoringContext?, @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }
    /// Captures content for a style fixture.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  public var label: Label
  public var valueLabel: ValueLabel
  public var fractionCompleted: Double
  public var trackCellCount: Int
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var isPressed: Bool
  public var canDecrement: Bool
  public var canIncrement: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot
  public var focusActive: Bool { isFocused && showsFocusEffect }
  private var trackIdentity: Identity?

  /// Constructs an inert configuration for a style test.
  @_spi(StyleFixtures)
  public init(
    label: Label,
    valueLabel: ValueLabel,
    fractionCompleted: Double,
    trackCellCount: Int,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    canDecrement: Bool,
    canIncrement: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.valueLabel = valueLabel
    self.fractionCompleted = fractionCompleted
    self.trackCellCount = trackCellCount
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.canDecrement = canDecrement
    self.canIncrement = canIncrement
    self.styleEnvironment = styleEnvironment
    trackIdentity = nil
  }

  /// Installs the primitive's track pointer target. Install once; fixture routes are inert.
  @ViewBuilder @MainActor
  public func track<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if let trackIdentity {
      StyleRouteView(
        target: .init(
          identity: trackIdentity, family: "SliderStyle", role: "track", captureOnPress: true),
        content: content().disabled(!isEnabled))
    } else {
      content()
    }
  }

  mutating func bindRoutes(to identity: Identity) {
    trackIdentity = sliderTrackIdentity(for: identity)
  }
}

/// Type-erased storage for a concrete ``SliderStyle``.
public struct AnySliderStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnySliderStyleBox
  public init<S: SliderStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnySliderStyleBox(style: style)
  }
  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }
  public static var automatic: Self {
    Self(AutomaticSliderStyle())
  }
  public static var linear: Self {
    Self(LinearSliderStyle())
  }
  @MainActor
  package func resolveBody(configuration: SliderStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnySliderStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``Slider``.
public struct AutomaticSliderStyle: SliderStyle {
  public init() {}
  public var snapshotLabel: String { "AnySliderStyle.automatic" }
  @MainActor
  public func makeBody(configuration: SliderStyleConfiguration) -> some View {
    AutomaticSliderStyleBody(configuration: configuration)
  }
}
extension SliderStyle where Self == AutomaticSliderStyle {
  public static var automatic: AutomaticSliderStyle { .init() }
}
extension AutomaticSliderStyle: ReuseTransparentStyle {}

/// The `linear` treatment for ``Slider``.
public struct LinearSliderStyle: SliderStyle {
  public init() {}
  public var snapshotLabel: String { "AnySliderStyle.linear" }
  @MainActor
  public func makeBody(configuration: SliderStyleConfiguration) -> some View {
    LinearSliderStyleBody(configuration: configuration)
  }
}
extension SliderStyle where Self == LinearSliderStyle {
  public static var linear: LinearSliderStyle { .init() }
}
extension LinearSliderStyle: ReuseTransparentStyle {}

private struct AutomaticSliderStyleBody: View {
  let configuration: SliderStyleConfiguration
  var body: some View { LinearSliderStyleBody(configuration: configuration) }
}

private struct LinearSliderStyleBody: View {
  let configuration: SliderStyleConfiguration
  var body: some View {
    let active = configuration.focusActive || configuration.isPressed
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let contentChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let width = max(1, configuration.trackCellCount)
    let fraction =
      configuration.fractionCompleted.isFinite
      ? min(max(configuration.fractionCompleted, 0), 1) : 0
    let position = min(width - 1, max(0, Int((fraction * Double(width - 1)).rounded())))
    ValueControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive, isHighlighted: active
    ) {
      configuration.label.foregroundStyle(.terminalBorder(.accent))
      HStack(alignment: .center, spacing: 1) {
        configuration.track {
          Text(
            String(repeating: "━", count: position) + "●"
              + String(repeating: "─", count: width - position - 1)
          )
          .foregroundStyle(active ? contentChrome.borderStyle : AnyShapeStyle(.separator))
        }
        configuration.valueLabel.foregroundStyle(
          active ? contentChrome.foregroundStyle : chrome.foregroundStyle)
      }
      .opacity(contentChrome.opacity)
      .background {
        if active { Rectangle().fill(contentChrome.backgroundStyle) }
      }
    }
  }
}

private protocol AnySliderStyleBox: Sendable {
  func isEqualForReuse(to other: any AnySliderStyleBox) -> Bool
  @MainActor
  func resolveBody(configuration: SliderStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}
private struct ConcreteAnySliderStyleBox<S: SliderStyle>: AnySliderStyleBox {
  let style: S
  func isEqualForReuse(to other: any AnySliderStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
  @MainActor
  func resolveBody(configuration: SliderStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel, in: context)
  }
}
