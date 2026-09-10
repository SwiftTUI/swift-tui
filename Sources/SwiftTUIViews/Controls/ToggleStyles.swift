public import SwiftTUICore

/// Defines the visual composition of a ``Toggle``.
///
/// A toggle style is body-producing: for every pass the primitive resolves a
/// ``ToggleStyleConfiguration`` and calls
/// ``ToggleStyle/makeBody(configuration:)``, and the returned view stands in for
/// the toggle. The configuration carries the captured authored label, the state
/// binding, and read-only render state.
///
/// The style owns appearance only. The focus stop, the activation keys and
/// pointer route, and the accessibility semantics stay with the primitive
/// whatever the style returns, and the binding writes through to the authored
/// source of truth.
///
/// Apply a style with `toggleStyle(_:)`. The value is stored in the environment
/// for the subtree, so the nearest modifier wins. The built-ins are
/// ``AnyToggleStyle/automatic`` (radio glyphs), ``AnyToggleStyle/checkbox``
/// (checkbox glyphs), and ``AnyToggleStyle/button`` (a highlighted row); each is
/// a fixed treatment rather than an alias of another built-in.
///
/// A conforming type must be a value type (a struct or an enum) and `Sendable`;
/// a class conformance does not compile.
///
/// ```swift
/// struct SwitchToggleStyle: ToggleStyle {
///   func makeBody(configuration: ToggleStyleConfiguration) -> some View {
///     HStack(spacing: 1) {
///       Text(configuration.isOn ? "[  ■]" : "[■  ]")
///         .foregroundStyle(
///           configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator)
///         )
///       configuration.label
///     }
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol ToggleStyle: Sendable {
  /// The view type this style returns for a toggle.
  associatedtype Body: View
  /// The label reported for this style in snapshots and diagnostics.
  ///
  /// The default implementation returns the reflected type name. It is
  /// diagnostic text: reuse and identity never depend on its value.
  var snapshotLabel: String { get }

  /// Builds the view that renders in the toggle's place.
  ///
  /// - Parameter configuration: The captured label, the state binding, and the
  ///   render state of this toggle.
  /// - Returns: The replacement body for the control.
  @ViewBuilder @MainActor
  func makeBody(configuration: ToggleStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _toggleStyleValueTypeWitness: Void { get }
}

extension ToggleStyle {
  /// The reflected name of the conforming type, used when a style does not
  /// supply a label of its own.
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
///
/// ``label`` is a captured authored slot: it keeps the state, environment, and
/// preferences of the scope it was written in, so it renders correctly wherever
/// the style places it. ``isOn`` is the live binding to the authored source of
/// truth. The remaining members are read-only render state the primitive
/// resolved for this pass.
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public struct ToggleStyleConfiguration: Sendable {
  /// The captured authored label.
  ///
  /// Place it in the body to render the toggle's title. Because the content
  /// keeps the scope it was authored in, its state, environment values, and
  /// preferences survive wherever the style puts it.
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

    /// The captured authored content.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The captured authored label, placed in the body to render the toggle's
  /// title.
  public var label: Label
  /// The toggle's state, as a binding to the authored source of truth.
  ///
  /// Reading it tells the style which glyph or highlight to draw; writing to it
  /// flips the control and the write reaches the authored storage, so a style
  /// can offer its own affordance for changing the value. The binding is the
  /// control's own: a style reads and writes through it but cannot substitute a
  /// different source of truth.
  @Binding public var isOn: Bool
  /// Whether the toggle should render a mixed state.
  ///
  /// Reserved. The primitive always reports `false` today, because no ``Toggle``
  /// initializer produces a mixed state; only a fixture can set it. The glyph
  /// built-ins already answer it, drawing `◐` and `⊟`.
  public var isMixed: Bool
  /// Whether the toggle accepts activation. A disabled toggle still renders,
  /// dimmed by the row chrome the built-ins resolve.
  public var isEnabled: Bool
  /// Whether the toggle owns keyboard focus, regardless of whether a focus
  /// treatment is allowed.
  public var isFocused: Bool
  /// Whether the environment permits a focus treatment; `focusEffectDisabled()`
  /// clears it while the toggle stays focused.
  public var showsFocusEffect: Bool
  /// Whether the toggle is in its pressed state for this pass.
  public var isPressed: Bool
  /// The resolved style environment for this pass: the theme, its semantic
  /// colors, the enablement flag, and the `controlChrome`/`rowChrome` helpers a
  /// custom style uses to match the built-in treatments.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Whether the toggle is focused and the focus effect is enabled.
  ///
  /// Read this rather than combining `isFocused` and `showsFocusEffect`
  /// yourself: a toggle under `focusEffectDisabled()` still flips from the
  /// keyboard but must not draw a focus treatment.
  public var focusActive: Bool { isFocused && showsFocusEffect }

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  ///
  /// This is also the framework's own construction path; the parameters mirror
  /// the stored properties in declaration order, and the `isOn` binding a
  /// fixture passes in is the one the style writes to.
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
///
/// `toggleStyle(_:)` wraps a concrete style in this type before storing it for
/// the subtree. The built-ins are exposed as statics here as well as on
/// ``ToggleStyle`` itself.
public struct AnyToggleStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyToggleStyleBox

  /// Wraps a concrete toggle style for storage in the environment.
  ///
  /// The style's ``ToggleStyle/snapshotLabel`` is captured here and reported as
  /// this value's description.
  ///
  /// - Parameter style: The concrete style to erase.
  public init<S: ToggleStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }

  /// The default toggle treatment: a radio glyph (`○` off, `◉` on, `◐` mixed)
  /// before the label on a row that highlights while focused or pressed. It is a
  /// fixed treatment, not an alias of ``AnyToggleStyle/checkbox``.
  public static var automatic: Self {
    Self(AutomaticToggleStyle())
  }
  /// The same row as ``AnyToggleStyle/automatic`` with checkbox glyphs: `☐` off,
  /// `☑` on, `⊟` mixed.
  public static var checkbox: Self {
    Self(CheckboxToggleStyle())
  }
  /// The label alone on a row with one cell of horizontal padding, highlighted
  /// while the toggle is on, focused, or pressed, and drawn with the selected
  /// row chrome while it is on.
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

/// The `automatic` treatment for ``Toggle``: a radio glyph before the label.
///
/// The row shows `○` when off, `◉` when on, and `◐` for the reserved mixed
/// state, tinted with the row chrome's border color while on and with the
/// separator color otherwise. The row carries the focus treatment while
/// ``ToggleStyleConfiguration/focusActive`` is true, and its background is
/// highlighted while the toggle is focused or pressed. The treatment is fixed,
/// not environment-driven, and it is not the checkbox glyph set.
public struct AutomaticToggleStyle: ToggleStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyToggleStyle.automatic" }

  /// Builds the glyph row with the radio glyph set.
  ///
  /// - Parameter configuration: The captured label, state binding, and render
  ///   state.
  /// - Returns: The radio-glyph toggle body.
  @MainActor
  public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    GlyphToggleStyleBody(configuration: configuration, glyphs: .radio)
  }
}

extension ToggleStyle where Self == AutomaticToggleStyle {
  /// The ``AutomaticToggleStyle`` value, so `.automatic` resolves wherever a
  /// concrete ``ToggleStyle`` is expected.
  public static var automatic: AutomaticToggleStyle { .init() }
}

extension AutomaticToggleStyle: ReuseTransparentStyle {}

/// The `checkbox` treatment for ``Toggle``: a checkbox glyph before the label.
///
/// The row is the one ``AutomaticToggleStyle`` draws, with `☐` when off, `☑`
/// when on, and `⊟` for the reserved mixed state.
public struct CheckboxToggleStyle: ToggleStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyToggleStyle.checkbox" }

  /// Builds the glyph row with the checkbox glyph set.
  ///
  /// - Parameter configuration: The captured label, state binding, and render
  ///   state.
  /// - Returns: The checkbox-glyph toggle body.
  @MainActor
  public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    GlyphToggleStyleBody(configuration: configuration, glyphs: .checkbox)
  }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
  /// The ``CheckboxToggleStyle`` value, so `.checkbox` resolves wherever a
  /// concrete ``ToggleStyle`` is expected.
  public static var checkbox: CheckboxToggleStyle { .init() }
}

extension CheckboxToggleStyle: ReuseTransparentStyle {}

/// The `button` treatment for ``Toggle``: the label alone on a highlighted row.
///
/// No glyph is drawn. The row takes one cell of horizontal padding, resolves its
/// chrome as selected while the toggle is on (or in the reserved mixed state),
/// and is highlighted while it is on, focused, or pressed.
public struct ButtonToggleStyle: ToggleStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyToggleStyle.button" }

  /// Builds the padded, highlightable label row.
  ///
  /// - Parameter configuration: The captured label, state binding, and render
  ///   state.
  /// - Returns: The button-shaped toggle body.
  @MainActor
  public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    ButtonToggleStyleBody(configuration: configuration)
  }
}

extension ToggleStyle where Self == ButtonToggleStyle {
  /// The ``ButtonToggleStyle`` value, so `.button` resolves wherever a concrete
  /// ``ToggleStyle`` is expected.
  public static var button: ButtonToggleStyle { .init() }
}

extension ButtonToggleStyle: ReuseTransparentStyle {}

private protocol AnyToggleStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(configuration: ToggleStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

extension ConcreteStyleBox: AnyToggleStyleBox where S: ToggleStyle {

  @MainActor
  func resolveBody(configuration: ToggleStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

/// The off, on, and mixed glyphs of a glyph-led toggle row.
private struct ToggleGlyphs {
  let off: String
  let on: String
  let mixed: String

  static let radio = ToggleGlyphs(off: "○", on: "◉", mixed: "◐")
  static let checkbox = ToggleGlyphs(off: "☐", on: "☑", mixed: "⊟")
}

/// The automatic and checkbox treatments: a state glyph before the label.
private struct GlyphToggleStyleBody: View {
  let configuration: ToggleStyleConfiguration
  let glyphs: ToggleGlyphs

  var body: some View {
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    ControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive,
      isHighlighted: configuration.focusActive || configuration.isPressed
    ) {
      Text(configuration.isMixed ? glyphs.mixed : configuration.isOn ? glyphs.on : glyphs.off)
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
    ControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive,
      isHighlighted: configuration.focusActive || configuration.isPressed || selected
    ) {
      configuration.label
    }
    .padding(.horizontal, 1)
  }
}
