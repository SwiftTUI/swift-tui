public import SwiftTUICore

/// Defines the visual composition of a ``Stepper``.
public protocol StepperStyle: Sendable {
  associatedtype Body: View
  var snapshotLabel: String { get }
  @ViewBuilder @MainActor
  func makeBody(configuration: StepperStyleConfiguration) -> Body
  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _stepperStyleValueTypeWitness: Void { get }
}

extension StepperStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }
  @_documentation(visibility: internal)
  public static var _stepperStyleValueTypeWitness: Void { () }
}

extension StepperStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message: "SwiftTUI styles must be value types; a class cannot conform to StepperStyle"
  )
  public static var _stepperStyleValueTypeWitness: Void { () }
}

/// Authored content, normalized state, and primitive-owned routes for a ``StepperStyle``.
public struct StepperStyleConfiguration: Sendable {
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
  public var canDecrement: Bool
  public var canIncrement: Bool
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var isPressed: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot
  public var focusActive: Bool { isFocused && showsFocusEffect }
  private var decrementIdentity: Identity?
  private var incrementIdentity: Identity?

  /// Constructs an inert configuration for a style test.
  @_spi(StyleFixtures)
  public init(
    label: Label,
    valueLabel: ValueLabel,
    canDecrement: Bool,
    canIncrement: Bool,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.valueLabel = valueLabel
    self.canDecrement = canDecrement
    self.canIncrement = canIncrement
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.styleEnvironment = styleEnvironment
    decrementIdentity = nil
    incrementIdentity = nil
  }

  /// Installs the primitive's decrement pointer target. Install once; fixture routes are inert.
  @ViewBuilder @MainActor
  public func decrement<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if let decrementIdentity {
      StyleRouteView(
        target: .init(identity: decrementIdentity, family: "StepperStyle", role: "decrement"),
        content: content().disabled(!isEnabled || !canDecrement))
    } else {
      content()
    }
  }

  /// Installs the primitive's increment pointer target. Install once; fixture routes are inert.
  @ViewBuilder @MainActor
  public func increment<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if let incrementIdentity {
      StyleRouteView(
        target: .init(identity: incrementIdentity, family: "StepperStyle", role: "increment"),
        content: content().disabled(!isEnabled || !canIncrement))
    } else {
      content()
    }
  }

  mutating func bindRoutes(to identity: Identity) {
    decrementIdentity = stepperDecrementIdentity(for: identity)
    incrementIdentity = stepperIncrementIdentity(for: identity)
  }
}

/// Type-erased storage for a concrete ``StepperStyle``.
public struct AnyStepperStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyStepperStyleBox
  public init<S: StepperStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyStepperStyleBox(style: style)
  }
  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }
  public static var automatic: Self {
    Self(AutomaticStepperStyle())
  }
  public static var compact: Self {
    Self(CompactStepperStyle())
  }
  @MainActor
  package func resolveBody(configuration: StepperStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyStepperStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``Stepper``.
public struct AutomaticStepperStyle: StepperStyle {
  public init() {}
  public var snapshotLabel: String { "AnyStepperStyle.automatic" }
  @MainActor
  public func makeBody(configuration: StepperStyleConfiguration) -> some View {
    AutomaticStepperStyleBody(configuration: configuration)
  }
}
extension StepperStyle where Self == AutomaticStepperStyle {
  public static var automatic: AutomaticStepperStyle { .init() }
}
extension AutomaticStepperStyle: ReuseTransparentStyle {}

/// The `compact` treatment for ``Stepper``.
public struct CompactStepperStyle: StepperStyle {
  public init() {}
  public var snapshotLabel: String { "AnyStepperStyle.compact" }
  @MainActor
  public func makeBody(configuration: StepperStyleConfiguration) -> some View {
    CompactStepperStyleBody(configuration: configuration)
  }
}
extension StepperStyle where Self == CompactStepperStyle {
  public static var compact: CompactStepperStyle { .init() }
}
extension CompactStepperStyle: ReuseTransparentStyle {}

private struct AutomaticStepperStyleBody: View {
  let configuration: StepperStyleConfiguration
  var body: some View { StepperStyleRow(configuration: configuration, compact: false) }
}

private struct CompactStepperStyleBody: View {
  let configuration: StepperStyleConfiguration
  var body: some View { StepperStyleRow(configuration: configuration, compact: true) }
}

private struct StepperStyleRow: View {
  let configuration: StepperStyleConfiguration
  let compact: Bool
  var body: some View {
    let active = configuration.focusActive || configuration.isPressed
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let contentChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let accent = active ? contentChrome.borderStyle : AnyShapeStyle(.separator)
    ValueControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive,
      isHighlighted: active, reservesRail: !compact
    ) {
      configuration.label.foregroundStyle(.terminalBorder(.accent))
      HStack(alignment: .center, spacing: 1) {
        configuration.decrement {
          Text(compact ? "−" : configuration.canDecrement ? "◀" : "◁")
            .foregroundStyle(configuration.canDecrement ? accent : AnyShapeStyle(.placeholder))
        }
        configuration.valueLabel.foregroundStyle(
          active ? contentChrome.foregroundStyle : chrome.foregroundStyle)
        configuration.increment {
          Text(compact ? "+" : configuration.canIncrement ? "▶" : "▷")
            .foregroundStyle(configuration.canIncrement ? accent : AnyShapeStyle(.placeholder))
        }
      }
      .opacity(contentChrome.opacity)
      .background {
        if active { Rectangle().fill(contentChrome.backgroundStyle) }
      }
    }
  }
}

private protocol AnyStepperStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyStepperStyleBox) -> Bool
  @MainActor
  func resolveBody(configuration: StepperStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}
private struct ConcreteAnyStepperStyleBox<S: StepperStyle>: AnyStepperStyleBox {
  let style: S
  func isEqualForReuse(to other: any AnyStepperStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
  @MainActor
  func resolveBody(configuration: StepperStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel, in: context)
  }
}
