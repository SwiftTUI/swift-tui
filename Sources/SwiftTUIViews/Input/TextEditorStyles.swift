public import SwiftTUICore

/// Defines the visual composition of a ``TextEditor``.
///
/// A text editor style is body-producing: ``makeBody(configuration:)``
/// receives a ``TextEditorStyleConfiguration`` and returns the replacement
/// body. The configuration hands the style one protected slot, the editing
/// surface itself, plus the enabled and focus state; a style surrounds that
/// slot with chrome rather than rebuilding it.
///
/// The primitive keeps everything inside the slot: the text binding, editing
/// keys, selection, the caret and its wrapped movement, scrolling, the single
/// focus stop the editor exposes, and the accessibility role. The slot's
/// measured viewport drives caret navigation, so padding a style adds is
/// accounted for.
///
/// Three built-ins ship. ``RoundedBorderTextEditorStyle`` frames the surface,
/// ``AutomaticTextEditorStyle`` is a fixed alias of it, and
/// ``PlainTextEditorStyle`` removes the chrome. Apply one with
/// `textEditorStyle(_:)`, which stores the style in the environment for
/// its subtree; the nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform.
///
/// ```swift
/// struct GutterTextEditorStyle: TextEditorStyle {
///   func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
///     HStack(spacing: 0) {
///       Text("│").foregroundStyle(configuration.focusActive ? .tint : .separator)
///       configuration.editorContent.padding(.init(horizontal: 1))
///     }
///   }
/// }
///
/// TextEditor(text: $notes)
///   .textEditorStyle(GutterTextEditorStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol TextEditorStyle: Sendable {
  /// The view type ``makeBody(configuration:)`` returns.
  associatedtype Body: View
  /// The label this style reports in snapshots, debug bundles, and style
  /// runtime issues.
  ///
  /// The default implementation reflects the conforming type's name; the
  /// built-ins pin their own, such as `"AnyTextEditorStyle.plain"`. It is
  /// diagnostic text, not identity: do not branch on it.
  var snapshotLabel: String { get }

  /// Composes the protected editing surface and the control's state into the
  /// rendered body.
  ///
  /// Runs on the main actor once per resolve of the styled editor. Place
  /// ``TextEditorStyleConfiguration/editorContent`` exactly once in the body:
  /// omitting it renders no editable surface.
  ///
  /// - Parameter configuration: The protected editing slot and the editor's
  ///   enabled and focus state.
  /// - Returns: The replacement body for the editor.
  @ViewBuilder @MainActor
  func makeBody(configuration: TextEditorStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _textEditorStyleValueTypeWitness: Void { get }
}

extension TextEditorStyle {
  /// The reflected name of the conforming type, used unless the style pins a
  /// label of its own.
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
///
/// ``EditorContent`` is the one slot: a protected view that carries the live
/// editing surface, which a style places in its body and surrounds with
/// chrome. The remaining members are read-only render state for this resolve.
/// There is no text binding here and no press state, because an editor is
/// edited rather than activated.
public struct TextEditorStyleConfiguration: Sendable {
  /// The protected editing surface.
  ///
  /// It hosts the editor's scrolling text, selection, and caret. Place it in
  /// the style body; its measured width is what wrapped caret movement uses,
  /// so any padding or border a style adds is taken into account.
  public struct EditorContent: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Creates inert editing content for a style fixture.
    ///
    /// It mirrors the live shape, a vertical scroll view over the text, with
    /// no focus stop, selection, caret, or key handling, so a style test can
    /// render a body without a live editor (see <doc:Testing-Styles>).
    ///
    /// - Parameter displayText: The text the inert surface shows.
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

    /// The captured editing surface.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The protected editing surface, placed in the body to render the editable
  /// text.
  public var editorContent: EditorContent
  /// Whether the editor accepts input.
  ///
  /// A disabled editor keeps its text visible; the built-in chrome dims with
  /// the control chrome's disabled paints.
  public var isEnabled: Bool
  /// Whether the editor is the focused control.
  ///
  /// Prefer ``focusActive`` when deciding whether to draw a focus treatment:
  /// a control under `focusEffectDisabled()` is still focused for keyboard
  /// purposes but must not show one.
  public var isFocused: Bool
  /// Whether the focus treatment is enabled in this subtree.
  ///
  /// It is `false` under `focusEffectDisabled()`, where the editor still takes
  /// keyboard focus and still edits.
  public var showsFocusEffect: Bool
  /// The `StyleEnvironmentSnapshot` for this resolve: the terminal
  /// appearance, the active theme, the ambient foreground and tint paints,
  /// the enabled state, and the cell metrics.
  ///
  /// The built-in chrome takes its border and background from its
  /// `controlChrome(...)` helper; a custom style can call the same helper to
  /// match.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Whether the editor is focused and the focus effect is enabled.
  ///
  /// This is the flag a style should draw a focus treatment from.
  public var focusActive: Bool { isFocused && showsFocusEffect }

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  ///
  /// The arguments follow this type's stored-property declaration order. The
  /// editing slot supplied to it is inert, so the body renders without a live
  /// editor.
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

/// Type-erased storage for a concrete ``TextEditorStyle``, the value the
/// environment carries.
public struct AnyTextEditorStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyTextEditorStyleBox

  /// Wraps a concrete editor style for the environment.
  ///
  /// The generic `textEditorStyle(_:)` overload calls this for you.
  ///
  /// - Parameter style: The style to erase.
  public init<S: TextEditorStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }

  /// The ``AutomaticTextEditorStyle`` treatment, a fixed alias of
  /// ``AnyTextEditorStyle/roundedBorder``.
  public static var automatic: Self {
    Self(AutomaticTextEditorStyle())
  }
  /// The ``PlainTextEditorStyle`` treatment: the editing surface with no
  /// chrome around it.
  public static var plain: Self {
    Self(PlainTextEditorStyle())
  }
  /// The ``RoundedBorderTextEditorStyle`` treatment: the editing surface
  /// padded inside a rounded, filled frame.
  public static var roundedBorder: Self {
    Self(RoundedBorderTextEditorStyle())
  }

  @MainActor
  package func resolveBody(configuration: TextEditorStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
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

/// The `automatic` treatment for ``TextEditor``: a fixed alias of
/// ``RoundedBorderTextEditorStyle``.
///
/// It renders exactly what the rounded-border style renders and exists so that
/// `.automatic` names one documented treatment rather than a hidden second
/// one. It reports its own snapshot label.
public struct AutomaticTextEditorStyle: TextEditorStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyTextEditorStyle.automatic" }

  /// Composes the rounded-border treatment's body around the editing surface.
  ///
  /// - Parameter configuration: The protected editing slot and the editor's state.
  /// - Returns: The same body ``RoundedBorderTextEditorStyle`` produces.
  @MainActor
  public func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    RoundedBorderTextEditorStyleBody(configuration: configuration)
  }
}

extension TextEditorStyle where Self == AutomaticTextEditorStyle {
  /// The automatic editor treatment, spelled `.automatic` wherever a
  /// ``TextEditorStyle`` is expected.
  public static var automatic: AutomaticTextEditorStyle { .init() }
}

extension AutomaticTextEditorStyle: ReuseTransparentStyle {}

/// The `plain` treatment for ``TextEditor``: the editing surface alone.
///
/// The body is the protected slot with nothing around it: no padding, border,
/// background, or focus treatment. Editing, selection, scrolling, and the
/// caret are unaffected, and the editor occupies exactly the space its text
/// needs within the proposal.
public struct PlainTextEditorStyle: TextEditorStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyTextEditorStyle.plain" }

  /// Returns the protected editing surface with no chrome around it.
  ///
  /// - Parameter configuration: The protected editing slot and the editor's state.
  /// - Returns: The editing surface itself.
  @MainActor
  public func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    PlainTextEditorStyleBody(configuration: configuration)
  }
}

extension TextEditorStyle where Self == PlainTextEditorStyle {
  /// The plain editor treatment, spelled `.plain` wherever a
  /// ``TextEditorStyle`` is expected.
  public static var plain: PlainTextEditorStyle { .init() }
}

extension PlainTextEditorStyle: ReuseTransparentStyle {}

/// The `roundedBorder` treatment for ``TextEditor``: the editing surface
/// inside a rounded, filled frame.
///
/// The surface is padded one cell on every side, filled with the control
/// chrome's background inset by one cell, and outlined by a rounded rectangle
/// stroked in the chrome's border paint, heavy while the focus effect is
/// active. The paints come from the style environment's `controlChrome(...)`
/// helper, so the frame dims when the editor is disabled.
///
/// The built-in uses `View.minimumIntrinsicSize(width:height:)` with height
/// three, keeping the editor content-sized under a finite proposal. Custom
/// styles can use the same public hint; a flexible `.frame(minHeight:)` would
/// fill the finite proposal instead.
public struct RoundedBorderTextEditorStyle: TextEditorStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyTextEditorStyle.roundedBorder" }

  /// Composes the padded, filled, rounded frame around the editing surface.
  ///
  /// - Parameter configuration: The protected editing slot and the editor's state.
  /// - Returns: The framed body for the editor.
  @MainActor
  public func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    RoundedBorderTextEditorStyleBody(configuration: configuration)
  }
}

extension TextEditorStyle where Self == RoundedBorderTextEditorStyle {
  /// The rounded-border editor treatment, spelled `.roundedBorder` wherever a
  /// ``TextEditorStyle`` is expected.
  public static var roundedBorder: RoundedBorderTextEditorStyle { .init() }
}

extension RoundedBorderTextEditorStyle: ReuseTransparentStyle {}

private protocol AnyTextEditorStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(configuration: TextEditorStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyTextEditorStyleBox where S: TextEditorStyle {

  @MainActor
  func resolveBody(configuration: TextEditorStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
  {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
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
      // A stack-minimum hint keeps the editor content-sized under a finite
      // proposal; a flexible frame would fill it.
      .minimumIntrinsicSize(height: 3)
  }
}
