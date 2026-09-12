public import SwiftTUICore

/// Defines the visual composition of a ``Stepper``.
///
/// A stepper style is body-producing: ``makeBody(configuration:)`` receives a
/// ``StepperStyleConfiguration`` and returns the replacement body for the
/// control. The configuration hands the style the authored label, the
/// framework-formatted value text, whether each direction can still move, the
/// enabled, focus, and press state, and the
/// ``StepperStyleConfiguration/decrement(content:)`` and
/// ``StepperStyleConfiguration/increment(content:)`` route wrappers for the
/// primitive's two pointer targets.
///
/// The primitive keeps what makes the control a stepper: its focus stop, the
/// value binding, clamping and step rounding, arrow-key and wheel adjustment,
/// Space activation, and the accessibility role. The configuration exposes no
/// binding, so a style never writes the value.
///
/// Two built-ins ship. ``AutomaticStepperStyle`` draws triangle controls
/// around the value with a focus rail, and ``CompactStepperStyle`` draws minus
/// and plus without the rail. Apply either with `stepperStyle(_:)`,
/// which stores the style in the environment for its subtree; the nearest
/// modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform.
///
/// ```swift
/// struct WordStepperStyle: StepperStyle {
///   func makeBody(configuration: StepperStyleConfiguration) -> some View {
///     HStack(spacing: 1) {
///       configuration.label
///       configuration.decrement {
///         Text(configuration.canDecrement ? "[less]" : "[    ]")
///       }
///       configuration.valueLabel
///       configuration.increment {
///         Text(configuration.canIncrement ? "[more]" : "[    ]")
///       }
///     }
///   }
/// }
///
/// Stepper("Replicas", value: $replicas, in: 1...9)
///   .stepperStyle(WordStepperStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol StepperStyle: Sendable {
  /// The view type ``makeBody(configuration:)`` returns.
  associatedtype Body: View
  /// The label this style reports in snapshots, debug bundles, and style
  /// runtime issues.
  ///
  /// The default implementation reflects the conforming type's name; the
  /// built-ins pin their own, such as `"AnyStepperStyle.compact"`. It is
  /// diagnostic text, not identity: do not branch on it.
  var snapshotLabel: String { get }
  /// Composes the captured content and render state of a stepper into its
  /// rendered body.
  ///
  /// Runs on the main actor once per resolve of the styled control.
  ///
  /// - Parameter configuration: The captured label and value label, the
  ///   adjustment availability of each direction, the control's interaction
  ///   state, and the two action route wrappers.
  /// - Returns: The replacement body for the control.
  @ViewBuilder @MainActor
  func makeBody(configuration: StepperStyleConfiguration) -> Body
  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _stepperStyleValueTypeWitness: Void { get }
}

extension StepperStyle {
  /// The reflected name of the conforming type, used unless the style pins a
  /// label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }
  @_documentation(visibility: internal)
  public static var _stepperStyleValueTypeWitness: Void { () }
}

extension StepperStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message: "SwiftTUI styles must be value types; a class cannot conform to StepperStyle"
  )
  public static var _stepperStyleValueTypeWitness: Void { () }
}

/// Authored content, normalized state, and primitive-owned routes for a ``StepperStyle``.
///
/// The members fall into two groups. ``Label`` and ``ValueLabel`` are captured
/// authored slots: placing one in the style body renders the authored content
/// with the state and scope it was declared in. Everything else is read-only
/// render state the primitive computed for this resolve, including whether
/// each direction can still move and the enabled, focus, and press flags.
///
/// A stepper models its value on a binding, but no binding reaches the style.
/// The value moves only through the primitive's own keyboard and wheel
/// handling and through the two pointer routes the configuration installs.
public struct StepperStyleConfiguration: Sendable {
  /// Captured authored label content.
  ///
  /// Place it in the style body to render the stepper's title; the authored
  /// content keeps its own state and authoring scope wherever it is placed.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload
    package init<V: View>(
      authoringContext: AuthoringContext?, @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }
    /// Captures `content` as the authored label of a fixture-constructed
    /// configuration for a style test (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }
    /// The captured authored content.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// Captured framework-formatted value content.
  ///
  /// The primitive formats the current value for its `Int` or `Double`
  /// storage and captures it as a ``Text``; a style places the slot rather
  /// than formatting the value itself.
  public struct ValueLabel: View, Sendable {
    package let payload: CapturedSubviewPayload
    package init<V: View>(
      authoringContext: AuthoringContext?, @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }
    /// Captures `content` as the value text of a fixture-constructed
    /// configuration for a style test (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }
    /// The captured authored content.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The captured authored label, placed in the body to render the stepper's title.
  public var label: Label
  /// The captured value text the primitive formatted for the current value.
  ///
  /// An `Int` stepper prints the integer; a `Double` stepper prints the value
  /// clamped to the bounds, rounded to the step, and trimmed of trailing
  /// zeros.
  public var valueLabel: ValueLabel
  /// Whether one step would lower the value, that is whether the value is off
  /// the lower bound.
  ///
  /// The built-ins draw the decrement affordance in the placeholder paint when
  /// it is `false`, and the route content is disabled with it.
  public var canDecrement: Bool
  /// Whether one step would raise the value, that is whether the value is off
  /// the upper bound.
  ///
  /// The built-ins draw the increment affordance in the placeholder paint when
  /// it is `false`, and the route content is disabled with it.
  public var canIncrement: Bool
  /// Whether the control is interactive.
  ///
  /// A disabled stepper registers no handlers, and the content passed to
  /// either action wrapper is disabled with it.
  public var isEnabled: Bool
  /// Whether the stepper is the focused control.
  ///
  /// Prefer ``focusActive`` when deciding whether to draw a focus treatment:
  /// a control under `focusEffectDisabled()` is still focused for keyboard
  /// purposes but must not show one.
  public var isFocused: Bool
  /// Whether the focus treatment is enabled in this subtree.
  ///
  /// It is `false` under `focusEffectDisabled()`, where the control still
  /// takes keyboard focus.
  public var showsFocusEffect: Bool
  /// Whether a pointer press is currently held on the stepper, including a
  /// press on either action half.
  public var isPressed: Bool
  /// The `StyleEnvironmentSnapshot` for this resolve: the terminal
  /// appearance, the active theme, the ambient foreground and tint paints,
  /// the enabled state, and the cell metrics.
  ///
  /// Built-in bodies take every paint from it, through `rowChrome(...)` and
  /// `controlChrome(...)`; a custom style can call the same helpers to match.
  public var styleEnvironment: StyleEnvironmentSnapshot
  /// Whether the stepper is focused and the focus effect is enabled.
  ///
  /// This is the flag a style should draw a focus treatment from.
  public var focusActive: Bool { isFocused && showsFocusEffect }
  private var decrementIdentity: Identity?
  private var incrementIdentity: Identity?

  /// Constructs the configuration from fixture state for a style test without
  /// a live render (see <doc:Testing-Styles>).
  ///
  /// The arguments follow this type's stored-property declaration order. Both
  /// action routes of a fixture-constructed configuration are inert: they
  /// render their content and install nothing.
  @_spi(StyleFixtures)
  public init(
    label: Label,
    valueLabel: ValueLabel,
    canDecrement: Bool,
    canIncrement: Bool,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.valueLabel = valueLabel
    self.canDecrement = canDecrement
    self.canIncrement = canIncrement
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.styleEnvironment = styleEnvironment
    decrementIdentity = nil
    incrementIdentity = nil
  }

  /// Installs the primitive's decrement pointer target. Install once; fixture routes are inert.
  ///
  /// A press inside the wrapped view lowers the value by one step. The half
  /// claims its press and its release even at the lower bound, so a pointer
  /// on a spent decrement cannot fall through to the stepper's own activation
  /// action. The framework supplies the route identity, and the content is
  /// disabled when the control is disabled or ``canDecrement`` is `false`.
  ///
  /// Installing the route twice in one body reports `style.duplicateRoute`;
  /// the first installation stays the target. Omitting the wrapper removes
  /// only the pointer target: arrow keys, the wheel, and Space stay with the
  /// primitive.
  ///
  /// - Parameter content: The view the style composes for the decrement half.
  /// - Returns: That content wrapped in the decrement pointer route.
  @ViewBuilder @MainActor
  public func decrement<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    actionRoute(
      identity: decrementIdentity, role: "decrement", canAdjust: canDecrement, content: content)
  }

  /// Installs the primitive's increment pointer target. Install once; fixture routes are inert.
  ///
  /// A press inside the wrapped view raises the value by one step. The half
  /// claims its press and its release even at the upper bound, so a pointer
  /// on a spent increment cannot fall through to the stepper's own activation
  /// action. The framework supplies the route identity, and the content is
  /// disabled when the control is disabled or ``canIncrement`` is `false`.
  ///
  /// Installing the route twice in one body reports `style.duplicateRoute`;
  /// the first installation stays the target. Omitting the wrapper removes
  /// only the pointer target: arrow keys, the wheel, and Space stay with the
  /// primitive.
  ///
  /// - Parameter content: The view the style composes for the increment half.
  /// - Returns: That content wrapped in the increment pointer route.
  @ViewBuilder @MainActor
  public func increment<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    actionRoute(
      identity: incrementIdentity, role: "increment", canAdjust: canIncrement, content: content)
  }

  /// One action half. The content receives the half's disabled state on both
  /// the live and the fixture path, so a style body that reads `isEnabled`
  /// renders the same way under test as it does in a live control.
  @ViewBuilder @MainActor
  private func actionRoute<Content: View>(
    identity: Identity?, role: String, canAdjust: Bool, content: () -> Content
  ) -> some View {
    let content = content().disabled(!isEnabled || !canAdjust)
    styleRoute(
      target: identity.map { identity in
        StyleRouteTarget(identity: identity, family: "StepperStyle", role: role)
      }, content: content)
  }

  mutating func bindRoutes(to identity: Identity) {
    decrementIdentity = stepperDecrementIdentity(for: identity)
    incrementIdentity = stepperIncrementIdentity(for: identity)
  }
}

/// Type-erased storage for a concrete ``StepperStyle``, the value the environment carries.
public struct AnyStepperStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyStepperStyleBox
  /// Wraps a concrete stepper style for the environment.
  ///
  /// The generic `stepperStyle(_:)` overload calls this for you.
  ///
  /// - Parameter style: The style to erase.
  public init<S: StepperStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }
  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }
  /// The ``AutomaticStepperStyle`` treatment: triangle controls around the
  /// value, with a focus rail.
  public static var automatic: Self {
    Self(AutomaticStepperStyle())
  }
  /// The ``CompactStepperStyle`` treatment: minus and plus around the value,
  /// with no focus rail.
  public static var compact: Self {
    Self(CompactStepperStyle())
  }
  @MainActor
  package func resolveBody(configuration: StepperStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
  {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyStepperStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``Stepper``: triangle controls around the
/// value, on a row that reserves a focus rail.
///
/// The row keeps a leading cell for the rail and draws it in the theme's
/// border paint while the focus effect is active. The halves print `◀` and
/// `▶` while that direction can still move and the hollow `◁` and `▷` at a
/// bound, where they also take the placeholder paint. While the control is
/// focused or pressed, the controls and value take the control chrome's
/// paints over a filled background. The label uses the theme's accent border
/// role, and the row honors the chrome's disabled opacity.
///
/// It is not an alias: ``CompactStepperStyle`` renders a different row.
public struct AutomaticStepperStyle: StepperStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyStepperStyle.automatic" }
  /// Composes the label, the triangle halves inside their action routes, and
  /// the value into one row with a focus rail.
  ///
  /// - Parameter configuration: The stepper's captured content and render state.
  /// - Returns: The railed triangle row for the control.
  @MainActor
  public func makeBody(configuration: StepperStyleConfiguration) -> some View {
    AutomaticStepperStyleBody(configuration: configuration)
  }
}
extension StepperStyle where Self == AutomaticStepperStyle {
  /// The automatic stepper treatment, spelled `.automatic` wherever a
  /// ``StepperStyle`` is expected.
  public static var automatic: AutomaticStepperStyle { .init() }
}
extension AutomaticStepperStyle: ReuseTransparentStyle {}

/// The `compact` treatment for ``Stepper``: minus and plus around the value,
/// on a row with no focus rail.
///
/// The halves print `−` and `+` regardless of direction, taking the
/// placeholder paint at a bound, and the row reserves no leading cell, so the
/// label starts at the row's edge and no rail ever appears. Focus and press
/// still tint the controls and value and fill the row background from the
/// control chrome.
public struct CompactStepperStyle: StepperStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyStepperStyle.compact" }
  /// Composes the label, the minus and plus halves inside their action
  /// routes, and the value into one railless row.
  ///
  /// - Parameter configuration: The stepper's captured content and render state.
  /// - Returns: The compact row for the control.
  @MainActor
  public func makeBody(configuration: StepperStyleConfiguration) -> some View {
    CompactStepperStyleBody(configuration: configuration)
  }
}
extension StepperStyle where Self == CompactStepperStyle {
  /// The compact stepper treatment, spelled `.compact` wherever a
  /// ``StepperStyle`` is expected.
  public static var compact: CompactStepperStyle { .init() }
}
extension CompactStepperStyle: ReuseTransparentStyle {}

private struct AutomaticStepperStyleBody: View {
  let configuration: StepperStyleConfiguration
  var body: some View { StepperStyleRow(configuration: configuration, compact: false) }
}

private struct CompactStepperStyleBody: View {
  let configuration: StepperStyleConfiguration
  var body: some View { StepperStyleRow(configuration: configuration, compact: true) }
}

private struct StepperStyleRow: View {
  let configuration: StepperStyleConfiguration
  let compact: Bool
  var body: some View {
    let active = configuration.focusActive || configuration.isPressed
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let contentChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let accent = active ? contentChrome.borderStyle : AnyShapeStyle(.separator)
    ControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive,
      isHighlighted: active, reservesRail: !compact
    ) {
      configuration.label.foregroundStyle(.terminalBorder(.accent))
      HStack(alignment: .center, spacing: 1) {
        configuration.decrement {
          Text(compact ? "−" : configuration.canDecrement ? "◀" : "◁")
            .foregroundStyle(configuration.canDecrement ? accent : AnyShapeStyle(.placeholder))
        }
        configuration.valueLabel.foregroundStyle(
          active ? contentChrome.foregroundStyle : chrome.foregroundStyle)
        configuration.increment {
          Text(compact ? "+" : configuration.canIncrement ? "▶" : "▷")
            .foregroundStyle(configuration.canIncrement ? accent : AnyShapeStyle(.placeholder))
        }
      }
      .opacity(contentChrome.opacity)
      .background {
        if active { Rectangle().fill(contentChrome.backgroundStyle) }
      }
    }
  }
}

private protocol AnyStepperStyleBox: AnyStyleBox {
  @MainActor
  func resolveBody(configuration: StepperStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
}
extension ConcreteStyleBox: AnyStepperStyleBox where S: StepperStyle {
  @MainActor
  func resolveBody(configuration: StepperStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
  {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}
