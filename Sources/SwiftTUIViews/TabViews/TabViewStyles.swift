@_spi(Testing) public import SwiftTUICore

/// Type-erased storage for a tab-view style, the value the environment carries.
///
/// Both ``description`` and ``debugDescription`` report the wrapped style's
/// ``TabViewStyle/snapshotLabel``. The built-in labels are spelled after this
/// eraser rather than after the protocol, as `"AnyTabViewStyle.underline"`,
/// where the other style families spell theirs after the protocol.
public struct AnyTabViewStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyTabViewStyleBox

  /// Wraps a concrete tab-view style for storage in the environment.
  ///
  /// The style's label is read once here; the style itself stays boxed, so reuse
  /// comparisons still see the concrete value.
  ///
  /// - Parameter style: The style to erase.
  public init<S: TabViewStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's ``TabViewStyle/snapshotLabel``.
  public var description: String {
    snapshotLabel
  }

  /// The wrapped style's ``TabViewStyle/snapshotLabel``, the same text as
  /// ``description``.
  public var debugDescription: String {
    snapshotLabel
  }

  /// The default tab-view style, a fixed alias of ``underline``.
  public static var automatic: Self {
    Self(AutomaticTabViewStyle())
  }

  /// A two-row strip: labels on the first row, and under each one a block rule
  /// drawn `▄` when that tab is both selected and focused, `▂` when it is one of
  /// the two, and `▁` otherwise.
  public static var underline: Self {
    Self(UnderlineTabViewStyle())
  }

  /// A three-row strip that brackets each label in literal box-drawing tab
  /// chrome and opens the selected tab's floor into the content. It is the only
  /// built-in that overflows: labels that do not fit move behind a `▾` trigger
  /// that opens a bordered menu.
  public static var literalTabs: Self {
    Self(LiteralTabsTabViewStyle())
  }

  /// A one-row strip of connected segments: the selected label sits on the tint
  /// color, and segments are divided by `◤` and `◢` beside the selected tab and
  /// a dimmed `╱` elsewhere.
  public static var powerline: Self {
    Self(PowerlineTabViewStyle())
  }

  @MainActor
  package func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    box.presentation(for: configuration)
  }

  /// The style's presentation for `configuration`, checked against the
  /// shared misuse rule (see `StyleMisuse`): an invalid value reports one
  /// `style.invalidPresentation` issue naming this style and the tab view at
  /// `identity`, and the automatic presentation drives this resolve. The
  /// style's body still renders; only the presentation value is replaced.
  @MainActor
  package func validatedPresentation(
    for configuration: TabViewStyleConfiguration,
    identity: Identity
  ) -> TabViewStylePresentation {
    let resolved = presentation(for: configuration)
    return StyleMisuse.validatedPresentation(
      resolved,
      problems: resolved.validationProblems(optionCount: configuration.options.count),
      family: "TabViewStyle",
      styleLabel: description,
      identity: identity,
      report: ImperativeRuntimeIssueQueue.record,
      fallback: { Self.automatic.presentation(for: configuration) }
    )
  }

  @MainActor
  package func resolveBody(
    configuration: TabViewStyleBodyConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(
      configuration: configuration,
      in: context
    )
  }
}

extension AnyTabViewStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default tab-view style: a fixed alias of ``UnderlineTabViewStyle``.
///
/// It resolves the same two-row presentation with every option visible and no
/// overflow menu, and it renders the same underline body. It reads nothing from
/// the environment.
public struct AutomaticTabViewStyle: Sendable {
  /// Creates the style.
  public init() {}
}

/// A tab-view style that underlines the selected tab.
///
/// It reserves a two-row strip and keeps every option visible, so it never
/// produces an overflow menu. The rule under a tab is `▄` when that tab is both
/// selected and focused, `▂` when it is one of the two, and `▁` otherwise; the
/// selected rule takes the accent paint, and the focused tab is drawn on an
/// accent surface.
public struct UnderlineTabViewStyle: Sendable {
  /// Creates the style.
  public init() {}
}

/// A tab-view style that renders labels as literal terminal tabs.
///
/// It reserves a three-row strip and draws each label inside box-drawing tab
/// chrome: `╭──╮` above, `│ label │` around, and `┴──┴` below, opened to
/// `┘   └` under the selected tab. It is the only built-in that overflows: when
/// the tab widths exceed ``TabViewStyleConfiguration/availableWidth``, the tabs
/// that do not fit move behind a trigger labeled `▾`, or `▴` while the menu is
/// open, and the filled `▼` and `▲` when the selection itself is in the
/// overflow. The menu is padded one cell, filled with the background paint, and
/// outlined with a radius-one border that takes the accent tone while the strip
/// is focused.
public struct LiteralTabsTabViewStyle: Sendable {
  /// Creates the style.
  public init() {}
}

/// A tab-view style that renders connected powerline-style tab segments.
///
/// It reserves a one-row strip and keeps every option visible, so it never
/// produces an overflow menu. The selected label is drawn on the tint color with
/// an automatically contrasting foreground; the separator after a segment is `◤`
/// on the selected tab, `◢` on the tab before it, and a dimmed `╱` elsewhere.
public struct PowerlineTabViewStyle: Sendable {
  /// Creates the style.
  public init() {}
}

/// Defines tab strip, overflow, and active tab rendering.
///
/// A tab-view style has both halves of the style system: it resolves a value
/// from ``TabViewStyle/presentation(for:)`` and then builds a body from
/// ``TabViewStyle/makeBody(configuration:)``. The presentation decides how tall
/// the strip is, which options appear in it, and whether the remainder collapses
/// into an overflow menu; the body draws that strip and places the active tab's
/// content.
///
/// Whatever the style renders, the tab view keeps the selection and its binding,
/// arrow-key and overflow key handling, focus, dormant tab state, and
/// accessibility semantics. A strip whose style never calls
/// ``TabViewStyleItemConfiguration/route(content:)`` still changes tabs from the
/// keyboard; a route only adds the pointer target.
///
/// The presentation is validated before the body runs, under the rules on
/// ``TabViewStylePresentation``. An invalid value reports one
/// `style.invalidPresentation` issue naming this style and the tab view, and
/// ``AnyTabViewStyle/automatic``'s presentation drives that resolve instead,
/// while this style's ``makeBody(configuration:)`` still renders.
///
/// Apply a style with `tabViewStyle(_:)`. The value is stored in the
/// environment for the subtree, so the nearest modifier above a tab view wins.
/// The built-ins are ``AnyTabViewStyle/automatic``,
/// ``AnyTabViewStyle/underline``, ``AnyTabViewStyle/literalTabs``, and
/// ``AnyTabViewStyle/powerline``; `.automatic` is a fixed alias of
/// `.underline`.
///
/// A conforming type must be a value type, a struct or an enum, and `Sendable`;
/// a class conformance fails to compile.
///
/// ```swift
/// struct PillTabViewStyle: TabViewStyle {
///   var snapshotLabel: String { "PillTabViewStyle" }
///
///   func presentation(
///     for configuration: TabViewStyleConfiguration
///   ) -> TabViewStylePresentation {
///     .init(
///       stripHeight: 1,
///       visibleOptionIndices: Array(configuration.options.indices),
///       overflowMenu: nil
///     )
///   }
///
///   func makeBody(configuration: TabViewStyleBodyConfiguration) -> some View {
///     VStack(alignment: .leading, spacing: 0) {
///       HStack(spacing: 1) {
///         ForEach(Array(configuration.visibleItems.indices), id: \.self) { position in
///           let item = configuration.visibleItems[position]
///           item.route {
///             Text(item.isSelected ? "(\(item.label.displayText))" : item.label.displayText)
///           }
///         }
///       }
///       .frame(height: configuration.presentation.stripHeight)
///
///       configuration.content
///     }
///   }
/// }
/// ```
///
/// See <doc:Style-System>, <doc:Authoring-Styles>, and
/// <doc:Navigation-And-Tabs>.
public protocol TabViewStyle: Sendable {
  /// The view type ``makeBody(configuration:)`` returns, inferred from the
  /// body's `@ViewBuilder` result.
  associatedtype Body: View

  /// The label reported in snapshots and diagnostics.
  ///
  /// Diagnostic text, not identity: do not branch on it. It names the style in a
  /// `style.invalidPresentation` report and is what ``AnyTabViewStyle`` reports
  /// as both its description and its debug description. The default
  /// implementation returns the reflected type name.
  var snapshotLabel: String { get }

  /// Resolves the strip height and the visible-versus-overflow split for the
  /// given tab state.
  ///
  /// Called on the main actor before ``makeBody(configuration:)``, and validated
  /// before the body sees it.
  ///
  /// - Parameter configuration: The options, selection, focus, available width,
  ///   and overflow-expansion state for this resolve.
  /// - Returns: The strip height, the option indices to draw in the strip, and
  ///   the overflow menu, if any.
  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  /// Builds the tab view's body: the strip, any overflow surface, and the active
  /// tab's content.
  ///
  /// Called on the main actor with the validated presentation already applied
  /// and the per-item configurations already split into visible and overflow
  /// groups. Place ``TabViewStyleBodyConfiguration/content`` somewhere in the
  /// returned body, or the selected tab renders nothing.
  ///
  /// - Parameter configuration: The items, presentation, overflow trigger, and
  ///   active-tab content slot for this resolve.
  /// - Returns: The rendered tab view.
  @ViewBuilder @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> Body

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _tabViewStyleValueTypeWitness: Void { get }
}

extension TabViewStyle {
  @_documentation(visibility: internal)
  public static var _tabViewStyleValueTypeWitness: Void { () }
}

extension TabViewStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI tab view styles must be value types (a struct or an enum); a class cannot conform to TabViewStyle"
  )
  public static var _tabViewStyleValueTypeWitness: Void { () }
}

extension TabViewStyle {
  /// The reflected type name, supplied when a conforming type declares no label.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// One authored tab, as a style sees it.
///
/// A style receives these in ``TabViewStyleConfiguration/options`` in
/// declaration order, and their positions are the indices every other tab-view
/// type refers to. An option carries the label only: the tab's tag, content, and
/// dormant state stay with the tab view.
public struct TabViewStyleOption: Sendable {
  /// The tab's structured label. Its `displayText` joins the title, detail, and
  /// badge into one line.
  public var label: TabItemLabel

  /// Creates an option from a tab label.
  ///
  /// - Parameter label: The label the strip draws for this tab.
  public init(
    label: TabItemLabel
  ) {
    self.label = label
  }
}

/// The per-tab render state a style's strip is built from.
///
/// The tab view supplies one of these per option in
/// ``TabViewStyleBodyConfiguration/items`` and splits them into
/// ``TabViewStyleBodyConfiguration/visibleItems`` and
/// ``TabViewStyleBodyConfiguration/overflowItems`` according to the resolved
/// presentation. Every stored member is read-only render state; there is no
/// binding here, because changing the selection is the tab view's own job. The
/// two route wrappers are what add pointer targets.
public struct TabViewStyleItemConfiguration: Sendable {
  /// The tab's position in ``TabViewStyleConfiguration/options``.
  ///
  /// This is the tab's identity across the strip, the overflow menu, and the
  /// presentation's index lists. It is not the item's position within
  /// ``TabViewStyleBodyConfiguration/visibleItems``, which can be shorter.
  public var index: Int

  /// The tab's structured label. Its `displayText` joins the title, detail, and
  /// badge into one line.
  public var label: TabItemLabel

  /// Whether this tab is the selected one.
  public var isSelected: Bool

  /// Whether keyboard focus is on this tab. It is `true` only while the strip
  /// itself is focused and the focus effect is enabled.
  public var isFocused: Bool
  package var controlIdentity: Identity?

  /// A fixture configuration for tests (see <doc:Testing-Styles>): it
  /// carries no control identity, so ``route(content:)`` and
  /// ``overflowRoute(content:)`` render their content and install no
  /// pointer target. The framework constructs live items itself.
  public init(
    index: Int,
    label: TabItemLabel,
    isSelected: Bool,
    isFocused: Bool
  ) {
    self.index = index
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    controlIdentity = nil
  }

  package init(
    index: Int,
    label: TabItemLabel,
    isSelected: Bool,
    isFocused: Bool,
    controlIdentity: Identity
  ) {
    self.index = index
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.controlIdentity = controlIdentity
  }

  /// Installs this item's pointer route around `content` so a click on it
  /// selects the tab.
  ///
  /// The framework supplies the identity, so a style never names one. Install
  /// the route once per item: a repeated installation in one style body reports
  /// `style.duplicateRoute` and the first one wins. Omitting it removes only the
  /// pointer target, since keyboard navigation is the tab view's own. On a
  /// fixture-constructed configuration there is no identity, so the wrapper
  /// renders `content` and installs nothing. See <doc:Authoring-Styles>.
  ///
  /// - Parameter content: The item's rendered appearance.
  /// - Returns: `content` with the item's pointer target around it.
  @ViewBuilder @MainActor
  public func route<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    styleRoute(
      target: controlIdentity.map { controlIdentity in
        StyleRouteTarget(
          identity: tabItemIdentity(for: controlIdentity, index: index),
          family: "TabViewStyle",
          role: "item"
        )
      }, content: content())
  }

  /// Installs this item's overflow-menu pointer route around `content`, so a
  /// click on the row inside an expanded overflow menu selects the tab.
  ///
  /// The same once-per-configuration rule as ``route(content:)`` applies, it is
  /// likewise inert on a fixture, and omitting it leaves the overflow row
  /// keyboard-reachable but not clickable.
  ///
  /// - Parameter content: The overflow row's rendered appearance.
  /// - Returns: `content` with the overflow row's pointer target around it.
  @ViewBuilder @MainActor
  public func overflowRoute<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    styleRoute(
      target: controlIdentity.map { controlIdentity in
        StyleRouteTarget(
          identity: tabOverflowItemIdentity(for: controlIdentity, index: index),
          family: "TabViewStyle",
          role: "overflow item"
        )
      }, content: content())
  }
}

/// `Equatable` lets style item views store the configuration as their memo
/// value. The renderer can reuse an item when its configuration and other stored
/// inputs compare equal across a frame.
extension TabViewStyleItemConfiguration: Equatable {}

/// The render state of the control that opens the overflow menu.
///
/// The tab view supplies one of these as
/// ``TabViewStyleBodyConfiguration/overflowTrigger`` exactly when the resolved
/// presentation carries an overflow menu, mirroring that menu's fields. Every
/// stored member is read-only render state; ``route(content:)`` is what adds the
/// pointer target that toggles the menu.
public struct TabViewOverflowTriggerConfiguration: Sendable {
  /// The text to draw for the trigger, copied from
  /// ``TabViewOverflowMenuPresentation/triggerLabel``.
  public var label: String

  /// Whether the selected tab is one of the overflowed ones, so the trigger
  /// stands in for the selection.
  public var isSelected: Bool

  /// Whether the focused tab is one of the overflowed ones.
  public var isFocused: Bool

  /// Whether the overflow menu is currently open.
  public var isExpanded: Bool

  /// The option indices held behind the trigger, in strip order.
  public var overflowIndices: [Int]

  /// The width in cells the visible tabs occupy before the trigger, so a style
  /// can align an expanded menu under it.
  public var leadingWidth: Int
  package var controlIdentity: Identity?

  /// A fixture configuration for tests (see <doc:Testing-Styles>): it
  /// carries no control identity, so ``route(content:)`` renders its
  /// content and installs no pointer target.
  public init(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    isExpanded: Bool,
    overflowIndices: [Int],
    leadingWidth: Int
  ) {
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.isExpanded = isExpanded
    self.overflowIndices = overflowIndices
    self.leadingWidth = leadingWidth
    controlIdentity = nil
  }

  package init(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    isExpanded: Bool,
    overflowIndices: [Int],
    leadingWidth: Int,
    controlIdentity: Identity
  ) {
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.isExpanded = isExpanded
    self.overflowIndices = overflowIndices
    self.leadingWidth = leadingWidth
    self.controlIdentity = controlIdentity
  }

  /// Installs the overflow trigger's pointer route around `content` so a
  /// click on it toggles the overflow menu.
  ///
  /// The framework supplies the identity. The same once-per-configuration rule
  /// as ``TabViewStyleItemConfiguration/route(content:)`` applies, it is
  /// likewise inert on a fixture, and omitting it leaves the menu reachable from
  /// the keyboard but not from the pointer.
  ///
  /// - Parameter content: The trigger's rendered appearance.
  /// - Returns: `content` with the trigger's pointer target around it.
  @ViewBuilder @MainActor
  public func route<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    styleRoute(
      target: controlIdentity.map { controlIdentity in
        StyleRouteTarget(
          identity: tabOverflowTriggerIdentity(for: controlIdentity),
          family: "TabViewStyle",
          role: "overflow trigger"
        )
      }, content: content())
  }
}

/// `Equatable` for the same memo-boundary reason as
/// ``TabViewStyleItemConfiguration``.
extension TabViewOverflowTriggerConfiguration: Equatable {}
/// `Equatable` so a style test can compare two resolved presentations with
/// `==` instead of field by field.
extension TabViewOverflowMenuPresentation: Equatable {}
extension TabViewStylePresentation: Equatable {}

/// The overflow surface a tab-view presentation asks for.
///
/// A style returns one of these in ``TabViewStylePresentation/overflowMenu``
/// when some options do not fit the strip. Its indices are validated with the
/// rest of the presentation: they must index the options, must not repeat, and
/// must not also be visible.
public struct TabViewOverflowMenuPresentation: Sendable {
  /// The width in cells the visible tabs occupy before the trigger, so a style
  /// can align an expanded menu under it.
  public var triggerLeadingWidth: Int

  /// The option indices held behind the trigger, in strip order. They must index
  /// ``TabViewStyleConfiguration/options``, must not repeat, and must be
  /// disjoint from ``TabViewStylePresentation/visibleOptionIndices``.
  public var overflowIndices: [Int]

  /// Whether the menu is open. The tab view owns this flag and clears it when
  /// the overflow surface goes away.
  public var isExpanded: Bool

  /// The selected option's index when the selection is in the overflow, and
  /// `nil` otherwise.
  public var selectedOverflowIndex: Int?

  /// The focused option's index when focus is in the overflow, and `nil`
  /// otherwise.
  public var focusedOverflowIndex: Int?

  /// The text the trigger draws. The built-in literal-tabs strip uses `▾`, `▴`
  /// while expanded, and the filled `▼` and `▲` when the selection is in the
  /// overflow.
  public var triggerLabel: String

  /// Cells of padding inside the menu, around the overflow rows. Defaults to
  /// `.zero`.
  public var contentPadding: EdgeInsets

  /// The fill painted behind the menu. `nil`, the default, leaves whatever is
  /// behind the menu showing through.
  public var backgroundStyle: AnyShapeStyle?

  /// The paint of the menu's border. `nil`, the default, draws no border.
  public var borderStyle: AnyShapeStyle?

  /// Reserved; the built-in hosting does not read it.
  ///
  /// ``LiteralTabsTabViewStyle`` sets it to `1`, but the built-in overflow menu
  /// draws its outline from ``borderStyle`` and ``cornerRadius`` alone. Defaults
  /// to `0`.
  public var borderInset: Int

  /// The corner radius of the menu's border, in cells. Defaults to `0`, a square
  /// corner.
  public var cornerRadius: Int

  /// Whether the selection is one of the overflowed options, which holds exactly
  /// when ``selectedOverflowIndex`` is not `nil`.
  public var isTriggerSelected: Bool {
    selectedOverflowIndex != nil
  }

  /// Whether focus is on one of the overflowed options, which holds exactly when
  /// ``focusedOverflowIndex`` is not `nil`.
  public var isTriggerFocused: Bool {
    focusedOverflowIndex != nil
  }

  /// The option an opening menu should focus: the focused overflow option, then
  /// the selected one, then the first. `nil` when ``overflowIndices`` is empty.
  public var preferredOverflowFocusIndex: Int? {
    focusedOverflowIndex ?? selectedOverflowIndex ?? overflowIndices.first
  }

  /// Creates an overflow-menu presentation.
  ///
  /// The appearance parameters all default to an unpainted, unpadded,
  /// square-cornered menu, so a style that only needs the index split can omit
  /// them.
  public init(
    triggerLeadingWidth: Int,
    overflowIndices: [Int],
    isExpanded: Bool,
    selectedOverflowIndex: Int?,
    focusedOverflowIndex: Int?,
    triggerLabel: String,
    contentPadding: EdgeInsets = .zero,
    backgroundStyle: AnyShapeStyle? = nil,
    borderStyle: AnyShapeStyle? = nil,
    borderInset: Int = 0,
    cornerRadius: Int = 0
  ) {
    self.triggerLeadingWidth = triggerLeadingWidth
    self.overflowIndices = overflowIndices
    self.isExpanded = isExpanded
    self.selectedOverflowIndex = selectedOverflowIndex
    self.focusedOverflowIndex = focusedOverflowIndex
    self.triggerLabel = triggerLabel
    self.contentPadding = contentPadding
    self.backgroundStyle = backgroundStyle
    self.borderStyle = borderStyle
    self.borderInset = borderInset
    self.cornerRadius = cornerRadius
  }
}

/// The strip geometry and overflow split a tab-view style resolves.
///
/// A tab view validates this value before the style's body runs. The strip
/// height must be nonnegative and no larger than a quarter of `Int.max`; the
/// visible indices must index the options and must not repeat; and an overflow
/// menu's indices must index the options, must not repeat, and must not also be
/// visible. A value that breaks any of those rules reports one
/// `style.invalidPresentation` issue and is replaced wholesale with
/// ``AnyTabViewStyle/automatic``'s presentation, while the style's own
/// ``TabViewStyle/makeBody(configuration:)`` still renders.
public struct TabViewStylePresentation: Sendable {
  /// The rows the tab strip occupies, in cells. The built-ins use `1`
  /// (powerline), `2` (underline and automatic), and `3` (literal tabs).
  public var stripHeight: Int

  /// The option indices drawn in the strip, in the order they are drawn.
  public var visibleOptionIndices: [Int]

  /// The overflow surface for the options that did not fit, or `nil` when every
  /// option is in the strip.
  public var overflowMenu: TabViewOverflowMenuPresentation?

  /// Creates a tab-view presentation.
  ///
  /// - Parameters:
  ///   - stripHeight: The rows the strip occupies, in cells.
  ///   - visibleOptionIndices: The options to draw in the strip, in draw order.
  ///   - overflowMenu: The overflow surface, or `nil` for no overflow.
  public init(
    stripHeight: Int,
    visibleOptionIndices: [Int],
    overflowMenu: TabViewOverflowMenuPresentation?
  ) {
    self.stripHeight = stripHeight
    self.visibleOptionIndices = visibleOptionIndices
    self.overflowMenu = overflowMenu
  }
}

extension TabViewStylePresentation {
  /// Why this value cannot drive a tab view with `optionCount` options: a
  /// negative or unrepresentable strip height, a visible index outside the
  /// options or repeated, or an overflow index outside the options, repeated,
  /// or also visible. Empty when the value is valid.
  package func validationProblems(optionCount: Int) -> [String] {
    var problems: [String] = []
    if stripHeight < 0 || stripHeight > AnchoredSurfaceStylePresentation.representableCellCount {
      problems.append("stripHeight must be a nonnegative representable cell count")
    }
    let options = 0..<max(optionCount, 0)
    let visible = Set(visibleOptionIndices)
    if visibleOptionIndices.contains(where: { !options.contains($0) }) {
      problems.append("visibleOptionIndices must index the options")
    }
    if visible.count != visibleOptionIndices.count {
      problems.append("visibleOptionIndices must not repeat")
    }
    guard let overflowMenu else {
      return problems
    }
    let overflow = Set(overflowMenu.overflowIndices)
    if overflowMenu.overflowIndices.contains(where: { !options.contains($0) }) {
      problems.append("overflowMenu.overflowIndices must index the options")
    }
    if overflow.count != overflowMenu.overflowIndices.count {
      problems.append("overflowMenu.overflowIndices must not repeat")
    }
    if !overflow.isDisjoint(with: visible) {
      problems.append("overflowMenu.overflowIndices must not also be visible")
    }
    return problems
  }
}

/// The tab state a style resolves its presentation from.
///
/// Every member is read-only render state: there is no authored view slot and no
/// binding here, because changing the selection is the tab view's own job. This
/// is the input to ``TabViewStyle/presentation(for:)``; the richer
/// ``TabViewStyleBodyConfiguration`` is the input to
/// ``TabViewStyle/makeBody(configuration:)``.
public struct TabViewStyleConfiguration: Sendable {
  /// The authored tabs in declaration order. Their positions are the indices the
  /// presentation's index lists refer to.
  public var options: [TabViewStyleOption]

  /// The selected option's index. It is `nil` only when there are no options: a
  /// tab view that has options always falls back to the first one.
  public var selectedIndex: Int?

  /// The option keyboard focus rests on, or `nil` when the strip is not focused.
  public var focusedIndex: Int?

  /// Whether focus rests on the tab strip.
  public var isFocused: Bool

  /// Whether the focus effect is enabled for this subtree. A style that paints
  /// focus chrome should do so only when this and ``isFocused`` are both `true`.
  public var showsFocusEffect: Bool

  /// The theme, appearance, inherited paints, and cell metrics captured from the
  /// environment, for deriving colors instead of hardcoding them.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The width in cells the strip may occupy, from the current proposal or the
  /// terminal's safe area. A style measures its labels against it to decide what
  /// overflows.
  public var availableWidth: Int

  /// Whether the tab view's overflow menu is currently open. It is the tab
  /// view's stored state, and it is cleared when the overflow surface goes away.
  public var isOverflowMenuExpanded: Bool

  /// The framework's construction path.
  ///
  /// Unlike the other families in this group it is ordinary public rather than
  /// `@_spi(StyleFixtures)`, so a style test builds one directly without
  /// importing the fixture SPI (see <doc:Testing-Styles>).
  public init(
    options: [TabViewStyleOption],
    selectedIndex: Int?,
    focusedIndex: Int?,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    availableWidth: Int,
    isOverflowMenuExpanded: Bool
  ) {
    self.options = options
    self.selectedIndex = selectedIndex
    self.focusedIndex = focusedIndex
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
    self.availableWidth = availableWidth
    self.isOverflowMenuExpanded = isOverflowMenuExpanded
  }
}

/// Everything a tab-view style's body is built from.
///
/// It pairs the strip state of ``TabViewStyleConfiguration`` with the validated
/// ``presentation``, the per-item configurations, the overflow trigger, and the
/// ``content`` slot holding the active tab's authored body. Its members fall
/// into two groups: ``content`` is a captured authored slot, and everything else
/// is read-only render state.
///
/// The item lists are derived rather than authored. ``items`` has one entry per
/// option; ``visibleItems`` and ``overflowItems`` are the subsets the
/// presentation named, in the presentation's order, with any index that does not
/// address an item dropped.
public struct TabViewStyleBodyConfiguration: Sendable {
  /// The active tab's authored content, as a view a style places in its body.
  ///
  /// Placing it in the body renders the selected tab's authored content with its
  /// own state and authoring scope intact, including the dormant-state archive
  /// that lets an unselected tab keep its state. A style that omits it renders a
  /// strip with nothing under it.
  public struct Content: PrimitiveView, ResolvableView, Sendable {
    package var payload: LazySubviewPayload?
    /// The declaring `TabView`'s control identity — the identity focus rests
    /// on while the tab strip is focused. Recorded so the content slot can
    /// declare itself focus-presentation-inert for that control: the values
    /// this slot receives derive from the authored tabs and the selection
    /// only, never from the control's focus/press presentation, so a focus
    /// move onto/off the strip must not pull the whole content subtree into
    /// the retained-reuse suppression cone.
    package var controlIdentity: Identity?
    /// Entity lifetime for the active tab generation. Descendant exact IDs
    /// scope to this route, so replacing the TabView owner resets them while a
    /// reorder within the same owner preserves them.
    package var payloadEntityIdentity: EntityIdentity?
    /// Owner-scoped authored identity for the structural child below the
    /// dormant entity host. This keeps different tab lifetimes out of the
    /// same identity-index slot without retaining a graph-node address.
    package var payloadStructuralIdentity: TabDormantPayloadStructuralIdentity?
    /// Reports a value-only locator for the freshly resolved payload back to
    /// its declaring TabView. The sink captures the owner weakly, so retained
    /// style/evaluator values cannot form a graph-node cycle.
    package var dormantArchiveLocatorSink:
      (@MainActor @Sendable (DormantStateArchiveLocator) -> Void)?

    package init(
      payload: LazySubviewPayload?,
      controlIdentity: Identity? = nil,
      payloadEntityIdentity: EntityIdentity? = nil,
      payloadStructuralIdentity: TabDormantPayloadStructuralIdentity? = nil,
      dormantArchiveLocatorSink:
        (@MainActor @Sendable (DormantStateArchiveLocator) -> Void)? = nil
    ) {
      self.payload = payload
      self.controlIdentity = controlIdentity
      self.payloadEntityIdentity = payloadEntityIdentity
      self.payloadStructuralIdentity = payloadStructuralIdentity
      self.dormantArchiveLocatorSink = dormantArchiveLocatorSink
    }

    /// An empty content slot for a fixture-constructed configuration: it
    /// resolves to nothing.
    @_spi(StyleFixtures)
    public init() {
      self.init(payload: nil)
    }

    /// A content slot showing `content` for a fixture-constructed
    /// configuration. It resolves as an ordinary active tab body with no
    /// declaring tab view, so no dormant-state archive is involved.
    @_spi(StyleFixtures)
    public init<V: View>(
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      self.init(
        payload: LazySubviewPayload(
          tabBody: ScopedContentPayload(content: content),
          debugName: "TabBodyFixture"
        )
      )
    }

    package func resolveElements(
      in context: ResolveContext
    ) -> [ResolvedNode] {
      guard let payload else {
        return []
      }

      if let controlIdentity {
        // The style-owned `configuration.content` slot is itself independent
        // of focus presentation. Declare it before payload resolution so a
        // focus-only frame can reuse the slot without evaluating a node-less
        // authored payload body merely to reach the routed child below.
        context.viewGraph?.declareFocusPresentationInertSlot(
          context.identity,
          forControl: controlIdentity
        )
      }

      // Keep the style-owned content slot transparent while preserving the
      // lazy payload boundary that owns active-tab lifecycle and state.
      let payloadContext = context.child(
        component: .named("TabContentPayload")
      )
      let payloadRoute = payloadEntityIdentity.map {
        ResolveEntityRoute(
          identity: $0,
          structuralPath: payloadContext.structuralPath
        )
      }
      var child = withResolveEntityRoute(payloadRoute) {
        if let payloadEntityIdentity {
          payload.resolveInEntityRoutedHost(
            in: payloadContext,
            entityIdentity: payloadEntityIdentity,
            structuralIdentity: payloadStructuralIdentity
          )
        } else {
          payload.resolve(
            in: payloadContext,
            placementRoot: context
          )
        }
      }
      if child.entityIdentity == nil, let payloadEntityIdentity {
        child.attachingEntityIdentity(
          payloadEntityIdentity,
          at: payloadContext.structuralPath
        )
      }

      if let controlIdentity {
        // Also declare the identity the payload actually returned. Style-body
        // builder normalization may consume or rebase the authored slot, and
        // dirty-frontier entry can begin inside the entity-hosted content cone.
        context.viewGraph?.declareFocusPresentationInertSlot(
          child.identity,
          forControl: controlIdentity
        )
      }

      if payload.lifecyclePolicy == .dormantStatePreserving,
        let graph = context.viewGraph
      {
        dormantArchiveLocatorSink?(
          graph.dormantStateArchiveLocator(rootedAt: child)
        )
      }

      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("Group"),
          typeDiscriminator: ObjectIdentifier(SynthesizedGroupWrapperMarker.self),
          children: [child],
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction
        )
      ]
    }
  }

  /// The authored tabs in declaration order, as
  /// ``TabViewStyleConfiguration/options`` supplied them.
  public var options: [TabViewStyleOption]

  /// One item configuration per option, in declaration order, so the entry at a
  /// position matches the option at that position.
  public var items: [TabViewStyleItemConfiguration]

  /// The items the presentation put in the strip, in
  /// ``TabViewStylePresentation/visibleOptionIndices`` order. An index that does
  /// not address an item is dropped.
  public var visibleItems: [TabViewStyleItemConfiguration]

  /// The items the presentation put behind the overflow trigger, in
  /// ``TabViewOverflowMenuPresentation/overflowIndices`` order. Empty when there
  /// is no overflow menu.
  public var overflowItems: [TabViewStyleItemConfiguration]

  /// The selected option's index. It is `nil` only when there are no options.
  public var selectedIndex: Int?

  /// The option keyboard focus rests on, or `nil` when the strip is not focused.
  public var focusedIndex: Int?

  /// Whether focus rests on the tab strip.
  public var isFocused: Bool

  /// Whether the focus effect is enabled for this subtree. A style that paints
  /// focus chrome should do so only when this and ``isFocused`` are both `true`.
  public var showsFocusEffect: Bool

  /// The theme, appearance, inherited paints, and cell metrics captured from the
  /// environment, for deriving colors instead of hardcoding them.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The width in cells the strip may occupy, from the current proposal or the
  /// terminal's safe area.
  public var availableWidth: Int

  /// Whether the tab view's overflow menu is currently open.
  public var isOverflowMenuExpanded: Bool

  /// The validated presentation this body is built against. Its
  /// ``TabViewStylePresentation/stripHeight`` is the height the strip should
  /// take.
  public var presentation: TabViewStylePresentation

  /// The overflow trigger's render state, present exactly when ``presentation``
  /// carries an overflow menu.
  public var overflowTrigger: TabViewOverflowTriggerConfiguration?

  /// The active tab's authored content. Place it in the body to render the
  /// selected tab.
  public var content: Content

  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a
  /// live `TabView` (see <doc:Testing-Styles>).
  ///
  /// It does not mirror the stored properties. ``options`` and the seven strip
  /// fields are copied out of `styleConfiguration`, and ``visibleItems`` and
  /// ``overflowItems`` are derived by looking `items` up through
  /// `presentation`'s index lists, dropping any index that does not address an
  /// item. Pass the same `presentation` the style resolved, or the derived lists
  /// will not match the body it renders.
  ///
  /// - Parameters:
  ///   - styleConfiguration: The strip state the presentation was resolved from.
  ///   - presentation: The presentation that splits the items.
  ///   - items: One item configuration per option, in declaration order.
  ///   - overflowTrigger: The trigger's state, or `nil` for no overflow.
  ///   - content: The active tab's content slot.
  @_spi(StyleFixtures)
  public init(
    styleConfiguration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation,
    items: [TabViewStyleItemConfiguration],
    overflowTrigger: TabViewOverflowTriggerConfiguration?,
    content: Content
  ) {
    options = styleConfiguration.options
    self.items = items
    visibleItems = presentation.visibleOptionIndices.compactMap { index in
      items.indices.contains(index) ? items[index] : nil
    }
    overflowItems =
      presentation.overflowMenu?.overflowIndices.compactMap { index in
        items.indices.contains(index) ? items[index] : nil
      } ?? []
    selectedIndex = styleConfiguration.selectedIndex
    focusedIndex = styleConfiguration.focusedIndex
    isFocused = styleConfiguration.isFocused
    showsFocusEffect = styleConfiguration.showsFocusEffect
    styleEnvironment = styleConfiguration.styleEnvironment
    availableWidth = styleConfiguration.availableWidth
    isOverflowMenuExpanded = styleConfiguration.isOverflowMenuExpanded
    self.presentation = presentation
    self.overflowTrigger = overflowTrigger
    self.content = content
  }
}
