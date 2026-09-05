public import SwiftTUICore

/// Defines the visual composition of a ``Toggle``.
public protocol ToggleStyle: Sendable {
  associatedtype Body: View
  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(configuration: ToggleStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _toggleStyleValueTypeWitness: Void { get }
}

extension ToggleStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _toggleStyleValueTypeWitness: Void { () }
}

extension ToggleStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message: "SwiftTUI styles must be value types; a class cannot conform to ToggleStyle"
  )
  public static var _toggleStyleValueTypeWitness: Void { () }
}

/// Authored content and primitive-owned state supplied to a ``ToggleStyle``.
public struct ToggleStyleConfiguration: Sendable {
  /// The captured authored label.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures authored content for a style fixture.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  public var label: Label
  @Binding public var isOn: Bool
  public var isMixed: Bool
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var isPressed: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot

  public var focusActive: Bool { isFocused && showsFocusEffect }

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    label: Label,
    isOn: Binding<Bool>,
    isMixed: Bool,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self._isOn = isOn
    self.isMixed = isMixed
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``ToggleStyle``.
public struct AnyToggleStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyToggleStyleBox

  public init<S: ToggleStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyToggleStyleBox(style: style)
  }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  public static var automatic: Self {
    Self(AutomaticToggleStyle())
  }
  public static var checkbox: Self {
    Self(CheckboxToggleStyle())
  }
  public static var button: Self {
    Self(ButtonToggleStyle())
  }

  @MainActor
  package func resolveBody(configuration: ToggleStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyToggleStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``Toggle``.
public struct AutomaticToggleStyle: ToggleStyle {
  public init() {}
  public var snapshotLabel: String { "AnyToggleStyle.automatic" }

  @MainActor
  public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    AutomaticToggleStyleBody(configuration: configuration)
  }
}

extension ToggleStyle where Self == AutomaticToggleStyle {
  public static var automatic: AutomaticToggleStyle { .init() }
}

extension AutomaticToggleStyle: ReuseTransparentStyle {}

/// The `checkbox` treatment for ``Toggle``.
public struct CheckboxToggleStyle: ToggleStyle {
  public init() {}
  public var snapshotLabel: String { "AnyToggleStyle.checkbox" }

  @MainActor
  public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    CheckboxToggleStyleBody(configuration: configuration)
  }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
  public static var checkbox: CheckboxToggleStyle { .init() }
}

extension CheckboxToggleStyle: ReuseTransparentStyle {}

/// The `button` treatment for ``Toggle``.
public struct ButtonToggleStyle: ToggleStyle {
  public init() {}
  public var snapshotLabel: String { "AnyToggleStyle.button" }

  @MainActor
  public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    ButtonToggleStyleBody(configuration: configuration)
  }
}

extension ToggleStyle where Self == ButtonToggleStyle {
  public static var button: ButtonToggleStyle { .init() }
}

extension ButtonToggleStyle: ReuseTransparentStyle {}

private protocol AnyToggleStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyToggleStyleBox) -> Bool

  @MainActor
  func resolveBody(configuration: ToggleStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

private struct ConcreteAnyToggleStyleBox<S: ToggleStyle>: AnyToggleStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyToggleStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody(configuration: ToggleStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel, in: context)
  }
}

private struct AutomaticToggleStyleBody: View {
  let configuration: ToggleStyleConfiguration

  var body: some View {
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    BoundControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive,
      isHighlighted: configuration.focusActive || configuration.isPressed
    ) {
      Text(configuration.isMixed ? "◐" : configuration.isOn ? "◉" : "○")
        .foregroundStyle(configuration.isOn ? chrome.borderStyle : AnyShapeStyle(.separator))
      configuration.label
    }
  }
}

private struct CheckboxToggleStyleBody: View {
  let configuration: ToggleStyleConfiguration

  var body: some View {
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    BoundControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive,
      isHighlighted: configuration.focusActive || configuration.isPressed
    ) {
      Text(configuration.isMixed ? "⊟" : configuration.isOn ? "☑" : "☐")
        .foregroundStyle(configuration.isOn ? chrome.borderStyle : AnyShapeStyle(.separator))
      configuration.label
    }
  }
}

private struct ButtonToggleStyleBody: View {
  let configuration: ToggleStyleConfiguration

  var body: some View {
    let selected = configuration.isOn || configuration.isMixed
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed, isSelected: selected)
    BoundControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive,
      isHighlighted: configuration.focusActive || configuration.isPressed || selected
    ) {
      configuration.label
    }
    .padding(.horizontal, 1)
  }
}
