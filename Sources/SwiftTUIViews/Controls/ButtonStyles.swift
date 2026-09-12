public import SwiftTUICore

/// Composes the authored label and render state of a button into its rendered body.
///
/// A button style is body-producing: for every pass the primitive resolves a
/// ``ButtonStyleConfiguration`` and calls ``ButtonStyle/makeBody(configuration:)``,
/// and the returned view stands in for the button. The configuration carries the
/// captured authored label plus read-only render state: the role, enablement,
/// focus, press state, the resolved control prominence, the requested border
/// shape, and a snapshot of the resolved style environment.
///
/// The style owns appearance only. The focus stop, the action dispatch, key and
/// pointer handling, and the accessibility semantics stay with the primitive
/// whatever the style returns, so a body that drops
/// ``ButtonStyleConfiguration/label`` loses the title and nothing else.
///
/// Apply a style with `buttonStyle(_:)`. The value is stored in the environment
/// for the subtree, so the nearest modifier wins. The built-ins are
/// ``AnyButtonStyle/automatic``, ``AnyButtonStyle/plain``,
/// ``AnyButtonStyle/bordered``, ``AnyButtonStyle/borderedProminent``, and
/// ``AnyButtonStyle/link``. Unlike the other control families, `.automatic` is
/// not an alias of another built-in: it is a fixed dense, filled treatment of
/// its own.
///
/// A conforming type must be a value type (a struct or an enum) and `Sendable`;
/// a class conformance does not compile.
///
/// ```swift
/// struct BracketButtonStyle: ButtonStyle {
///   func makeBody(configuration: ButtonStyleConfiguration) -> some View {
///     HStack(spacing: 0) {
///       Text(configuration.focusActive ? "▶ [" : "  [")
///       configuration.label
///       Text("]")
///     }
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol ButtonStyle: Sendable {
  /// The view type this style returns for a button.
  associatedtype Body: View

  /// The label reported for this style in snapshots and diagnostics.
  ///
  /// The default implementation returns the reflected type name. It is
  /// diagnostic text: reuse and identity never depend on its value.
  var snapshotLabel: String { get }

  /// Maps the inherited control prominence to the prominence the button renders
  /// with.
  ///
  /// The primitive calls this before it builds the configuration, so
  /// ``ButtonStyleConfiguration/controlProminence`` already carries the returned
  /// value and a style that overrides this requirement reads back its own
  /// answer. The default implementation returns `base` unchanged;
  /// ``BorderedProminentButtonStyle`` returns `.increased` regardless of `base`.
  ///
  /// - Parameter base: The prominence inherited from the environment.
  /// - Returns: The prominence reported to the style and to the chrome helpers.
  @MainActor
  func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence

  /// Builds the view that renders in the button's place.
  ///
  /// - Parameter configuration: The captured label and render state of this
  ///   button.
  /// - Returns: The replacement body for the control.
  @ViewBuilder @MainActor
  func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> Body

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _buttonStyleValueTypeWitness: Void { get }
}

extension ButtonStyle {
  @_documentation(visibility: internal)
  public static var _buttonStyleValueTypeWitness: Void { () }
}

extension ButtonStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI button styles must be value types (a struct or an enum); a class cannot conform to ButtonStyle"
  )
  public static var _buttonStyleValueTypeWitness: Void { () }
}

extension ButtonStyle {
  /// The reflected name of the conforming type, used when a style does not
  /// supply a label of its own.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }

  /// Leaves the inherited prominence unchanged.
  ///
  /// - Parameter base: The prominence inherited from the environment.
  /// - Returns: `base`.
  @MainActor
  public func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence {
    base
  }
}

/// The captured label and render state a ``ButtonStyle`` composes into a body.
///
/// The members fall into two groups. ``label`` is a captured authored slot: a
/// view that still carries the state, environment, and preferences of the scope
/// it was written in, so placing it anywhere in the style's body renders the
/// authored title correctly. Everything else is read-only render state the
/// primitive resolved for this pass; the properties are `var` so a style can
/// copy and adjust a configuration for a nested style, but writing to a copy
/// never changes the control.
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public struct ButtonStyleConfiguration: Sendable {
  /// The authored label of the button, captured with its authoring scope.
  ///
  /// Place it in the body to render the title. Because the content keeps the
  /// scope it was authored in, its state, environment values, and preferences
  /// survive wherever the style puts it.
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

  /// The captured authored label, placed in the body to render the button's
  /// title.
  public var label: Label
  /// The authored role, or `nil` when the button has none.
  ///
  /// The built-ins map it to theme colors: `.destructive` to the danger color,
  /// `.cancel` and `.close` to the muted color, and `.confirm` to the tint.
  public var role: ButtonRole?
  /// Whether the button accepts activation.
  ///
  /// A disabled button still renders. The built-ins draw it in the placeholder
  /// color and carry a dimming opacity in the chrome they resolve.
  public var isEnabled: Bool
  /// Whether the button owns keyboard focus, regardless of whether a focus
  /// treatment is allowed.
  public var isFocused: Bool
  /// Whether the environment permits a focus treatment; `focusEffectDisabled()`
  /// clears it while the button stays focused.
  public var showsFocusEffect: Bool
  /// Whether the button is in its pressed state for this pass.
  public var isPressed: Bool
  /// The prominence the button renders with.
  ///
  /// The primitive has already passed the inherited value through
  /// ``ButtonStyle/resolvedProminence(base:)``, so a style that raises
  /// prominence reads its own raised value here. The built-in chrome uses it to
  /// pick between the standard and the filled, increased treatment.
  public var controlProminence: ControlProminence
  /// The border shape requested for the button.
  ///
  /// The built-in chrome consults it together with ``controlProminence``:
  /// `.roundedRectangle` always rounds the background and border, while
  /// `.automatic` rounds only at increased prominence and is square otherwise.
  public var buttonBorderShape: ButtonBorderShape
  /// The resolved style environment for this pass: the theme, its semantic
  /// colors, the enablement flag, and the `controlChrome`/`rowChrome` helpers a
  /// custom style uses to match the built-in treatments.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Whether the button is focused and the focus effect is enabled.
  ///
  /// Read this rather than combining ``isFocused`` and ``showsFocusEffect``
  /// yourself: a button under `focusEffectDisabled()` still activates from the
  /// keyboard but must not draw a focus treatment.
  public var focusActive: Bool {
    isFocused && showsFocusEffect
  }

  /// Constructs the configuration from fixture state for a style test without a
  /// live render (see <doc:Testing-Styles>).
  ///
  /// This is also the framework's own construction path, exposed to test
  /// targets through `@_spi(StyleFixtures)`; the parameters mirror the stored
  /// properties in declaration order.
  @_spi(StyleFixtures)
  public init(
    label: Label,
    role: ButtonRole?,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    controlProminence: ControlProminence,
    buttonBorderShape: ButtonBorderShape,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.role = role
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.controlProminence = controlProminence
    self.buttonBorderShape = buttonBorderShape
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a button style, the value the environment carries.
///
/// `buttonStyle(_:)` wraps a concrete style in this type before storing it for
/// the subtree. The built-ins are exposed as statics here, which is what lets a
/// call site write `.bordered` where an `AnyButtonStyle` is expected.
public struct AnyButtonStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyButtonStyleBox

  /// Wraps a concrete button style for storage in the environment.
  ///
  /// The style's ``ButtonStyle/snapshotLabel`` is captured here and reported as
  /// this value's description.
  ///
  /// - Parameter style: The concrete style to erase.
  public init<S: ButtonStyle>(
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

  /// The default button treatment: a dense, filled body drawn with the
  /// increased-prominence chrome tone.
  ///
  /// It is a fixed treatment, not an environment-driven choice and not an alias
  /// of another built-in. It draws no border overlay and no focus rail, so focus
  /// shows as a change of fill color, and it does not raise
  /// ``ButtonStyleConfiguration/controlProminence``.
  public static var automatic: Self {
    Self(AutomaticButtonStyle())
  }

  /// A borderless treatment: the label over the theme background, with a
  /// leading focus rail whose gutter stays reserved while the rail is hidden so
  /// the button's width does not change when focus arrives.
  public static var plain: Self {
    Self(PlainButtonStyle())
  }

  /// A bordered treatment: one cell of padding around the label, a minimum
  /// height of three cells, and a border overlay that switches to a heavy stroke
  /// while the focus effect is active. It renders at the inherited prominence.
  public static var bordered: Self {
    Self(BorderedButtonStyle())
  }

  /// A bordered treatment that raises prominence: it reports `.increased` from
  /// ``ButtonStyle/resolvedProminence(base:)`` and renders the same dense,
  /// filled body as ``AnyButtonStyle/automatic``, so focus shows as a change of
  /// fill rather than a border.
  public static var borderedProminent: Self {
    Self(BorderedProminentButtonStyle())
  }

  /// A link-shaped treatment: the label underlined in the theme's link color
  /// over a row background that fills while focused or pressed, with the same
  /// reserved focus rail as ``AnyButtonStyle/plain``.
  public static var link: Self {
    Self(LinkButtonStyle())
  }

  @MainActor
  package func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence {
    box.resolvedProminence(base: base)
  }

  @MainActor
  package func resolveBody(
    configuration: ButtonStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    box.resolveBody(
      configuration: configuration,
      in: context
    )
  }
}

extension AnyButtonStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default button style: a dense, filled body drawn with the
/// increased-prominence chrome tone.
///
/// The treatment is fixed rather than environment-driven, and it is not an alias
/// of any other built-in. It fills the label's cells with the resolved chrome
/// background, adds one cell of horizontal padding, draws no border overlay and
/// no focus rail, and leaves ``ButtonStyleConfiguration/controlProminence``
/// alone. Focus, idle, and pressed therefore differ only in fill color.
public struct AutomaticButtonStyle: Sendable, ButtonStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyButtonStyle.automatic"
  }

  /// Builds the dense body: the label with one cell of horizontal padding over
  /// the increased-prominence chrome fill, without a border overlay or a focus
  /// rail.
  ///
  /// - Parameter configuration: The captured label and render state.
  /// - Returns: The filled button body.
  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonChromeStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .automatic,
        configuration: configuration
      ),
      controlProminence: configuration.controlProminence,
      buttonBorderShape: configuration.buttonBorderShape,
      usesDenseBorderlessChrome: true,
      verticalPadding: 0,
      needsMinimumHeight: false,
      focusActive: configuration.focusActive
    )
  }
}

/// A minimal button style without surrounding border chrome.
///
/// The label is drawn over the theme background in the role's foreground color,
/// preceded by a focus rail. The rail's gutter stays reserved while the rail is
/// hidden, so focus does not change the button's width, and a disabled button
/// uses the placeholder color with the chrome's dimming opacity.
public struct PlainButtonStyle: Sendable, ButtonStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyButtonStyle.plain"
  }

  /// Builds the borderless body: a focus rail followed by the label, tinted and
  /// dimmed by the resolved plain chrome.
  ///
  /// - Parameter configuration: The captured label and render state.
  /// - Returns: The borderless button body.
  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonPlainStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .plain,
        configuration: configuration
      ),
      focusActive: configuration.focusActive
    )
  }
}

/// A bordered button style that reserves terminal-cell chrome around the label.
///
/// The label sits inside one cell of horizontal and vertical padding, the body
/// reserves a minimum height of three cells, and a border overlay is stroked
/// around it: a light stroke normally and a heavy stroke while the focus effect
/// is active. The corners follow ``ButtonStyleConfiguration/buttonBorderShape``.
public struct BorderedButtonStyle: Sendable, ButtonStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyButtonStyle.bordered"
  }

  /// Builds the bordered body: the padded label over the standard-prominence
  /// chrome fill, with a border overlay that goes heavy on focus and a minimum
  /// height of three cells.
  ///
  /// - Parameter configuration: The captured label and render state.
  /// - Returns: The bordered button body.
  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonChromeStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .bordered,
        configuration: configuration
      ),
      controlProminence: configuration.controlProminence,
      buttonBorderShape: configuration.buttonBorderShape,
      usesDenseBorderlessChrome: false,
      verticalPadding: 1,
      needsMinimumHeight: true,
      focusActive: configuration.focusActive
    )
  }
}

/// A bordered button style with increased control prominence.
///
/// It raises prominence through ``resolvedProminence(base:)`` and then renders
/// the same dense, filled body as ``AutomaticButtonStyle``: rounded corners at
/// increased prominence, no border overlay, and no focus rail, so focus reads as
/// a change of fill color.
public struct BorderedProminentButtonStyle: Sendable, ButtonStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyButtonStyle.borderedProminent"
  }

  /// Reports `.increased` whatever the environment inherited, so both this
  /// style's chrome and ``ButtonStyleConfiguration/controlProminence`` describe
  /// the raised level.
  ///
  /// - Parameter base: The inherited prominence, ignored.
  /// - Returns: `.increased`.
  @MainActor
  public func resolvedProminence(
    base _: ControlProminence
  ) -> ControlProminence {
    .increased
  }

  /// Builds the dense, filled body at increased prominence, without a border
  /// overlay or a focus rail.
  ///
  /// - Parameter configuration: The captured label and render state.
  /// - Returns: The prominent button body.
  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonChromeStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .borderedProminent,
        configuration: configuration
      ),
      controlProminence: configuration.controlProminence,
      buttonBorderShape: configuration.buttonBorderShape,
      usesDenseBorderlessChrome: true,
      verticalPadding: 0,
      needsMinimumHeight: false,
      focusActive: configuration.focusActive
    )
  }
}

/// A link-shaped button style for navigation or external-link actions.
///
/// The label is underlined and drawn in the theme's link color, or in the role's
/// color when the button has one, over a row background that fills while the
/// button is focused or pressed. It keeps the reserved focus rail of
/// ``PlainButtonStyle``. Styling a ``Link`` needs ``LinkStyle`` instead; a
/// `Link` never reads the button style.
public struct LinkButtonStyle: Sendable, ButtonStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyButtonStyle.link"
  }

  /// Builds the link-shaped body: the underlined label with a focus rail over a
  /// background that fills while focused or pressed.
  ///
  /// - Parameter configuration: The captured label and render state.
  /// - Returns: The link-shaped button body.
  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonLinkStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .link,
        configuration: configuration
      ),
      focusActive: configuration.focusActive
    )
  }
}

private protocol AnyButtonStyleBox: AnyStyleBox {

  @MainActor
  func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence

  @MainActor
  func resolveBody(
    configuration: ButtonStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyButtonStyleBox where S: ButtonStyle {

  @MainActor
  func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence {
    style.resolvedProminence(base: base)
  }

  @MainActor
  func resolveBody(
    configuration: ButtonStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

// The builtin button styles: stateless, so type identity settles reuse.
extension AutomaticButtonStyle: ReuseTransparentStyle {}
extension PlainButtonStyle: ReuseTransparentStyle {}
extension BorderedButtonStyle: ReuseTransparentStyle {}
extension BorderedProminentButtonStyle: ReuseTransparentStyle {}
extension LinkButtonStyle: ReuseTransparentStyle {}
