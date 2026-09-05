public import SwiftTUICore

/// Defines the composition of a ``GroupBox`` through its authored slots.
public protocol GroupBoxStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(configuration: GroupBoxStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _groupBoxStyleValueTypeWitness: Void { get }
}

extension GroupBoxStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _groupBoxStyleValueTypeWitness: Void { () }
}

extension GroupBoxStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to GroupBoxStyle"
  )
  public static var _groupBoxStyleValueTypeWitness: Void { () }
}

/// Authored slots and environment supplied to a ``GroupBoxStyle``.
public struct GroupBoxStyleConfiguration: Sendable {
  /// The captured, authored label.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures content for a style test (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  /// The captured, authored content.
  public struct Content: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures content for a style test (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  public var label: Label?
  public var content: Content
  public var controlProminence: ControlProminence
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    label: Label?,
    content: Content,
    controlProminence: ControlProminence,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self.controlProminence = controlProminence
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``GroupBoxStyle``.
public struct AnyGroupBoxStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyGroupBoxStyleBox

  public init<S: GroupBoxStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyGroupBoxStyleBox(style: style)
  }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  public static var automatic: Self {
    Self(AutomaticGroupBoxStyle())
  }

  public static var bordered: Self {
    Self(BorderedGroupBoxStyle())
  }

  public static var plain: Self {
    Self(PlainGroupBoxStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: GroupBoxStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyGroupBoxStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` composition for ``GroupBox``.
public struct AutomaticGroupBoxStyle: GroupBoxStyle {
  public init() {}

  public var snapshotLabel: String { "AnyGroupBoxStyle.automatic" }

  @MainActor
  public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    BorderedGroupBoxStyleBody(configuration: configuration)
  }
}

extension GroupBoxStyle where Self == AutomaticGroupBoxStyle {
  public static var automatic: AutomaticGroupBoxStyle { .init() }
}

extension AutomaticGroupBoxStyle: ReuseTransparentStyle {}

/// The `bordered` composition for ``GroupBox``.
public struct BorderedGroupBoxStyle: GroupBoxStyle {
  public init() {}

  public var snapshotLabel: String { "AnyGroupBoxStyle.bordered" }

  @MainActor
  public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    BorderedGroupBoxStyleBody(configuration: configuration)
  }
}

extension GroupBoxStyle where Self == BorderedGroupBoxStyle {
  public static var bordered: BorderedGroupBoxStyle { .init() }
}

extension BorderedGroupBoxStyle: ReuseTransparentStyle {}

/// The `plain` composition for ``GroupBox``.
public struct PlainGroupBoxStyle: GroupBoxStyle {
  public init() {}

  public var snapshotLabel: String { "AnyGroupBoxStyle.plain" }

  @MainActor
  public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    PlainGroupBoxStyleBody(configuration: configuration)
  }
}

extension GroupBoxStyle where Self == PlainGroupBoxStyle {
  public static var plain: PlainGroupBoxStyle { .init() }
}

extension PlainGroupBoxStyle: ReuseTransparentStyle {}

private protocol AnyGroupBoxStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyGroupBoxStyleBox) -> Bool

  @MainActor
  func resolveBody(
    configuration: GroupBoxStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

private struct ConcreteAnyGroupBoxStyleBox<S: GroupBoxStyle>: AnyGroupBoxStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyGroupBoxStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody(
    configuration: GroupBoxStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel,
      in: context
    )
  }
}

private struct BorderedGroupBoxStyleBody: View {
  let configuration: GroupBoxStyleConfiguration

  var body: some View {
    let environment = configuration.styleEnvironment
    let foreground = environment.foregroundStyle ?? environment.theme.style(for: .foreground)
    let tone: TerminalTone = configuration.controlProminence == .increased ? .accent : .neutral
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label {
        label.foregroundStyle(.separator)
      }
      VStack(alignment: .leading, spacing: 0) {
        configuration.content
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(AnyShapeStyle(.terminalBorder(tone)))
      }
      .foregroundStyle(foreground)
    }
    .frame(minHeight: .finite((configuration.label == nil ? 0 : 1) + 3), alignment: .topLeading)
  }
}

private struct PlainGroupBoxStyleBody: View {
  let configuration: GroupBoxStyleConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label {
        label.foregroundStyle(.separator)
      }
      configuration.content
    }
  }
}
