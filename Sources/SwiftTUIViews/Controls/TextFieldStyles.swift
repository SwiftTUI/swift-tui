public import SwiftTUICore

/// Defines how single-line and secure text fields render their label and field content.
///
/// A text-field style is body-producing: for every pass the primitive resolves a
/// ``TextFieldStyleConfiguration`` and calls
/// ``TextFieldStyle/makeBody(configuration:)``, and the returned view stands in
/// for the field. Both ``TextField`` and ``SecureField`` resolve through this
/// family.
///
/// The configuration carries two captured slots and read-only render state. The
/// protected slot is ``TextFieldStyleConfiguration/fieldContent``: editing, the
/// caret, the selection runs, and paste all ride on that view, so a body that
/// omits it renders a field that cannot be edited. The focus stop, the text
/// binding, key handling, and the accessibility semantics stay with the
/// primitive whatever the style returns.
///
/// Apply a style with `textFieldStyle(_:)`. The value is stored in the
/// environment for the subtree, so the nearest modifier wins. The built-ins are
/// ``AnyTextFieldStyle/automatic``, ``AnyTextFieldStyle/plain``, and
/// ``AnyTextFieldStyle/roundedBorder``; `.automatic` is a fixed alias of
/// `.roundedBorder`.
///
/// A conforming type must be a value type (a struct or an enum) and `Sendable`;
/// a class conformance does not compile.
///
/// ```swift
/// struct UnderlineTextFieldStyle: TextFieldStyle {
///   func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
///     VStack(alignment: .leading, spacing: 0) {
///       configuration.fieldContent
///         .foregroundStyle(
///           configuration.isShowingPrompt
///             ? configuration.placeholderStyle
///             : configuration.chrome.foregroundStyle
///         )
///       Rectangle()
///         .fill(configuration.focusActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
///         .frame(height: 1)
///     }
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol TextFieldStyle: Sendable {
  /// The view type this style returns for a text field.
  associatedtype Body: View

  /// The label reported for this style in snapshots and diagnostics.
  ///
  /// The default implementation returns the reflected type name. It is
  /// diagnostic text: reuse and identity never depend on its value.
  var snapshotLabel: String { get }

  /// Builds the view that renders in the text field's place.
  ///
  /// Place ``TextFieldStyleConfiguration/fieldContent`` somewhere in the result:
  /// it is what carries the editable text, the caret, and the selection.
  ///
  /// - Parameter configuration: The captured label, the field content, and the
  ///   render state of this field.
  /// - Returns: The replacement body for the control.
  @ViewBuilder @MainActor
  func makeBody(
    configuration: TextFieldStyleConfiguration
  ) -> Body

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _textFieldStyleValueTypeWitness: Void { get }
}

extension TextFieldStyle {
  @_documentation(visibility: internal)
  public static var _textFieldStyleValueTypeWitness: Void { () }
}

extension TextFieldStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI text field styles must be value types (a struct or an enum); a class cannot conform to TextFieldStyle"
  )
  public static var _textFieldStyleValueTypeWitness: Void { () }
}

extension TextFieldStyle {
  /// The reflected name of the conforming type, used when a style does not
  /// supply a label of its own.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The captured label, the editable field content, and the render state a
/// ``TextFieldStyle`` composes into a body.
///
/// Two members are captured authored slots. ``label`` keeps the scope its
/// content was authored in, and ``fieldContent`` is the protected editing slot:
/// it carries the display runs, the selection, the owning field's identity, and
/// the caret anchor. Placing `fieldContent` in the body is what keeps editing,
/// the caret, and paste working; decorating it with padding, a frame, or a
/// foreground style is fine.
///
/// The remaining members are read-only render state the primitive resolved for
/// this pass. ``chrome`` arrives pre-resolved, so a style that wants the
/// built-in colors does not need to consult the theme itself.
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public struct TextFieldStyleConfiguration: Sendable {
  /// The authored label of the field, captured with its authoring scope.
  ///
  /// Place it in the body when ``TextFieldStyleConfiguration/showsLabel`` is
  /// true. Because the content keeps the scope it was authored in, its state,
  /// environment values, and preferences survive wherever the style puts it.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(
        authoringContext: authoringContext,
        content: content
      )
    }

    /// Captures `content` as the authored label of a fixture-constructed
    /// configuration (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  /// The protected editing slot: the field's visible text, its selection runs,
  /// the owning field's identity, and the caret anchor.
  ///
  /// A style must place it in the body. Text editing, the caret, selection
  /// highlighting, and paste all ride on this view, so a body that leaves it out
  /// renders a field the user cannot edit. Padding, framing, and coloring it are
  /// all safe.
  public struct FieldContent: View, Sendable {
    package var displayText: String
    package var displayRuns: [TextInputDisplayRun]
    package var ownerIdentity: Identity?
    package var caretAnchor: CellPoint?

    nonisolated package init(
      displayText: String,
      displayRuns: [TextInputDisplayRun]? = nil,
      ownerIdentity: Identity? = nil,
      caretAnchor: CellPoint? = nil
    ) {
      self.displayText = displayText
      self.displayRuns =
        displayRuns ?? [
          TextInputDisplayRun(text: displayText, isSelected: false)
        ]
      self.ownerIdentity = ownerIdentity
      self.caretAnchor = caretAnchor
    }

    /// Field content for a fixture-constructed configuration: it shows
    /// `displayText` with no selection, owning field, or caret.
    @_spi(StyleFixtures)
    nonisolated public init(displayText: String) {
      self.init(
        displayText: displayText,
        displayRuns: nil,
        ownerIdentity: nil,
        caretAnchor: nil
      )
    }

    /// The captured field content.
    public var body: some View {
      TextInputContent(
        displayText: displayText,
        displayRuns: displayRuns,
        ownerIdentity: ownerIdentity,
        caretAnchor: caretAnchor
      )
    }
  }

  /// The text the field shows for this pass, the prompt included.
  ///
  /// It is resolved from a presentation that does not follow the caret, so for a
  /// long value it can differ from the window ``fieldContent`` draws. Use it for
  /// measurement or decoration, and place ``fieldContent`` for the text itself.
  public var displayText: String
  /// The editable field content, placed in the body to keep editing, the caret,
  /// selection, and paste working.
  public var fieldContent: FieldContent
  /// Whether the field is showing its prompt instead of a value. The built-ins
  /// draw the content in ``placeholderStyle`` while it is true.
  public var isShowingPrompt: Bool
  /// The captured authored label, placed in the body when ``showsLabel`` is
  /// true.
  public var label: Label
  /// Whether the authored label should be rendered.
  ///
  /// It is `false` for the string-title form of ``TextField`` and true for the
  /// forms that take a label view. A style should gate ``label`` on it, as the
  /// built-ins do.
  public var showsLabel: Bool
  /// The chrome resolved for this pass: content colors taken from the field's
  /// enabled state, plus the focused border colors when the field is enabled and
  /// focused. Its `opacity` already carries the disabled dimming.
  public var chrome: ControlChrome
  /// The style for prompt text, applied by the built-ins whenever
  /// ``isShowingPrompt`` is true.
  public var placeholderStyle: AnyShapeStyle
  /// Whether the field accepts input. `chrome` already carries the disabled
  /// dimming; read this to swap content or decorations as well.
  public var isEnabled: Bool
  /// Whether the field owns keyboard focus, regardless of the focus effect.
  public var isFocused: Bool
  /// Whether the environment permits a focus treatment;
  /// `focusEffectDisabled()` clears it while the field stays focused.
  public var showsFocusEffect: Bool
  /// The resolved style environment for this pass: the theme, its semantic
  /// colors, the enablement flag, and the `controlChrome`/`rowChrome` helpers a
  /// custom style uses to match the built-in treatments.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Whether the field is focused and the focus effect is enabled.
  ///
  /// Read this rather than combining `isFocused` and `showsFocusEffect`
  /// yourself: a field under `focusEffectDisabled()` still edits from the
  /// keyboard but must not draw a focus treatment.
  public var focusActive: Bool {
    isFocused && showsFocusEffect
  }

  /// Constructs the configuration from fixture state for a style test without a
  /// live render (see <doc:Testing-Styles>).
  ///
  /// This is also the framework's own construction path, exposed to test targets
  /// through `@_spi(StyleFixtures)`; the parameters mirror the stored properties
  /// in declaration order.
  ///
  /// - Parameter fieldContent: Inert field content showing `displayText` when
  ///   omitted.
  @_spi(StyleFixtures)
  public init(
    displayText: String,
    fieldContent: FieldContent? = nil,
    isShowingPrompt: Bool,
    label: Label,
    showsLabel: Bool,
    chrome: ControlChrome,
    placeholderStyle: AnyShapeStyle,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.displayText = displayText
    self.fieldContent = fieldContent ?? FieldContent(displayText: displayText)
    self.isShowingPrompt = isShowingPrompt
    self.label = label
    self.showsLabel = showsLabel
    self.chrome = chrome
    self.placeholderStyle = placeholderStyle
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
  }

  /// Constructs a fixture from the combined focus flag this configuration
  /// carried before it gained `isEnabled`, `isFocused`, and `showsFocusEffect`.
  ///
  /// It is the earlier spelling, kept so an existing style-library test keeps
  /// compiling. `focusActive` sets `isFocused` and `showsFocusEffect` together
  /// and the field is enabled, which is what the single flag used to mean.
  /// Prefer the initializer above, which can express a focused field whose
  /// focus effect is suppressed and a disabled field.
  @_spi(StyleFixtures)
  public init(
    displayText: String,
    fieldContent: FieldContent? = nil,
    isShowingPrompt: Bool,
    label: Label,
    showsLabel: Bool,
    chrome: ControlChrome,
    placeholderStyle: AnyShapeStyle,
    focusActive: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.init(
      displayText: displayText,
      fieldContent: fieldContent,
      isShowingPrompt: isShowingPrompt,
      label: label,
      showsLabel: showsLabel,
      chrome: chrome,
      placeholderStyle: placeholderStyle,
      isEnabled: true,
      isFocused: focusActive,
      showsFocusEffect: focusActive,
      styleEnvironment: styleEnvironment
    )
  }
}

package func textInputChrome(
  styleEnvironment: StyleEnvironmentSnapshot,
  isEnabled: Bool,
  isFocused: Bool
) -> ControlChrome {
  let contentChrome = styleEnvironment.controlChrome(
    isEnabled: isEnabled,
    isFocused: false
  )
  guard isEnabled, isFocused else {
    return contentChrome
  }

  let focusChrome = styleEnvironment.controlChrome(
    isEnabled: true,
    isFocused: true
  )
  return ControlChrome(
    foregroundStyle: contentChrome.foregroundStyle,
    contentBackgroundStyle: contentChrome.contentBackgroundStyle,
    borderForegroundStyle: focusChrome.borderForegroundStyle,
    borderBackgroundStyle: focusChrome.borderBackgroundStyle,
    opacity: contentChrome.opacity
  )
}

/// Type-erased storage for a text-field style, the value the environment
/// carries.
///
/// `textFieldStyle(_:)` wraps a concrete style in this type before storing it
/// for the subtree. The built-ins are exposed as statics here, which is what lets
/// a call site write `.roundedBorder` where an `AnyTextFieldStyle` is expected.
public struct AnyTextFieldStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyTextFieldStyleBox

  /// Wraps a concrete text-field style for storage in the environment.
  ///
  /// The style's ``TextFieldStyle/snapshotLabel`` is captured here and reported
  /// as this value's description.
  ///
  /// - Parameter style: The concrete style to erase.
  public init<S: TextFieldStyle>(
    _ style: S
  ) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String {
    snapshotLabel
  }

  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String {
    snapshotLabel
  }

  /// The default text-field treatment: a fixed alias of
  /// ``AnyTextFieldStyle/roundedBorder``, not an environment-driven choice.
  public static var automatic: Self {
    Self(AutomaticTextFieldStyle())
  }

  /// A text field without chrome: the field content on its own, with the
  /// authored label stacked above it when the field has one.
  public static var plain: Self {
    Self(PlainTextFieldStyle())
  }

  /// A rounded, inset border around the padded field content, stroked heavy
  /// while the focus effect is active, reserving three cells of height plus one
  /// more when the label is shown.
  public static var roundedBorder: Self {
    Self(RoundedBorderTextFieldStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: TextFieldStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    box.resolveBody(
      configuration: configuration,
      in: context
    )
  }
}

extension AnyTextFieldStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default text-field style: a fixed alias of
/// ``RoundedBorderTextFieldStyle``.
///
/// It renders the same body as `.roundedBorder`; nothing about the treatment is
/// environment-driven. It exists so that a control with no style modifier and a
/// control written as `.textFieldStyle(.automatic)` resolve to the same
/// appearance under a distinct snapshot label.
public struct AutomaticTextFieldStyle: Sendable, TextFieldStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyTextFieldStyle.automatic"
  }

  /// Builds the rounded-border body, identical to
  /// ``RoundedBorderTextFieldStyle``.
  ///
  /// - Parameter configuration: The captured label, field content, and render
  ///   state.
  /// - Returns: The rounded-border field body.
  @MainActor
  public func makeBody(
    configuration: TextFieldStyleConfiguration
  ) -> some View {
    RoundedBorderTextFieldStyleBody(configuration: configuration)
  }
}

/// A text-field style that drops the border chrome around the field content.
///
/// The field content is drawn on its own line, in the placeholder style while
/// the prompt is showing and in the chrome's foreground style otherwise, with
/// the chrome's opacity carrying any disabled dimming. When
/// ``TextFieldStyleConfiguration/showsLabel`` is true the authored label is
/// stacked above the field in the accent border color; the style removes the
/// chrome, not the label.
public struct PlainTextFieldStyle: Sendable, TextFieldStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyTextFieldStyle.plain"
  }

  /// Builds the chrome-free body: the field content alone, or the authored label
  /// stacked above it when the field has one.
  ///
  /// - Parameter configuration: The captured label, field content, and render
  ///   state.
  /// - Returns: The chrome-free field body.
  @MainActor
  public func makeBody(
    configuration: TextFieldStyleConfiguration
  ) -> some View {
    PlainTextFieldStyleBody(configuration: configuration)
  }
}

/// A text-field style that draws rounded border chrome around the field content.
///
/// The field content is padded by one cell in each direction, filled with the
/// chrome background, and overlaid with an inset rounded border that is stroked
/// heavy while the focus effect is active. The authored label is stacked above
/// the box when ``TextFieldStyleConfiguration/showsLabel`` is true, and the body
/// reserves a minimum height of three cells plus one more for that label.
public struct RoundedBorderTextFieldStyle: Sendable, TextFieldStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyTextFieldStyle.roundedBorder"
  }

  /// Builds the bordered body: the padded field content inside a rounded border
  /// that goes heavy on focus, with the label above it when the field has one.
  ///
  /// - Parameter configuration: The captured label, field content, and render
  ///   state.
  /// - Returns: The rounded-border field body.
  @MainActor
  public func makeBody(
    configuration: TextFieldStyleConfiguration
  ) -> some View {
    RoundedBorderTextFieldStyleBody(configuration: configuration)
  }
}

private protocol AnyTextFieldStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(
    configuration: TextFieldStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyTextFieldStyleBox where S: TextFieldStyle {

  @MainActor
  func resolveBody(
    configuration: TextFieldStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

// The builtin text-field styles: stateless, so type identity settles reuse.
extension AutomaticTextFieldStyle: ReuseTransparentStyle {}
extension PlainTextFieldStyle: ReuseTransparentStyle {}
extension RoundedBorderTextFieldStyle: ReuseTransparentStyle {}

package struct PlainTextFieldStyleBody: View {
  let configuration: TextFieldStyleConfiguration

  @MainActor
  @ViewBuilder
  package var body: some View {
    let textStyle =
      configuration.isShowingPrompt
      ? configuration.placeholderStyle
      : configuration.chrome.foregroundStyle
    let field =
      configuration.fieldContent
      .fixedSize(horizontal: true, vertical: false)
      .foregroundStyle(textStyle)
      .drawMetadata(.init(opacity: configuration.chrome.opacity))

    if configuration.showsLabel {
      VStack(alignment: .leading, spacing: 0) {
        configuration.label
          .foregroundStyle(.terminalBorder(.accent))
        field
      }
    } else {
      field
    }
  }
}

package struct RoundedBorderTextFieldStyleBody: View {
  let configuration: TextFieldStyleConfiguration

  @MainActor
  @ViewBuilder
  package var body: some View {
    let textStyle =
      configuration.isShowingPrompt
      ? configuration.placeholderStyle
      : configuration.chrome.foregroundStyle
    let baseField =
      configuration.fieldContent
      .fixedSize(horizontal: true, vertical: false)
      .foregroundStyle(textStyle)
      .drawMetadata(.init(opacity: configuration.chrome.opacity))
    let field =
      HStack(alignment: .center, spacing: 0) {
        baseField
        Spacer(minLength: 0)
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(
          configuration.chrome.backgroundStyle
        )
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(
          configuration.chrome.borderStyle,
          style: configuration.focusActive ? .heavy : .init(),
          background: configuration.chrome.borderBackgroundStyle
        )
      }

    let content =
      Group {
        if configuration.showsLabel {
          VStack(alignment: .leading, spacing: 0) {
            configuration.label
              .foregroundStyle(.terminalBorder(.accent))
            field
          }
        } else {
          field
        }
      }

    content.layoutMetadata(
      .init(
        minimumHeight: (configuration.showsLabel ? 1 : 0) + 3
      )
    )
  }
}
