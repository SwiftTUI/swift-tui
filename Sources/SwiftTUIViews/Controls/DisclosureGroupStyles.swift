public import SwiftTUICore

/// Defines the visual composition of a ``DisclosureGroup``.
///
/// This is a body-producing family: the framework hands
/// ``DisclosureGroupStyle/makeBody(configuration:)`` the captured label, the
/// captured content, the expansion binding, and the group's render state, and
/// the view it returns renders in the group's place. The style owns the
/// disclosure glyph, the row treatment, and how far the content is indented.
///
/// ``DisclosureGroup`` keeps the focus stop, the keyboard activation that
/// toggles expansion, the accessibility role, and ownership of the binding. A
/// style composes around one route wrapper,
/// ``DisclosureGroupStyleConfiguration/trigger(content:)``, which is the
/// group's only pointer activation: wrap the label row in it so a press on the
/// expanded content leaves the expansion alone. A style that omits the wrapper
/// keeps keyboard toggling and gives up pointer toggling.
///
/// ``AnyDisclosureGroupStyle/automatic`` draws a focus rail beside the row and
/// ``AnyDisclosureGroupStyle/compact`` does not; the two are otherwise the same
/// treatment. Apply a style with `disclosureGroupStyle(_:)`, which stores it in
/// the environment for that subtree; the nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform. A style
/// may store dynamic properties, which are prepared before `makeBody` runs.
///
/// ```swift
/// struct PlusMinusDisclosureGroupStyle: DisclosureGroupStyle {
///   func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
///     VStack(alignment: .leading, spacing: 0) {
///       configuration.trigger {
///         HStack(spacing: 1) {
///           Text(configuration.isExpanded ? "−" : "+")
///           configuration.label
///         }
///       }
///       configuration.content.padding(.leading, 2)
///     }
///   }
/// }
///
/// DisclosureGroup("Details", isExpanded: $expanded) { detail }
///   .disclosureGroupStyle(PlusMinusDisclosureGroupStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol DisclosureGroupStyle: Sendable {
  /// The view type ``DisclosureGroupStyle/makeBody(configuration:)`` returns.
  associatedtype Body: View
  /// The name this style reports in snapshots, debug bundles, and style
  /// diagnostics.
  ///
  /// The default implementation returns the reflected type name; the built-ins
  /// pin theirs, such as `"AnyDisclosureGroupStyle.compact"`. It is diagnostic
  /// text and not identity, so nothing should branch on its value.
  var snapshotLabel: String { get }

  /// Composes the label row and the disclosed content into the group's
  /// rendered body.
  ///
  /// The method runs on the main actor once per resolve of the styled group,
  /// expanded or not.
  ///
  /// - Parameter configuration: The captured label and content, the expansion
  ///   binding, the render state, and the trigger wrapper for this group.
  /// - Returns: The view that renders in the disclosure group's place.
  @ViewBuilder @MainActor
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _disclosureGroupStyleValueTypeWitness: Void { get }
}

extension DisclosureGroupStyle {
  /// The reflected type name of the conformance, used when a style does not
  /// pin a label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _disclosureGroupStyleValueTypeWitness: Void { () }
}

extension DisclosureGroupStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI disclosure group styles must be value types (a struct or an enum); a class cannot conform to DisclosureGroupStyle"
  )
  public static var _disclosureGroupStyleValueTypeWitness: Void { () }
}

/// Authored content and primitive-owned state supplied to a ``DisclosureGroupStyle``.
///
/// The configuration has three groups of members.
/// ``DisclosureGroupStyleConfiguration/label`` and
/// ``DisclosureGroupStyleConfiguration/content`` are the captured authored
/// slots, which keep the authoring scope of the content the group was declared
/// with. ``DisclosureGroupStyleConfiguration/isExpanded`` is the primitive's
/// expansion binding, and the remaining values (`isEnabled`, `isFocused`,
/// `showsFocusEffect`, `isPressed`, `focusActive`, `styleEnvironment`) are
/// read-only render state.
/// ``DisclosureGroupStyleConfiguration/trigger(content:)`` is the group's one
/// route wrapper.
///
/// While the group is collapsed the primitive supplies an empty content slot,
/// so a style can place `content` unconditionally and use `isExpanded` only for
/// spacing and glyphs. The framework builds this value while it resolves a
/// ``DisclosureGroup``; test targets build one directly through the fixture
/// initializer, whose trigger wrapper installs nothing (see
/// <doc:Testing-Styles>).
public struct DisclosureGroupStyleConfiguration: Sendable {
  /// The captured authored label.
  ///
  /// Placing this view in the body renders the title the group was declared
  /// with and keeps that content's state and authoring scope. It belongs
  /// inside ``DisclosureGroupStyleConfiguration/trigger(content:)``, which
  /// makes the row it sits in the group's pointer target.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures authored content for a style fixture (see <doc:Testing-Styles>).
    ///
    /// - Parameter content: The view builder standing in for the authored
    ///   label.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The captured authored content the group discloses.
  ///
  /// The slot is empty while the group is collapsed: the primitive captures
  /// the authored content only when
  /// ``DisclosureGroupStyleConfiguration/isExpanded`` is true, so placing this
  /// view unconditionally renders nothing in the collapsed state. Placing it in
  /// the body keeps the authored content's state and authoring scope.
  public struct Content: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures authored content for a style fixture (see <doc:Testing-Styles>).
    ///
    /// - Parameter content: The view builder standing in for the authored
    ///   content.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The authored label slot, ready to place in the style's trigger row.
  public var label: Label
  /// The authored content slot, which renders nothing while the group is
  /// collapsed.
  public var content: Content
  /// Whether the group is expanded, projected as the primitive's own binding.
  ///
  /// Read it to pick the disclosure glyph and the content's spacing, and write
  /// it to expand or collapse the group from a view the style composes. The
  /// binding cannot be replaced, and writes are dropped while the group is
  /// disabled; it writes through to the binding the group was declared with.
  @Binding public var isExpanded: Bool
  /// Whether the group accepts activation. A disabled group keeps its current
  /// expansion and renders it.
  public var isEnabled: Bool
  /// Whether the group owns keyboard focus, regardless of the focus effect.
  public var isFocused: Bool
  /// Whether the environment permits a focus treatment;
  /// `focusEffectDisabled()` clears it while the group stays focused.
  public var showsFocusEffect: Bool
  /// Whether the pointer is currently pressing the group's trigger row.
  public var isPressed: Bool
  /// The appearance, theme, ambient paints, and cell metrics in effect where
  /// the group was declared.
  ///
  /// The built-in treatments derive their row paints from
  /// `rowChrome(isEnabled:isFocused:isPressed:)` on this snapshot.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Whether the group is focused and the focus effect is enabled.
  ///
  /// Read this rather than combining `isFocused` and `showsFocusEffect`
  /// yourself: a group under `focusEffectDisabled()` still toggles from the
  /// keyboard but must not draw a focus treatment.
  public var focusActive: Bool { isFocused && showsFocusEffect }
  private var controlIdentity: Identity?

  /// Constructs the configuration from fixture state for a style test without
  /// a live render (see <doc:Testing-Styles>).
  ///
  /// Supply `isExpanded` as a constant or write-counting binding to exercise
  /// both states; the fixture's trigger wrapper installs no pointer route.
  @_spi(StyleFixtures)
  public init(
    label: Label,
    content: Content,
    isExpanded: Binding<Bool>,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self._isExpanded = isExpanded
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.styleEnvironment = styleEnvironment
  }

  /// Routes a click on `content` to expansion toggling. Wrap the label row
  /// once: it is the group's only pointer activation, so a press on the
  /// expanded content leaves the expansion alone. Keyboard activation stays
  /// with the primitive when a style omits this wrapper, and a fixture
  /// configuration installs nothing.
  ///
  /// The framework supplies the route's identity, and a press on it toggles
  /// ``DisclosureGroupStyleConfiguration/isExpanded`` while the group is
  /// enabled. Installing the wrapper twice in one body reports
  /// `style.duplicateRoute`: the first installation stays the pointer target
  /// and the later one renders its content without one.
  ///
  /// - Parameter content: The trigger row to place behind the pointer target,
  ///   normally the disclosure glyph and the label.
  /// - Returns: The trigger row, with the group's pointer route installed
  ///   around it.
  @ViewBuilder @MainActor
  public func trigger<Trigger: View>(@ViewBuilder content: () -> Trigger) -> some View {
    styleRoute(
      target: controlIdentity.map { controlIdentity in
        StyleRouteTarget(
          identity: disclosureGroupTriggerIdentity(for: controlIdentity),
          family: "DisclosureGroupStyle", role: "trigger")
      }, content: content())
  }

  package mutating func bindRoutes(to identity: Identity) {
    controlIdentity = identity
  }
}

/// Type-erased storage for a concrete ``DisclosureGroupStyle``, the value the
/// environment carries.
///
/// `disclosureGroupStyle(_:)` stores one of these for its subtree, and every
/// built-in is available as a static on this type. The value participates in
/// retained reuse: the stateless built-ins compare equal by type, and a custom
/// style compares by value when it conforms to `Equatable`.
public struct AnyDisclosureGroupStyle: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package let snapshotLabel: String
  private let box: any AnyDisclosureGroupStyleBox

  /// Erases a concrete disclosure group style.
  ///
  /// - Parameter style: The conformance to store. Its `snapshotLabel` is
  ///   copied out for diagnostics.
  public init<S: DisclosureGroupStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }

  /// A disclosure glyph before the label with the content indented beneath,
  /// keeping one leading cell for the focus rail.
  public static var automatic: Self {
    Self(AutomaticDisclosureGroupStyle())
  }
  /// The same treatment without the focus rail, which relies on the row
  /// highlight alone and saves the leading cell.
  public static var compact: Self {
    Self(CompactDisclosureGroupStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: DisclosureGroupStyleConfiguration, in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyDisclosureGroupStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``DisclosureGroup``: a `▾` or `▸` glyph before
/// the label, the content indented one cell beneath, and one leading cell kept
/// for the focus rail.
///
/// The glyph takes the tint role while expanded and the `separator` role while
/// collapsed, and the row's paints come from the snapshot's row chrome. The
/// label row is wrapped in the configuration's trigger route, so a press on the
/// disclosed content does not collapse the group.
public struct AutomaticDisclosureGroupStyle: DisclosureGroupStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyDisclosureGroupStyle.automatic" }

  /// Renders the glyph and label as a rail-reserving trigger row, with the
  /// disclosed content indented beneath it while expanded.
  ///
  /// - Parameter configuration: The captured slots, render state, and trigger
  ///   wrapper for this group.
  /// - Returns: The column that renders in the group's place.
  @MainActor
  public func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    DisclosureGroupStyleBody(configuration: configuration, compact: false)
  }
}

extension DisclosureGroupStyle where Self == AutomaticDisclosureGroupStyle {
  /// A disclosure glyph before the label with the content indented beneath,
  /// keeping one leading cell for the focus rail.
  public static var automatic: AutomaticDisclosureGroupStyle { .init() }
}

extension AutomaticDisclosureGroupStyle: ReuseTransparentStyle {}

/// The `compact` treatment for ``DisclosureGroup``: the automatic composition
/// without the focus rail.
///
/// The row draws no rail cell at all, so a focused group is distinguished by
/// its highlight alone and the label starts one cell further left than under
/// ``AutomaticDisclosureGroupStyle``.
public struct CompactDisclosureGroupStyle: DisclosureGroupStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyDisclosureGroupStyle.compact" }

  /// Renders the glyph and label as a trigger row with no focus rail, with the
  /// disclosed content indented beneath it while expanded.
  ///
  /// - Parameter configuration: The captured slots, render state, and trigger
  ///   wrapper for this group.
  /// - Returns: The column that renders in the group's place.
  @MainActor
  public func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    DisclosureGroupStyleBody(configuration: configuration, compact: true)
  }
}

extension DisclosureGroupStyle where Self == CompactDisclosureGroupStyle {
  /// The automatic treatment without the focus rail.
  public static var compact: CompactDisclosureGroupStyle { .init() }
}

extension CompactDisclosureGroupStyle: ReuseTransparentStyle {}

private protocol AnyDisclosureGroupStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(configuration: DisclosureGroupStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyDisclosureGroupStyleBox where S: DisclosureGroupStyle {

  @MainActor
  func resolveBody(configuration: DisclosureGroupStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
  {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

/// The automatic and compact treatments: a disclosure glyph before the label,
/// with the content indented beneath. Compact drops the focus rail and relies
/// on the row highlight alone.
private struct DisclosureGroupStyleBody: View {
  let configuration: DisclosureGroupStyleConfiguration
  let compact: Bool

  var body: some View {
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger {
        ControlStyleRow(
          chrome: chrome, focusActive: configuration.focusActive,
          isHighlighted: configuration.focusActive || configuration.isPressed,
          reservesRail: !compact
        ) {
          Text(configuration.isExpanded ? "▾" : "▸")
            .foregroundStyle(
              configuration.isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
          configuration.label
        }
      }
      if configuration.isExpanded {
        configuration.content.padding(.leading, 1)
      }
    }
  }
}

/// The pointer route a ``DisclosureGroupStyleConfiguration/trigger(content:)``
/// wrapper installs for `control`.
package func disclosureGroupTriggerIdentity(for control: Identity) -> Identity {
  control.child(.named("DisclosureTrigger"))
}
