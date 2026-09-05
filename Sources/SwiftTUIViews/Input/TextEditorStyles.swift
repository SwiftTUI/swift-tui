public import SwiftTUICore

/// Defines the visual composition of a ``TextEditor``.
public protocol TextEditorStyle: Sendable {
  associatedtype Body: View
  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(configuration: TextEditorStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _textEditorStyleValueTypeWitness: Void { get }
}

extension TextEditorStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _textEditorStyleValueTypeWitness: Void { () }
}

extension TextEditorStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message: "SwiftTUI styles must be value types; a class cannot conform to TextEditorStyle"
  )
  public static var _textEditorStyleValueTypeWitness: Void { () }
}

/// Authored content and primitive-owned state supplied to a ``TextEditorStyle``.
public struct TextEditorStyleConfiguration: Sendable {
  /// The protected editing surface.
  public struct EditorContent: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Creates inert editing content for a style fixture.
    @_spi(StyleFixtures)
    public init(displayText: String) {
      payload = CapturedSubviewPayload {
        ScrollView(.vertical) {
          Text(displayText).fixedSize(horizontal: false, vertical: true)
        }
        .focusable(false)
        .ambientTextAttributesReset()
      }
    }

    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  public var editorContent: EditorContent
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot

  public var focusActive: Bool { isFocused && showsFocusEffect }

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    editorContent: EditorContent,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.editorContent = editorContent
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``TextEditorStyle``.
public struct AnyTextEditorStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyTextEditorStyleBox

  public init<S: TextEditorStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyTextEditorStyleBox(style: style)
  }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  public static var automatic: Self {
    Self(AutomaticTextEditorStyle())
  }
  public static var plain: Self {
    Self(PlainTextEditorStyle())
  }
  public static var roundedBorder: Self {
    Self(RoundedBorderTextEditorStyle())
  }

  @MainActor
  package func resolveBody(configuration: TextEditorStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyTextEditorStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``TextEditor``.
public struct AutomaticTextEditorStyle: TextEditorStyle {
  public init() {}
  public var snapshotLabel: String { "AnyTextEditorStyle.automatic" }

  @MainActor
  public func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    RoundedBorderTextEditorStyleBody(configuration: configuration)
  }
}

extension TextEditorStyle where Self == AutomaticTextEditorStyle {
  public static var automatic: AutomaticTextEditorStyle { .init() }
}

extension AutomaticTextEditorStyle: ReuseTransparentStyle {}

/// The `plain` treatment for ``TextEditor``.
public struct PlainTextEditorStyle: TextEditorStyle {
  public init() {}
  public var snapshotLabel: String { "AnyTextEditorStyle.plain" }

  @MainActor
  public func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    PlainTextEditorStyleBody(configuration: configuration)
  }
}

extension TextEditorStyle where Self == PlainTextEditorStyle {
  public static var plain: PlainTextEditorStyle { .init() }
}

extension PlainTextEditorStyle: ReuseTransparentStyle {}

/// The `roundedBorder` treatment for ``TextEditor``.
public struct RoundedBorderTextEditorStyle: TextEditorStyle {
  public init() {}
  public var snapshotLabel: String { "AnyTextEditorStyle.roundedBorder" }

  @MainActor
  public func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    RoundedBorderTextEditorStyleBody(configuration: configuration)
  }
}

extension TextEditorStyle where Self == RoundedBorderTextEditorStyle {
  public static var roundedBorder: RoundedBorderTextEditorStyle { .init() }
}

extension RoundedBorderTextEditorStyle: ReuseTransparentStyle {}

private protocol AnyTextEditorStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyTextEditorStyleBox) -> Bool

  @MainActor
  func resolveBody(configuration: TextEditorStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

private struct ConcreteAnyTextEditorStyleBox<S: TextEditorStyle>: AnyTextEditorStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyTextEditorStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody(configuration: TextEditorStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel, in: context)
  }
}

private struct PlainTextEditorStyleBody: View {
  let configuration: TextEditorStyleConfiguration

  var body: some View { configuration.editorContent }
}

private struct RoundedBorderTextEditorStyleBody: View {
  let configuration: TextEditorStyleConfiguration

  var body: some View {
    let contentChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: false)
    let focusChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive)
    configuration.editorContent
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(contentChrome.backgroundStyle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(
          focusChrome.borderStyle,
          style: configuration.focusActive ? .heavy : .init())
      }
      .frame(minHeight: 3, alignment: .topLeading)
  }
}
