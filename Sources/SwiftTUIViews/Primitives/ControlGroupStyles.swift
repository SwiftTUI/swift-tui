public import SwiftTUICore

/// Defines the composition of a ``ControlGroup`` through its authored slots.
public protocol ControlGroupStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(configuration: ControlGroupStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _controlGroupStyleValueTypeWitness: Void { get }
}

extension ControlGroupStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _controlGroupStyleValueTypeWitness: Void { () }
}

extension ControlGroupStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to ControlGroupStyle"
  )
  public static var _controlGroupStyleValueTypeWitness: Void { () }
}

/// Authored slots and environment supplied to a ``ControlGroupStyle``.
public struct ControlGroupStyleConfiguration: Sendable {
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
    package let payloads: [ScopedContentPayload]
    package var retention: CapturedSubviewRetention? = nil

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payloads = withAuthoringContext(makeCapturedAuthoringContext(from: authoringContext)) {
        scopedDeclaredBuilderChildren(from: content())
      }
    }

    /// Captures content for a style test (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      self.init(authoringContext: currentAuthoringContext(), content: content)
    }

    public var body: some View {
      sequence
    }

    package var sequence: CapturedSubviewSequenceView {
      CapturedSubviewSequenceView(payloads: payloads, retention: retention)
    }
  }

  public var label: Label?
  public var content: Content
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    label: Label?,
    content: Content,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self.styleEnvironment = styleEnvironment
  }
}

extension ControlGroupStyleConfiguration.Content: ResolvableView, DeclaredChildrenView {
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    sequence.resolveElements(in: context)
  }

  package func appendDeclaredChildren(
    in context: ResolveContext, kindName: String, nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    sequence.appendDeclaredChildren(
      in: context, kindName: kindName, nextIndex: &nextIndex, into: &resolved)
  }

  package func appendScopedDeclaredChildren(
    in context: DeclaredPayloadTraversalContext, kindName: String, nextIndex: inout Int,
    into children: inout [ScopedContentPayload]
  ) {
    sequence.appendScopedDeclaredChildren(
      in: context, kindName: kindName, nextIndex: &nextIndex, into: &children)
  }

  package func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext, kindName: String, nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  ) {
    sequence.appendPortalDeclaredChildren(
      in: context, kindName: kindName, nextIndex: &nextIndex, into: &children)
  }

  package func enumerateDeclaredChildren(
    in context: ResolveContext, kindName: String, nextIndex: inout Int,
    visitor: (Any, ResolveContext, @escaping @MainActor () -> ResolvedNode) -> Void
  ) {
    sequence.enumerateDeclaredChildren(
      in: context, kindName: kindName, nextIndex: &nextIndex, visitor: visitor)
  }
}

/// Type-erased storage for a concrete ``ControlGroupStyle``.
public struct AnyControlGroupStyle: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package let snapshotLabel: String
  private let box: any AnyControlGroupStyleBox

  public init<S: ControlGroupStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyControlGroupStyleBox(style: style)
  }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  public static var automatic: Self {
    Self(AutomaticControlGroupStyle())
  }

  public static var horizontal: Self {
    Self(HorizontalControlGroupStyle())
  }
  public static var compactMenu: Self {
    Self(CompactMenuControlGroupStyle())
  }

  public static var vertical: Self {
    Self(VerticalControlGroupStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: ControlGroupStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyControlGroupStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` composition for ``ControlGroup``.
public struct AutomaticControlGroupStyle: ControlGroupStyle {
  public init() {}

  public var snapshotLabel: String { "AnyControlGroupStyle.automatic" }

  @MainActor
  public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    AutomaticControlGroupStyleBody(configuration: configuration)
  }
}

extension ControlGroupStyle where Self == AutomaticControlGroupStyle {
  public static var automatic: AutomaticControlGroupStyle { .init() }
}

extension AutomaticControlGroupStyle: ReuseTransparentStyle {}

/// The `vertical` composition for ``ControlGroup``.
public struct VerticalControlGroupStyle: ControlGroupStyle {
  public init() {}

  public var snapshotLabel: String { "AnyControlGroupStyle.vertical" }

  @MainActor
  public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    VerticalControlGroupStyleBody(configuration: configuration)
  }
}

extension ControlGroupStyle where Self == VerticalControlGroupStyle {
  public static var vertical: VerticalControlGroupStyle { .init() }
}

extension VerticalControlGroupStyle: ReuseTransparentStyle {}

private protocol AnyControlGroupStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyControlGroupStyleBox) -> Bool

  @MainActor
  func resolveBody(
    configuration: ControlGroupStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

private struct ConcreteAnyControlGroupStyleBox<S: ControlGroupStyle>: AnyControlGroupStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyControlGroupStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody(
    configuration: ControlGroupStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel,
      in: context
    )
  }
}

private struct AutomaticControlGroupStyleBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View { HorizontalControlGroupStyleBody(configuration: configuration) }
}

private struct HorizontalControlGroupStyleBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label { label.foregroundStyle(.separator) }
      HStack(spacing: 1) { configuration.content }
    }
  }
}

private struct VerticalControlGroupStyleBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label { label.foregroundStyle(.separator) }
      VStack(alignment: .leading, spacing: 1) { configuration.content }
    }
  }
}

private struct CompactMenuControlGroupStyleBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    Menu {
      if let label = configuration.label { label } else { Text("Controls") }
    } content: {
      configuration.content
    }
  }
}

/// The `horizontal` composition for ``ControlGroup``.
public struct HorizontalControlGroupStyle: ControlGroupStyle {
  public init() {}
  public var snapshotLabel: String { "AnyControlGroupStyle.horizontal" }
  @MainActor
  public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    HorizontalControlGroupStyleBody(configuration: configuration)
  }
}
extension ControlGroupStyle where Self == HorizontalControlGroupStyle {
  public static var horizontal: HorizontalControlGroupStyle { .init() }
}
extension HorizontalControlGroupStyle: ReuseTransparentStyle {}

/// The `compactMenu` composition for ``ControlGroup``.
public struct CompactMenuControlGroupStyle: ControlGroupStyle {
  public init() {}
  public var snapshotLabel: String { "AnyControlGroupStyle.compactMenu" }
  @MainActor
  public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    CompactMenuControlGroupStyleBody(configuration: configuration)
  }
}
extension ControlGroupStyle where Self == CompactMenuControlGroupStyle {
  public static var compactMenu: CompactMenuControlGroupStyle { .init() }
}
extension CompactMenuControlGroupStyle: ReuseTransparentStyle {}
