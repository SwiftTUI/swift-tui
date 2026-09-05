public import SwiftTUICore

/// Defines the visual composition of a ``DisclosureGroup``.
public protocol DisclosureGroupStyle: Sendable {
  associatedtype Body: View
  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _disclosureGroupStyleValueTypeWitness: Void { get }
}

extension DisclosureGroupStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _disclosureGroupStyleValueTypeWitness: Void { () }
}

extension DisclosureGroupStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message: "SwiftTUI styles must be value types; a class cannot conform to DisclosureGroupStyle"
  )
  public static var _disclosureGroupStyleValueTypeWitness: Void { () }
}

/// Authored content and primitive-owned state supplied to a ``DisclosureGroupStyle``.
public struct DisclosureGroupStyleConfiguration: Sendable {
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

  /// The captured authored content.
  public struct Content: View, Sendable {
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
  public var content: Content
  @Binding public var isExpanded: Bool
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
    content: Content,
    isExpanded: Binding<Bool>,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self._isExpanded = isExpanded
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``DisclosureGroupStyle``.
public struct AnyDisclosureGroupStyle: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package let snapshotLabel: String
  private let box: any AnyDisclosureGroupStyleBox

  public init<S: DisclosureGroupStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyDisclosureGroupStyleBox(style: style)
  }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  public static var automatic: Self {
    Self(AutomaticDisclosureGroupStyle())
  }
  public static var compact: Self {
    Self(CompactDisclosureGroupStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: DisclosureGroupStyleConfiguration, in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyDisclosureGroupStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``DisclosureGroup``.
public struct AutomaticDisclosureGroupStyle: DisclosureGroupStyle {
  public init() {}
  public var snapshotLabel: String { "AnyDisclosureGroupStyle.automatic" }

  @MainActor
  public func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    AutomaticDisclosureGroupStyleBody(configuration: configuration)
  }
}

extension DisclosureGroupStyle where Self == AutomaticDisclosureGroupStyle {
  public static var automatic: AutomaticDisclosureGroupStyle { .init() }
}

extension AutomaticDisclosureGroupStyle: ReuseTransparentStyle {}

/// The `compact` treatment for ``DisclosureGroup``.
public struct CompactDisclosureGroupStyle: DisclosureGroupStyle {
  public init() {}
  public var snapshotLabel: String { "AnyDisclosureGroupStyle.compact" }

  @MainActor
  public func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    CompactDisclosureGroupStyleBody(configuration: configuration)
  }
}

extension DisclosureGroupStyle where Self == CompactDisclosureGroupStyle {
  public static var compact: CompactDisclosureGroupStyle { .init() }
}

extension CompactDisclosureGroupStyle: ReuseTransparentStyle {}

private protocol AnyDisclosureGroupStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyDisclosureGroupStyleBox) -> Bool

  @MainActor
  func resolveBody(configuration: DisclosureGroupStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

private struct ConcreteAnyDisclosureGroupStyleBox<S: DisclosureGroupStyle>:
  AnyDisclosureGroupStyleBox
{
  let style: S

  func isEqualForReuse(to other: any AnyDisclosureGroupStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody(configuration: DisclosureGroupStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel, in: context)
  }
}

private struct AutomaticDisclosureGroupStyleBody: View {
  let configuration: DisclosureGroupStyleConfiguration

  var body: some View {
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    VStack(alignment: .leading, spacing: 0) {
      BoundControlStyleRow(
        chrome: chrome, focusActive: configuration.focusActive,
        isHighlighted: configuration.focusActive || configuration.isPressed
      ) {
        Text(configuration.isExpanded ? "▾" : "▸")
          .foregroundStyle(
            configuration.isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
        configuration.label
      }
      if configuration.isExpanded {
        configuration.content.padding(.leading, 1)
      }
    }
  }
}

private struct CompactDisclosureGroupStyleBody: View {
  let configuration: DisclosureGroupStyleConfiguration

  var body: some View {
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    VStack(alignment: .leading, spacing: 0) {
      BoundControlStyleRow(
        chrome: chrome, focusActive: false,
        isHighlighted: configuration.focusActive || configuration.isPressed,
        reservesRail: false
      ) {
        Text(configuration.isExpanded ? "▾" : "▸")
          .foregroundStyle(
            configuration.isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
        configuration.label
      }
      if configuration.isExpanded {
        configuration.content.padding(.leading, 1)
      }
    }
  }
}
