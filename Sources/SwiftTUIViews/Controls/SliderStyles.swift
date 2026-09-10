public import SwiftTUICore

/// Defines the visual composition of a ``Slider``.
///
/// A slider style is body-producing: ``makeBody(configuration:)`` receives a
/// ``SliderStyleConfiguration`` and returns the replacement body for the
/// control. The configuration hands the style the authored label, the
/// framework-formatted value text, the normalized
/// ``SliderStyleConfiguration/fractionCompleted``, the track cell count, the
/// enabled, focus, and press state, and the
/// ``SliderStyleConfiguration/track(content:)`` route wrapper for the
/// primitive's pointer target.
///
/// The primitive keeps what makes the control a slider: its focus stop, the
/// value binding, clamping and step rounding, arrow-key and wheel adjustment,
/// Space activation, and the accessibility role. The configuration exposes no
/// binding, so a style never writes the value.
///
/// Two built-ins ship. ``LinearSliderStyle`` draws a labelled row with a
/// position marker on a track, and ``AutomaticSliderStyle`` is a fixed alias
/// of it. Apply either with `sliderStyle(_:)`, which stores the style
/// in the environment for its subtree; the nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform.
///
/// ```swift
/// struct BlockSliderStyle: SliderStyle {
///   func makeBody(configuration: SliderStyleConfiguration) -> some View {
///     let width = configuration.trackCellCount
///     let filled = Int((configuration.fractionCompleted * Double(width)).rounded())
///     return HStack(spacing: 1) {
///       configuration.label
///       configuration.track {
///         Text(
///           String(repeating: "█", count: filled)
///             + String(repeating: "░", count: width - filled))
///       }
///       configuration.valueLabel
///     }
///   }
/// }
///
/// Slider("Canary", value: $canary, in: 0...1)
///   .sliderStyle(BlockSliderStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol SliderStyle: Sendable {
  /// The view type ``makeBody(configuration:)`` returns.
  associatedtype Body: View
  /// The label this style reports in snapshots, debug bundles, and style
  /// runtime issues.
  ///
  /// The default implementation reflects the conforming type's name; the
  /// built-ins pin their own, such as `"AnySliderStyle.linear"`. It is
  /// diagnostic text, not identity: do not branch on it.
  var snapshotLabel: String { get }
  /// Composes the captured content and render state of a slider into its
  /// rendered body.
  ///
  /// Runs on the main actor once per resolve of the styled control.
  ///
  /// - Parameter configuration: The captured label and value label, the
  ///   normalized fraction and preferred track width, the control's
  ///   interaction state, and the track route wrapper.
  /// - Returns: The replacement body for the control.
  @ViewBuilder @MainActor
  func makeBody(configuration: SliderStyleConfiguration) -> Body
  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _sliderStyleValueTypeWitness: Void { get }
}

extension SliderStyle {
  /// The reflected name of the conforming type, used unless the style pins a
  /// label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }
  @_documentation(visibility: internal)
  public static var _sliderStyleValueTypeWitness: Void { () }
}

extension SliderStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message: "SwiftTUI styles must be value types; a class cannot conform to SliderStyle"
  )
  public static var _sliderStyleValueTypeWitness: Void { () }
}

/// Authored content, normalized state, and primitive-owned routes for a ``SliderStyle``.
///
/// The members fall into two groups. ``Label`` and ``ValueLabel`` are captured
/// authored slots: placing one in the style body renders the authored content
/// with the state and scope it was declared in. Everything else is read-only
/// render state the primitive computed for this resolve, including the
/// normalized fraction, the preferred track width, and the enabled, focus,
/// press, and adjustability flags.
///
/// A slider models its value on a binding, but no binding reaches the style.
/// The value moves only through the primitive's own keyboard and wheel
/// handling and through the pointer route that
/// ``SliderStyleConfiguration/track(content:)`` installs.
public struct SliderStyleConfiguration: Sendable {
  /// Captured authored label content.
  ///
  /// Place it in the style body to render the slider's title; the authored
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

  /// The captured authored label, placed in the body to render the slider's title.
  public var label: Label
  /// The captured value text the primitive formatted for the current value.
  ///
  /// An `Int` slider prints the integer; a `Double` slider prints the value
  /// clamped to the bounds, rounded to the step, and trimmed of trailing
  /// zeros.
  public var valueLabel: ValueLabel
  /// The current value's position in the slider's bounds, normalized to `0...1`.
  ///
  /// The live path clamps the fraction and substitutes zero for a value that
  /// is not finite. A fixture may supply any `Double`, so a style that
  /// derives a cell index from it should clamp the result as the built-in
  /// does.
  public var fractionCompleted: Double
  /// The track width in terminal cells the primitive prefers.
  ///
  /// It is currently the constant `8`: nothing authored or environmental
  /// changes it. A style may draw any width inside
  /// ``track(content:)``, and the pointer mapping follows the width the style
  /// actually renders.
  public var trackCellCount: Int
  /// Whether the control is interactive.
  ///
  /// A disabled slider registers no handlers, and the content passed to
  /// ``track(content:)`` is disabled with it.
  public var isEnabled: Bool
  /// Whether the slider is the focused control.
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
  /// Whether a pointer press is currently held on the slider, including a
  /// press or drag on the track route.
  public var isPressed: Bool
  /// Whether one adjustment step would lower the value, that is whether the
  /// value is off the lower bound.
  public var canDecrement: Bool
  /// Whether one adjustment step would raise the value, that is whether the
  /// value is off the upper bound.
  public var canIncrement: Bool
  /// The `StyleEnvironmentSnapshot` for this resolve: the terminal
  /// appearance, the active theme, the ambient foreground and tint paints,
  /// the enabled state, and the cell metrics.
  ///
  /// Built-in bodies take every paint from it, through `rowChrome(...)` and
  /// `controlChrome(...)`; a custom style can call the same helpers to match.
  public var styleEnvironment: StyleEnvironmentSnapshot
  /// Whether the slider is focused and the focus effect is enabled.
  ///
  /// This is the flag a style should draw a focus treatment from.
  public var focusActive: Bool { isFocused && showsFocusEffect }
  private var trackIdentity: Identity?

  /// Constructs the configuration from fixture state for a style test without
  /// a live render (see <doc:Testing-Styles>).
  ///
  /// This overload takes `canDecrement` and `canIncrement` before the
  /// interaction flags, the order ``StepperStyleConfiguration`` declares them
  /// in, so a test can spell both value-control fixtures the same way. It
  /// forwards to the overload below; the two differ only in argument order.
  @_spi(StyleFixtures)
  public init(
    label: Label, valueLabel: ValueLabel, fractionCompleted: Double, trackCellCount: Int,
    canDecrement: Bool, canIncrement: Bool, isEnabled: Bool, isFocused: Bool,
    showsFocusEffect: Bool, isPressed: Bool, styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.init(
      label: label, valueLabel: valueLabel, fractionCompleted: fractionCompleted,
      trackCellCount: trackCellCount, isEnabled: isEnabled, isFocused: isFocused,
      showsFocusEffect: showsFocusEffect, isPressed: isPressed,
      canDecrement: canDecrement, canIncrement: canIncrement, styleEnvironment: styleEnvironment)
  }

  /// Constructs the configuration from fixture state for a style test without
  /// a live render (see <doc:Testing-Styles>).
  ///
  /// The arguments follow this type's stored-property declaration order, with
  /// the adjustment flags after `isPressed`. Both overloads build the same
  /// value, and the track route of a fixture-constructed configuration is
  /// inert.
  @_spi(StyleFixtures)
  public init(
    label: Label,
    valueLabel: ValueLabel,
    fractionCompleted: Double,
    trackCellCount: Int,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    canDecrement: Bool,
    canIncrement: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.valueLabel = valueLabel
    self.fractionCompleted = fractionCompleted
    self.trackCellCount = trackCellCount
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.canDecrement = canDecrement
    self.canIncrement = canIncrement
    self.styleEnvironment = styleEnvironment
    trackIdentity = nil
  }

  /// Installs the primitive's track pointer target. Install once; fixture routes are inert.
  ///
  /// The wrapped view becomes the bounds pointer input maps against: a press,
  /// drag, or release inside it sets the value from the pointer's column, the
  /// drag stays captured when it leaves those bounds, and the wheel adjusts by
  /// one step. The framework supplies the route identity.
  ///
  /// Installing the route twice in one body reports `style.duplicateRoute`;
  /// the first installation stays the target and the later one renders its
  /// content without a route. Omitting the wrapper removes only the pointer
  /// target: arrow keys, the wheel, and Space stay with the primitive.
  ///
  /// The content receives the slider's enabled state on both the live and
  /// the fixture path, so a style body that reads `isEnabled` renders the
  /// same way under test as it does in a live control.
  ///
  /// - Parameter content: The view the style composes for the track.
  /// - Returns: That content wrapped in the track pointer route.
  @ViewBuilder @MainActor
  public func track<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    let content = content().disabled(!isEnabled)
    styleRoute(
      target: trackIdentity.map { trackIdentity in
        StyleRouteTarget(
          identity: trackIdentity, family: "SliderStyle", role: "track", captureOnPress: true)
      }, content: content)
  }

  mutating func bindRoutes(to identity: Identity) {
    trackIdentity = sliderTrackIdentity(for: identity)
  }
}

/// Type-erased storage for a concrete ``SliderStyle``, the value the environment carries.
public struct AnySliderStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnySliderStyleBox
  /// Wraps a concrete slider style for the environment.
  ///
  /// The generic `sliderStyle(_:)` overload calls this for you.
  ///
  /// - Parameter style: The style to erase.
  public init<S: SliderStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }
  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }
  /// The ``AutomaticSliderStyle`` treatment, a fixed alias of
  /// ``AnySliderStyle/linear``.
  public static var automatic: Self {
    Self(AutomaticSliderStyle())
  }
  /// The ``LinearSliderStyle`` treatment: the label, a one-line track with a
  /// position marker, and the formatted value.
  public static var linear: Self {
    Self(LinearSliderStyle())
  }
  @MainActor
  package func resolveBody(configuration: SliderStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnySliderStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``Slider``: a fixed alias of ``LinearSliderStyle``.
///
/// It renders exactly what the linear style renders and exists so that
/// `.automatic` names one documented treatment rather than a hidden second
/// one. It reports its own snapshot label.
public struct AutomaticSliderStyle: SliderStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnySliderStyle.automatic" }
  /// Composes the linear treatment's body: the label, the marked track, and
  /// the value.
  ///
  /// - Parameter configuration: The slider's captured content and render state.
  /// - Returns: The same body ``LinearSliderStyle`` produces.
  @MainActor
  public func makeBody(configuration: SliderStyleConfiguration) -> some View {
    AutomaticSliderStyleBody(configuration: configuration)
  }
}
extension SliderStyle where Self == AutomaticSliderStyle {
  /// The automatic slider treatment, spelled `.automatic` wherever a
  /// ``SliderStyle`` is expected.
  public static var automatic: AutomaticSliderStyle { .init() }
}
extension AutomaticSliderStyle: ReuseTransparentStyle {}

/// The `linear` treatment for ``Slider``: a labelled row with a marked track
/// and the formatted value.
///
/// The row reserves a leading cell for the focus rail and draws the rail in
/// the theme's border paint while the focus effect is active. The track spans
/// ``SliderStyleConfiguration/trackCellCount`` cells and prints the completed
/// span as `━`, the current position as `●`, and the remainder as `─`. While
/// the control is focused or pressed, the track and value take the control
/// chrome's paints over a filled background; otherwise the track uses the
/// separator paint. The label uses the theme's accent border role, and the
/// whole row honors the chrome's disabled opacity.
public struct LinearSliderStyle: SliderStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnySliderStyle.linear" }
  /// Composes the label, the marked track inside
  /// ``SliderStyleConfiguration/track(content:)``, and the value into one row.
  ///
  /// - Parameter configuration: The slider's captured content and render state.
  /// - Returns: The linear row for the control.
  @MainActor
  public func makeBody(configuration: SliderStyleConfiguration) -> some View {
    LinearSliderStyleBody(configuration: configuration)
  }
}
extension SliderStyle where Self == LinearSliderStyle {
  /// The linear slider treatment, spelled `.linear` wherever a ``SliderStyle``
  /// is expected.
  public static var linear: LinearSliderStyle { .init() }
}
extension LinearSliderStyle: ReuseTransparentStyle {}

private struct AutomaticSliderStyleBody: View {
  let configuration: SliderStyleConfiguration
  var body: some View { LinearSliderStyleBody(configuration: configuration) }
}

private struct LinearSliderStyleBody: View {
  let configuration: SliderStyleConfiguration
  var body: some View {
    let active = configuration.focusActive || configuration.isPressed
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let contentChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let width = max(1, configuration.trackCellCount)
    let fraction =
      configuration.fractionCompleted.isFinite
      ? min(max(configuration.fractionCompleted, 0), 1) : 0
    let position = min(width - 1, max(0, Int((fraction * Double(width - 1)).rounded())))
    ControlStyleRow(
      chrome: chrome, focusActive: configuration.focusActive, isHighlighted: active
    ) {
      configuration.label.foregroundStyle(.terminalBorder(.accent))
      HStack(alignment: .center, spacing: 1) {
        configuration.track {
          Text(
            String(repeating: "━", count: position) + "●"
              + String(repeating: "─", count: width - position - 1)
          )
          .foregroundStyle(active ? contentChrome.borderStyle : AnyShapeStyle(.separator))
        }
        configuration.valueLabel.foregroundStyle(
          active ? contentChrome.foregroundStyle : chrome.foregroundStyle)
      }
      .opacity(contentChrome.opacity)
      .background {
        if active { Rectangle().fill(contentChrome.backgroundStyle) }
      }
    }
  }
}

private protocol AnySliderStyleBox: AnyStyleBox {
  @MainActor
  func resolveBody(configuration: SliderStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}
extension ConcreteStyleBox: AnySliderStyleBox where S: SliderStyle {
  @MainActor
  func resolveBody(configuration: SliderStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}
