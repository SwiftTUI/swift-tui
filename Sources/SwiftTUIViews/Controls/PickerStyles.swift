public import SwiftTUICore

/// Defines keyboard behavior and rendered body for a picker.
///
/// A picker style is body-producing: for every pass the primitive resolves a
/// ``PickerStyleConfiguration`` and calls
/// ``PickerStyle/makeBody(configuration:)``, and the returned view stands in for
/// the picker. The configuration carries the captured authored label, the
/// resolved options, and read-only render state.
///
/// A picker style also owns one piece of behavior the other body-producing
/// families do not have: ``PickerStyle/selectionDelta(for:)`` decides which keys
/// step the selection. Everything else stays with the primitive, which keeps the
/// focus stop, writes the selection binding, dispatches option routes, and
/// carries the accessibility semantics whatever the style returns.
///
/// Apply a style with `pickerStyle(_:)`. The value is stored in the environment
/// for the subtree, so the nearest modifier wins. The built-ins are
/// ``AnyPickerStyle/automatic``, ``AnyPickerStyle/inline``,
/// ``AnyPickerStyle/segmented``, ``AnyPickerStyle/radioGroup``, and
/// ``AnyPickerStyle/menu``; `.automatic` is a fixed alias of `.inline`.
///
/// A conforming type must be a value type (a struct or an enum) and `Sendable`;
/// a class conformance does not compile.
///
/// ```swift
/// struct CompactPickerStyle: PickerStyle {
///   func selectionDelta(for event: KeyEvent) -> Int? {
///     switch event {
///     case .arrowLeft: -1
///     case .arrowRight: 1
///     default: nil
///     }
///   }
///
///   func makeBody(configuration: PickerStyleConfiguration) -> some View {
///     HStack(spacing: 1) {
///       configuration.label
///       ForEach(0..<configuration.options.count) { index in
///         let option = configuration.options[index]
///         option.route {
///           Text(option.isSelected ? "[\(option.label)]" : " \(option.label) ")
///         }
///       }
///     }
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol PickerStyle: Sendable {
  /// The view type this style returns for a picker.
  associatedtype Body: View

  /// The label reported for this style in snapshots and diagnostics.
  ///
  /// The default implementation returns the reflected type name. It is
  /// diagnostic text: reuse and identity never depend on its value.
  var snapshotLabel: String { get }

  /// Maps a key event to a step in the picker's selection.
  ///
  /// Return `-1` for the previous option, `1` for the next, or any other offset
  /// to move further; return `nil` to leave the event unhandled so the primitive
  /// can pass it on. The primitive applies the step and writes the selection
  /// binding, so a style never mutates the selection itself.
  ///
  /// The default implementation returns `nil` for every event, which means a
  /// style that does not implement it has no keyboard selection at all. The
  /// built-ins step on Up and Down, except ``SegmentedPickerStyle``, which steps
  /// on Left and Right.
  ///
  /// - Parameter event: The key event delivered while the picker is focused.
  /// - Returns: The offset to apply to the selected index, or `nil` when the
  ///   style does not handle the key.
  @MainActor
  func selectionDelta(
    for event: KeyEvent
  ) -> Int?

  /// Enables the primitive's menu expansion actions. Compose the trigger with
  /// `configuration.trigger` and show options while `isActiveNavigation` is true.
  ///
  /// The default implementation returns `false`, so no expansion actions are
  /// installed. ``MenuPickerStyle`` is the only built-in that opts in.
  @MainActor
  var wantsTriggerPointerRoute: Bool { get }

  /// Builds the view that renders in the picker's place.
  ///
  /// - Parameter configuration: The captured label, the resolved options, and
  ///   the render state of this picker.
  /// - Returns: The replacement body for the control.
  @ViewBuilder @MainActor
  func makeBody(
    configuration: PickerStyleConfiguration
  ) -> Body

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _pickerStyleValueTypeWitness: Void { get }
}

extension PickerStyle {
  @_documentation(visibility: internal)
  public static var _pickerStyleValueTypeWitness: Void { () }
}

extension PickerStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI picker styles must be value types (a struct or an enum); a class cannot conform to PickerStyle"
  )
  public static var _pickerStyleValueTypeWitness: Void { () }
}

extension PickerStyle {
  /// The reflected name of the conforming type, used when a style does not
  /// supply a label of its own.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }

  /// Handles no keys at all.
  ///
  /// A style that does not implement ``PickerStyle/selectionDelta(for:)`` gets
  /// no keyboard selection: every event is left to the primitive.
  ///
  /// - Parameter event: The key event, ignored.
  /// - Returns: `nil`.
  @MainActor
  public func selectionDelta(
    for _: KeyEvent
  ) -> Int? {
    nil
  }

  /// Declines the menu expansion actions, so the primitive installs no trigger
  /// route for this style.
  @MainActor
  public var wantsTriggerPointerRoute: Bool {
    false
  }
}

/// The captured label, the resolved options, and the render state a
/// ``PickerStyle`` composes into a body.
///
/// ``label`` is a captured authored slot: it keeps the state, environment, and
/// preferences of the scope it was written in. ``options`` and the flags around
/// them are read-only render state the primitive resolved for this pass; the
/// selection binding itself is never handed to the style.
///
/// Two route wrappers turn parts of the body into pointer targets:
/// ``PickerStyleConfiguration/Option/route(content:)`` for an option row and
/// ``PickerStyleConfiguration/trigger(content:)`` for a menu trigger. The
/// framework supplies the identities; a style only chooses what goes inside.
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public struct PickerStyleConfiguration: Sendable {
  /// The authored label of the picker, captured with its authoring scope.
  ///
  /// Place it in the body to render the picker's title. Because the content
  /// keeps the scope it was authored in, its state, environment values, and
  /// preferences survive wherever the style puts it.
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

  /// One selectable option, as the primitive resolved it for this pass.
  ///
  /// Options arrive in authored order. Occurrences, not labels, identify an
  /// option, so two options that render the same text stay distinct and route
  /// separately.
  public struct Option: Sendable {
    /// The option's position in the picker, independent of its display label.
    public var index: Int
    /// The option's text, as the primitive resolved it from the authored
    /// option content.
    public var label: String
    /// Whether this occurrence matches the current selection binding.
    public var isSelected: Bool
    /// Whether the picker currently accepts input.
    ///
    /// It mirrors the picker's own ``PickerStyleConfiguration/isEnabled``:
    /// individual options are never separately disabled.
    public var isEnabled: Bool
    private var routeIdentity: Identity?

    /// Creates a standalone option for a fixture or a preview.
    ///
    /// Its route installs no hit target, and its index, selection, and
    /// enablement are placeholders: the fixture initializer of
    /// ``PickerStyleConfiguration`` rewrites all three from the option's
    /// position, the selected index, and the picker's enablement (see
    /// <doc:Testing-Styles>).
    ///
    /// - Parameter label: The text the option renders.
    public init(
      label: String
    ) {
      index = 0
      self.label = label
      isSelected = false
      isEnabled = true
      routeIdentity = nil
    }

    /// Creates an option fixture whose route renders content without a hit target.
    @_spi(StyleFixtures)
    public init(index: Int, label: String, isSelected: Bool, isEnabled: Bool) {
      self.index = index
      self.label = label
      self.isSelected = isSelected
      self.isEnabled = isEnabled
      routeIdentity = nil
    }

    /// Routes a click on `content` to this option's selection. Install once
    /// per option; duplicates report `style.duplicateRoute` and the first wins.
    ///
    /// Omitting the wrapper removes only the pointer target: keyboard selection
    /// stays with the primitive. A fixture-constructed option installs no
    /// target, so the wrapper renders `content` unchanged in a style test.
    ///
    /// - Parameter content: The row or segment that should accept the click.
    /// - Returns: `content` with the option's pointer target installed.
    @ViewBuilder @MainActor
    public func route<Content: View>(
      @ViewBuilder content: () -> Content
    ) -> some View {
      styleRoute(
        target: routeIdentity.map { routeIdentity in
          StyleRouteTarget(identity: routeIdentity, family: "PickerStyle", role: "option")
        }, content: content())
    }

    mutating func bindRoute(to identity: Identity) {
      routeIdentity = identity
    }
  }

  /// The picker's identity in the view graph, from which the framework derives
  /// the option and trigger route targets. A fixture supplies a placeholder that
  /// activates no routes.
  public var controlIdentity: Identity
  /// The captured authored label, placed in the body to render the picker's
  /// title.
  public var label: Label
  /// The picker's options in authored order, already resolved for this pass.
  public var options: [Option]
  /// The index of the selected option, or `nil` when the selection binding
  /// matches no option.
  public var selectedIndex: Int?
  /// Whether the picker owns keyboard focus, regardless of whether a focus
  /// treatment is allowed.
  public var isFocused: Bool
  /// Whether the picker's option navigation is active.
  ///
  /// The primitive owns the flag. ``MenuPickerStyle`` expands its option list
  /// while it is true, and the other built-ins use it to decide whether the
  /// selected row is drawn as the active one rather than merely marked.
  public var isActiveNavigation: Bool
  /// Whether the environment permits a focus treatment; `focusEffectDisabled()`
  /// clears it while the picker stays focused.
  public var showsFocusEffect: Bool
  /// Whether the picker accepts input. A disabled picker still renders, dimmed
  /// by the chrome its style resolves.
  public var isEnabled: Bool
  /// The resolved style environment for this pass: the theme, its semantic
  /// colors, the enablement flag, and the `controlChrome`/`rowChrome` helpers a
  /// custom style uses to match the built-in treatments.
  public var styleEnvironment: StyleEnvironmentSnapshot
  /// The number of lines the framework has reserved for the picker, or `nil`
  /// when it is unconstrained.
  ///
  /// It is supplied by the framework through a package-level modifier, so a
  /// style reads it but application code cannot set it. ``InlinePickerStyle``
  /// windows its rows to the reserved height and draws `↑` and `↓` markers on
  /// the lines above and below the window.
  public var viewportLineCount: Int?
  /// The cell width the framework asks option rows to occupy, or `nil` to let
  /// the style choose.
  ///
  /// It is supplied the same package-level way as ``viewportLineCount``. The
  /// inline and menu built-ins fall back to the widest option label plus the two
  /// cells the selection marker and its spacing take.
  public var lineWidth: Int?
  private var triggerIdentity: Identity?

  /// Whether the picker is focused and the focus effect is enabled.
  ///
  /// Read this rather than combining `isFocused` and `showsFocusEffect`
  /// yourself: a picker under `focusEffectDisabled()` is still focused for
  /// keyboard purposes but must not draw a focus treatment.
  public var focusActive: Bool {
    isFocused && showsFocusEffect
  }

  /// Creates a fixture with inert option and trigger routes. `controlIdentity`
  /// is retained for source compatibility; it does not activate fixture routes.
  ///
  /// This constructs the configuration from fixture state for a style test
  /// without a live render (see <doc:Testing-Styles>). The `options` array is
  /// rewritten as it is stored: each option takes its position as `index`, is
  /// selected only when that position equals `selectedIndex`, and inherits
  /// `isEnabled` from the picker.
  @_spi(StyleFixtures)
  public init(
    controlIdentity: Identity = Identity(components: ["PickerStyleFixture"]),
    label: Label,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    viewportLineCount: Int?,
    lineWidth: Int?
  ) {
    self.controlIdentity = controlIdentity
    self.label = label
    self.options = options.enumerated().map { index, option in
      Option(
        index: index,
        label: option.label,
        isSelected: index == selectedIndex,
        isEnabled: isEnabled
      )
    }
    self.selectedIndex = selectedIndex
    self.isFocused = isFocused
    self.isActiveNavigation = isActiveNavigation
    self.showsFocusEffect = showsFocusEffect
    self.isEnabled = isEnabled
    self.styleEnvironment = styleEnvironment
    self.viewportLineCount = viewportLineCount
    self.lineWidth = lineWidth
    triggerIdentity = nil
  }

  /// Routes a click on `content` to menu expansion. Menu styles opt in with
  /// `wantsTriggerPointerRoute`; keyboard interaction survives omission of
  /// this wrapper. Fixture configurations never install a pointer target.
  ///
  /// Install it once. A duplicate reports `style.duplicateRoute` and the first
  /// wrapper wins.
  ///
  /// - Parameter content: The collapsed trigger row.
  /// - Returns: `content` with the expansion pointer target installed.
  @ViewBuilder @MainActor
  public func trigger<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    styleRoute(
      target: triggerIdentity.map { triggerIdentity in
        StyleRouteTarget(identity: triggerIdentity, family: "PickerStyle", role: "trigger")
      }, content: content())
  }

  mutating func bindRoutes(to identity: Identity) {
    triggerIdentity = pickerTriggerIdentity(for: identity)
    for index in options.indices {
      options[index].bindRoute(to: pickerOptionIdentity(for: identity, index: index))
    }
  }
}

/// Type-erased storage for a picker style, the value the environment carries.
///
/// `pickerStyle(_:)` wraps a concrete style in this type before storing it for
/// the subtree. The built-ins are exposed as statics here, which is what lets a
/// call site write `.segmented` where an `AnyPickerStyle` is expected.
public struct AnyPickerStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyPickerStyleBox

  /// Wraps a concrete picker style for storage in the environment.
  ///
  /// The style's ``PickerStyle/snapshotLabel`` is captured here and reported as
  /// this value's description.
  ///
  /// - Parameter style: The concrete style to erase.
  public init<S: PickerStyle>(
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

  /// The default picker treatment: a fixed alias of ``AnyPickerStyle/inline``,
  /// including its Up and Down selection steps, not an environment-driven
  /// choice.
  public static var automatic: Self {
    Self(AutomaticPickerStyle())
  }

  /// Every option as a row in a rounded, bordered container under the picker's
  /// label. The border goes heavy while the focus effect is active, the selected
  /// row carries a leading marker, and a framework-supplied viewport scrolls the
  /// rows with `↑` and `↓` markers. Up and Down step the selection.
  public static var inline: Self {
    Self(InlinePickerStyle())
  }

  /// Options laid out horizontally as divider-separated segments in a rounded,
  /// bordered container under the picker's label, with the selected segment
  /// filled with the tint. Left and Right step the selection.
  public static var segmented: Self {
    Self(SegmentedPickerStyle())
  }

  /// Options stacked as `(*)` and `( )` rows in a rounded, bordered container
  /// under the picker's label. Up and Down step the selection.
  public static var radioGroup: Self {
    Self(RadioGroupPickerStyle())
  }

  /// A collapsed trigger row showing the selected option, expanding an indented
  /// option list below it while navigation is active. It is the only built-in
  /// that opts into the trigger pointer route. Up and Down step the selection.
  public static var menu: Self {
    Self(MenuPickerStyle())
  }

  @MainActor
  package func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    box.selectionDelta(for: event)
  }

  @MainActor
  package var wantsTriggerPointerRoute: Bool {
    box.wantsTriggerPointerRoute
  }

  @MainActor
  package func resolveBody(
    configuration: PickerStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    box.resolveBody(
      configuration: configuration,
      in: context
    )
  }
}

extension AnyPickerStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default picker style: a fixed alias of ``InlinePickerStyle``.
///
/// It renders the same body and answers the same Up and Down selection steps;
/// nothing about the treatment is environment-driven. It exists so that a picker
/// with no style modifier and a picker written as `.pickerStyle(.automatic)`
/// resolve to the same appearance under a distinct snapshot label.
public struct AutomaticPickerStyle: Sendable, PickerStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyPickerStyle.automatic"
  }

  /// Steps one option back on Up and one forward on Down, and handles no other
  /// key.
  ///
  /// - Parameter event: The key event delivered while the picker is focused.
  /// - Returns: `-1`, `1`, or `nil`.
  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowUp:
      -1
    case .arrowDown:
      1
    default:
      nil
    }
  }

  /// Builds the inline body, identical to ``InlinePickerStyle``.
  ///
  /// - Parameter configuration: The captured label, options, and render state.
  /// - Returns: The inline picker body.
  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    InlinePickerStyleBody(configuration: configuration)
  }
}

/// A vertically arranged picker style that keeps options inline.
///
/// The authored label sits above a rounded, one-cell-inset container holding one
/// row per option. The container keeps a plain background so no row reads as
/// highlighted by the container itself, and its border is stroked heavy while
/// the focus effect is active. Each row carries a leading marker cell that is
/// filled for the selected option, and the active row also takes the row
/// background while navigation is running. When the framework reserves a
/// viewport, the rows are windowed around the selection and `↑` and `↓` markers
/// mark the options outside the window.
public struct InlinePickerStyle: Sendable, PickerStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyPickerStyle.inline"
  }

  /// Steps one option back on Up and one forward on Down, and handles no other
  /// key.
  ///
  /// - Parameter event: The key event delivered while the picker is focused.
  /// - Returns: `-1`, `1`, or `nil`.
  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowUp:
      -1
    case .arrowDown:
      1
    default:
      nil
    }
  }

  /// Builds the bordered row list, windowed to the reserved viewport when the
  /// framework supplies one.
  ///
  /// - Parameter configuration: The captured label, options, and render state.
  /// - Returns: The inline picker body.
  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    InlinePickerStyleBody(configuration: configuration)
  }
}

/// A compact horizontal picker style for mutually exclusive options.
///
/// The authored label sits above a rounded, one-cell-inset container holding the
/// options side by side, separated by dividers. The selected segment is filled
/// with the tint and draws its text in the chrome's content background color;
/// while navigation is running the other segments take the focused segment
/// background. The container's border is stroked heavy while the focus effect is
/// active.
public struct SegmentedPickerStyle: Sendable, PickerStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyPickerStyle.segmented"
  }

  /// Steps one option back on Left and one forward on Right, and handles no
  /// other key. This is the one built-in that does not use Up and Down.
  ///
  /// - Parameter event: The key event delivered while the picker is focused.
  /// - Returns: `-1`, `1`, or `nil`.
  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowLeft:
      -1
    case .arrowRight:
      1
    default:
      nil
    }
  }

  /// Builds the horizontal segment strip inside its bordered container.
  ///
  /// - Parameter configuration: The captured label, options, and render state.
  /// - Returns: The segmented picker body.
  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    SegmentedPickerStyleBody(configuration: configuration)
  }
}

/// A vertical radio-button picker style.
///
/// The authored label sits above a rounded, one-cell-inset container holding one
/// row per option, each prefixed with `(*)` when selected and `( )` when not.
/// The selected row also shows a leading marker, which takes the border color
/// and the row highlight only while navigation is running and the focus effect
/// is active. The container's border is stroked heavy while the focus effect is
/// active.
public struct RadioGroupPickerStyle: Sendable, PickerStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyPickerStyle.radioGroup"
  }

  /// Steps one option back on Up and one forward on Down, and handles no other
  /// key.
  ///
  /// - Parameter event: The key event delivered while the picker is focused.
  /// - Returns: `-1`, `1`, or `nil`.
  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowUp:
      -1
    case .arrowDown:
      1
    default:
      nil
    }
  }

  /// Builds the stacked radio rows inside their bordered container.
  ///
  /// - Parameter configuration: The captured label, options, and render state.
  /// - Returns: The radio-group picker body.
  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    RadioGroupPickerStyleBody(configuration: configuration)
  }
}

/// A collapsed picker style that opens a menu-like option list.
///
/// The authored label sits above a trigger row that shows a `▾` marker, the
/// selected option's text, or `Select` when nothing is selected. While
/// ``PickerStyleConfiguration/isActiveNavigation`` is true the marker turns to
/// `▴` and an indented option list is stacked below the trigger.
///
/// The two rails in this style mean different things. On the trigger row the
/// leading rail is the focus treatment. Beside an expanded option row it is a
/// selection marker, drawn whenever that option is selected, not a focus
/// treatment.
///
/// It is the only built-in that returns `true` from
/// ``wantsTriggerPointerRoute``, which is what installs the primitive's
/// expansion actions and makes the trigger clickable.
public struct MenuPickerStyle: Sendable, PickerStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String {
    "AnyPickerStyle.menu"
  }

  /// Steps one option back on Up and one forward on Down, and handles no other
  /// key.
  ///
  /// - Parameter event: The key event delivered while the picker is focused.
  /// - Returns: `-1`, `1`, or `nil`.
  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowUp:
      -1
    case .arrowDown:
      1
    default:
      nil
    }
  }

  /// Opts into the primitive's menu expansion actions, so the trigger row
  /// installed by ``PickerStyleConfiguration/trigger(content:)`` expands and
  /// collapses the option list.
  @MainActor
  public var wantsTriggerPointerRoute: Bool {
    true
  }

  /// Builds the collapsed trigger row, plus the indented option list while
  /// navigation is active.
  ///
  /// - Parameter configuration: The captured label, options, and render state.
  /// - Returns: The menu picker body.
  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    MenuPickerStyleBody(configuration: configuration)
  }
}

private protocol AnyPickerStyleBox: AnyStyleBox {

  @MainActor
  func selectionDelta(
    for event: KeyEvent
  ) -> Int?

  @MainActor
  var wantsTriggerPointerRoute: Bool { get }

  @MainActor
  func resolveBody(
    configuration: PickerStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyPickerStyleBox where S: PickerStyle {

  @MainActor
  func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    style.selectionDelta(for: event)
  }

  @MainActor
  var wantsTriggerPointerRoute: Bool {
    style.wantsTriggerPointerRoute
  }

  @MainActor
  func resolveBody(
    configuration: PickerStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

// The builtin picker styles: stateless, so type identity settles reuse.
extension AutomaticPickerStyle: ReuseTransparentStyle {}
extension InlinePickerStyle: ReuseTransparentStyle {}
extension SegmentedPickerStyle: ReuseTransparentStyle {}
extension RadioGroupPickerStyle: ReuseTransparentStyle {}
extension MenuPickerStyle: ReuseTransparentStyle {}
