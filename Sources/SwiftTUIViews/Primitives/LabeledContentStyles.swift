public import SwiftTUICore

/// Defines the composition of a ``LabeledContent`` through its authored slots.
public protocol LabeledContentStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(configuration: LabeledContentStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _labeledContentStyleValueTypeWitness: Void { get }
}

extension LabeledContentStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _labeledContentStyleValueTypeWitness: Void { () }
}

extension LabeledContentStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to LabeledContentStyle"
  )
  public static var _labeledContentStyleValueTypeWitness: Void { () }
}

/// Authored slots and environment supplied to a ``LabeledContentStyle``.
public struct LabeledContentStyleConfiguration: Sendable {
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

  public var label: Label
  public var content: Content
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    label: Label,
    content: Content,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``LabeledContentStyle``.
public struct AnyLabeledContentStyle: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package let snapshotLabel: String
  private let box: any AnyLabeledContentStyleBox

  public init<S: LabeledContentStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyLabeledContentStyleBox(style: style)
  }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  public static var automatic: Self {
    Self(AutomaticLabeledContentStyle())
  }

  public static var stacked: Self {
    Self(StackedLabeledContentStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: LabeledContentStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyLabeledContentStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` composition for ``LabeledContent``.
public struct AutomaticLabeledContentStyle: LabeledContentStyle {
  public init() {}

  public var snapshotLabel: String { "AnyLabeledContentStyle.automatic" }

  @MainActor
  public func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    AutomaticLabeledContentStyleBody(configuration: configuration)
  }
}

extension LabeledContentStyle where Self == AutomaticLabeledContentStyle {
  public static var automatic: AutomaticLabeledContentStyle { .init() }
}

extension AutomaticLabeledContentStyle: ReuseTransparentStyle {}

/// The `stacked` composition for ``LabeledContent``.
public struct StackedLabeledContentStyle: LabeledContentStyle {
  public init() {}

  public var snapshotLabel: String { "AnyLabeledContentStyle.stacked" }

  @MainActor
  public func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    StackedLabeledContentStyleBody(configuration: configuration)
  }
}

extension LabeledContentStyle where Self == StackedLabeledContentStyle {
  public static var stacked: StackedLabeledContentStyle { .init() }
}

extension StackedLabeledContentStyle: ReuseTransparentStyle {}

private protocol AnyLabeledContentStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyLabeledContentStyleBox) -> Bool

  @MainActor
  func resolveBody(
    configuration: LabeledContentStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

private struct ConcreteAnyLabeledContentStyleBox<S: LabeledContentStyle>: AnyLabeledContentStyleBox
{
  let style: S

  func isEqualForReuse(to other: any AnyLabeledContentStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody(
    configuration: LabeledContentStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel,
      in: context
    )
  }
}

private struct AutomaticLabeledContentStyleBody: View {
  let configuration: LabeledContentStyleConfiguration

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      configuration.label.foregroundStyle(.separator)
      Spacer()
      configuration.content
    }
  }
}

private struct StackedLabeledContentStyleBody: View {
  let configuration: LabeledContentStyleConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.label.foregroundStyle(.separator)
      configuration.content
    }
  }
}
