public import SwiftTUICore

/// Defines the composition of a ``Label`` through its authored slots.
public protocol LabelStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(configuration: LabelStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _labelStyleValueTypeWitness: Void { get }
}

extension LabelStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _labelStyleValueTypeWitness: Void { () }
}

extension LabelStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to LabelStyle"
  )
  public static var _labelStyleValueTypeWitness: Void { () }
}

/// Authored slots and environment supplied to a ``LabelStyle``.
public struct LabelStyleConfiguration: Sendable {
  /// The captured, authored title.
  public struct Title: View, Sendable {
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

  /// The captured, authored icon.
  public struct Icon: View, Sendable {
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

  public var title: Title
  public var icon: Icon
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    title: Title,
    icon: Icon,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.title = title
    self.icon = icon
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``LabelStyle``.
public struct AnyLabelStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyLabelStyleBox

  public init<S: LabelStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyLabelStyleBox(style: style)
  }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  public static var automatic: Self {
    Self(AutomaticLabelStyle())
  }

  public static var titleAndIcon: Self {
    Self(TitleAndIconLabelStyle())
  }

  public static var titleOnly: Self {
    Self(TitleOnlyLabelStyle())
  }

  public static var iconOnly: Self {
    Self(IconOnlyLabelStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: LabelStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyLabelStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` composition for ``Label``.
public struct AutomaticLabelStyle: LabelStyle {
  public init() {}

  public var snapshotLabel: String { "AnyLabelStyle.automatic" }

  @MainActor
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    TitleAndIconLabelStyleBody(configuration: configuration)
  }
}

extension LabelStyle where Self == AutomaticLabelStyle {
  public static var automatic: AutomaticLabelStyle { .init() }
}

extension AutomaticLabelStyle: ReuseTransparentStyle {}

/// The `titleAndIcon` composition for ``Label``.
public struct TitleAndIconLabelStyle: LabelStyle {
  public init() {}

  public var snapshotLabel: String { "AnyLabelStyle.titleAndIcon" }

  @MainActor
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    TitleAndIconLabelStyleBody(configuration: configuration)
  }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
  public static var titleAndIcon: TitleAndIconLabelStyle { .init() }
}

extension TitleAndIconLabelStyle: ReuseTransparentStyle {}

/// The `titleOnly` composition for ``Label``.
public struct TitleOnlyLabelStyle: LabelStyle {
  public init() {}

  public var snapshotLabel: String { "AnyLabelStyle.titleOnly" }

  @MainActor
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    TitleOnlyLabelStyleBody(configuration: configuration)
  }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
  public static var titleOnly: TitleOnlyLabelStyle { .init() }
}

extension TitleOnlyLabelStyle: ReuseTransparentStyle {}

/// The `iconOnly` composition for ``Label``.
public struct IconOnlyLabelStyle: LabelStyle {
  public init() {}

  public var snapshotLabel: String { "AnyLabelStyle.iconOnly" }

  @MainActor
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    IconOnlyLabelStyleBody(configuration: configuration)
  }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
  public static var iconOnly: IconOnlyLabelStyle { .init() }
}

extension IconOnlyLabelStyle: ReuseTransparentStyle {}

private protocol AnyLabelStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyLabelStyleBox) -> Bool

  @MainActor
  func resolveBody(
    configuration: LabelStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

private struct ConcreteAnyLabelStyleBox<S: LabelStyle>: AnyLabelStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyLabelStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody(
    configuration: LabelStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel,
      in: context
    )
  }
}

private struct TitleAndIconLabelStyleBody: View {
  let configuration: LabelStyleConfiguration

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      configuration.icon
      configuration.title
    }
  }
}

private struct TitleOnlyLabelStyleBody: View {
  let configuration: LabelStyleConfiguration

  var body: some View { configuration.title }
}

private struct IconOnlyLabelStyleBody: View {
  let configuration: LabelStyleConfiguration

  var body: some View { configuration.icon }
}
