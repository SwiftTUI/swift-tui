public import SwiftTUICore

/// Defines the composition of a ``ControlGroup`` through its authored slots.
///
/// This is a body-producing family: the framework hands
/// ``ControlGroupStyle/makeBody(configuration:)`` the optional label and the
/// captured controls, and the view it returns renders in the group's place. A
/// style chooses the arrangement, which is why the same declaration can render
/// as a row, a column, or a menu of commands.
///
/// The group's content is a sequence, not one view: the authored children lay
/// out as distinct children of whatever stack the style puts them in. It also
/// carries retention, which is what separates this family from ``LabelStyle``,
/// ``LabeledContentStyle``, and ``GroupBoxStyle``. The declaring group owns its
/// children's state across hosts, so switching between an inline layout and the
/// compact menu keeps typed text and counters. Content a style omits, such as
/// the commands of a closed compact menu, has no live focus targets and no live
/// actions: its value-only state is archived rather than discarded, and tasks
/// declared in it are cancelled and start again when the content returns. Place
/// retained content once: composing `configuration.content` twice in one body
/// is unsupported.
///
/// Styling introduces no focus stop, action, or accessibility role of its own;
/// the controls inside the group keep their own behavior and focus order.
///
/// ``AnyControlGroupStyle/horizontal`` lays the controls out in a row,
/// ``AnyControlGroupStyle/vertical`` in a column, and
/// ``AnyControlGroupStyle/compactMenu`` inside a ``Menu``.
/// ``AnyControlGroupStyle/automatic`` is a fixed alias of `horizontal`, not a
/// fourth treatment. Apply a style with `controlGroupStyle(_:)`, which stores
/// it in the environment for that subtree; the nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform. A style
/// may store dynamic properties, which are prepared before `makeBody` runs.
///
/// ```swift
/// struct NumberedControlGroupStyle: ControlGroupStyle {
///   func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
///     VStack(alignment: .leading, spacing: 1) {
///       if let label = configuration.label {
///         label.foregroundStyle(.separator)
///       }
///       configuration.content
///     }
///   }
/// }
///
/// ControlGroup("Commands") {
///   Button("Run") { run() }
///   Button("Stop") { stop() }
/// }
/// .controlGroupStyle(NumberedControlGroupStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol ControlGroupStyle: Sendable {
  /// The view type ``ControlGroupStyle/makeBody(configuration:)`` returns.
  associatedtype Body: View

  /// The name this style reports in snapshots, debug bundles, and style
  /// diagnostics.
  ///
  /// The default implementation returns the reflected type name; the built-ins
  /// pin theirs, such as `"AnyControlGroupStyle.vertical"`. It is diagnostic
  /// text and not identity, so nothing should branch on its value.
  var snapshotLabel: String { get }

  /// Composes the optional label and the captured controls into the group's
  /// rendered body.
  ///
  /// The method runs on the main actor once per resolve of the styled group.
  ///
  /// - Parameter configuration: The optional label slot, the retained content
  ///   sequence, and the style environment for this group.
  /// - Returns: The view that renders in the control group's place.
  @ViewBuilder @MainActor
  func makeBody(configuration: ControlGroupStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _controlGroupStyleValueTypeWitness: Void { get }
}

extension ControlGroupStyle {
  /// The reflected type name of the conformance, used when a style does not
  /// pin a label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _controlGroupStyleValueTypeWitness: Void { () }
}

extension ControlGroupStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to ControlGroupStyle"
  )
  public static var _controlGroupStyleValueTypeWitness: Void { () }
}

/// Authored slots and environment supplied to a ``ControlGroupStyle``.
///
/// The configuration has two groups of members.
/// ``ControlGroupStyleConfiguration/label`` and
/// ``ControlGroupStyleConfiguration/content`` are the captured authored slots:
/// views that render what the group was declared with, keeping that content's
/// authoring scope. ``ControlGroupStyleConfiguration/styleEnvironment`` is
/// read-only render state, the snapshot a style derives its paints from.
///
/// The content slot is retained by the declaring group, so a style may host it
/// inline or inside a ``Menu`` without losing the controls' state. Place it
/// exactly once. A control group has no interactive state of its own, so the
/// configuration carries no binding and no route wrapper. The framework builds
/// this value while it resolves a ``ControlGroup``; test targets build one
/// directly through the fixture initializer (see <doc:Testing-Styles>).
public struct ControlGroupStyleConfiguration: Sendable {
  /// The captured, authored label.
  ///
  /// Placing this view in the body renders the title the group was declared
  /// with and keeps that content's state and authoring scope. The built-in
  /// inline styles paint it in the `separator` semantic role, and the compact
  /// built-in uses it as the menu's trigger title.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures content for a style test (see <doc:Testing-Styles>).
    ///
    /// - Parameter content: The view builder standing in for the authored
    ///   label.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  /// The captured, authored controls, as a sequence of distinct children.
  ///
  /// Each control the group was declared with stays a separate child of the
  /// stack the style places this view in, so a row or column spaces them
  /// individually rather than overlaying them as one group.
  ///
  /// The slot is retained by the declaring group: hosting it inline or inside
  /// a ``Menu`` preserves the controls' state, and omitting it archives their
  /// value-only state while removing their focus targets and actions and
  /// cancelling their tasks. Place it once per body; composing it twice is
  /// unsupported.
  public struct Content: View, Sendable {
    package let payloads: [ScopedContentPayload]
    package var retention: CapturedSubviewRetention? = nil

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payloads = withAuthoringContext(makeCapturedAuthoringContext(from: authoringContext)) {
        scopedDeclaredBuilderChildren(from: content())
      }
    }

    /// Captures content for a style test (see <doc:Testing-Styles>).
    ///
    /// A multi-statement builder produces the same distinct children a live
    /// group would hand the style, and the fixture slot carries no retention.
    ///
    /// - Parameter content: The view builder standing in for the authored
    ///   controls.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      self.init(authoringContext: currentAuthoringContext(), content: content)
    }

    /// The captured authored controls.
    public var body: some View {
      sequence
    }

    package var sequence: CapturedSubviewSequenceView {
      CapturedSubviewSequenceView(payloads: payloads, retention: retention)
    }
  }

  /// The authored label slot, or `nil` when the group was declared without a
  /// label.
  ///
  /// The distinction is by initializer, not by what the label renders: a group
  /// declared with only a content builder has no label slot, while one
  /// declared with a label builder that returns `EmptyView` has a present slot
  /// that draws nothing.
  public var label: Label?
  /// The authored controls, ready to place in the style's body exactly once.
  public var content: Content
  /// The appearance, theme, ambient paints, and cell metrics in effect where
  /// the group was declared.
  ///
  /// Built-in styles resolve every color through this snapshot; a custom style
  /// that calls `theme.style(for:)`, `resolvedStyle(for:)`, or the chrome
  /// helpers matches them.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs the configuration from fixture state for a style test without
  /// a live render (see <doc:Testing-Styles>).
  ///
  /// - Parameters:
  ///   - label: The label slot, or `nil` to model a group declared without
  ///     one.
  @_spi(StyleFixtures)
  public init(
    label: Label?,
    content: Content,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self.styleEnvironment = styleEnvironment
  }
}

extension ControlGroupStyleConfiguration.Content: ResolvableView, DeclaredChildrenView {
  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    sequence.makeResolveWork(in: context)
  }
  package func appendDeclaredChildrenWork(
    in context: ResolveContext, kindName: String, into state: DeclaredChildrenWorkState
  ) -> ResolveWork<Void> {
    sequence.appendDeclaredChildrenWork(in: context, kindName: kindName, into: state)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    sequence.resolveElements(in: context)
  }

  package func appendDeclaredChildren(
    in context: ResolveContext, kindName: String, nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    sequence.appendDeclaredChildren(
      in: context, kindName: kindName, nextIndex: &nextIndex, into: &resolved)
  }

  package func appendScopedDeclaredChildren(
    in context: DeclaredPayloadTraversalContext, kindName: String, nextIndex: inout Int,
    into children: inout [ScopedContentPayload]
  ) {
    sequence.appendScopedDeclaredChildren(
      in: context, kindName: kindName, nextIndex: &nextIndex, into: &children)
  }

  package func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext, kindName: String, nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  ) {
    sequence.appendPortalDeclaredChildren(
      in: context, kindName: kindName, nextIndex: &nextIndex, into: &children)
  }

  package func enumerateDeclaredChildren(
    in context: ResolveContext, kindName: String, nextIndex: inout Int,
    visitor: (Any, ResolveContext, @escaping @MainActor () -> ResolvedNode) -> Void
  ) {
    sequence.enumerateDeclaredChildren(
      in: context, kindName: kindName, nextIndex: &nextIndex, visitor: visitor)
  }
}

/// Type-erased storage for a concrete ``ControlGroupStyle``, the value the
/// environment carries.
///
/// `controlGroupStyle(_:)` stores one of these for its subtree, and every
/// built-in is available as a static on this type. The value participates in
/// retained reuse: the stateless built-ins compare equal by type, and a custom
/// style compares by value when it conforms to `Equatable`.
public struct AnyControlGroupStyle: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package let snapshotLabel: String
  private let box: any AnyControlGroupStyleBox

  /// Erases a concrete control group style.
  ///
  /// - Parameter style: The conformance to store. Its `snapshotLabel` is
  ///   copied out for diagnostics.
  public init<S: ControlGroupStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }

  /// The default control group layout, a fixed alias of
  /// ``AnyControlGroupStyle/horizontal``.
  public static var automatic: Self {
    Self(AutomaticControlGroupStyle())
  }

  /// The optional label above a row of the controls, one cell apart.
  public static var horizontal: Self {
    Self(HorizontalControlGroupStyle())
  }
  /// The controls inside a ``Menu`` whose trigger title is the group's label,
  /// or the fixed text "Controls" when the group has none.
  public static var compactMenu: Self {
    Self(CompactMenuControlGroupStyle())
  }

  /// The optional label above a leading-aligned column of the controls, one
  /// cell apart.
  public static var vertical: Self {
    Self(VerticalControlGroupStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: ControlGroupStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyControlGroupStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` composition for ``ControlGroup``: a fixed alias of
/// ``HorizontalControlGroupStyle``.
///
/// It renders the same row and differs only in the label it reports.
public struct AutomaticControlGroupStyle: ControlGroupStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyControlGroupStyle.automatic" }

  /// Renders the optional label in the `separator` role above a row of the
  /// controls spaced one cell apart.
  ///
  /// - Parameter configuration: The optional label and the retained controls.
  /// - Returns: The column that renders in the group's place.
  @MainActor
  public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    AutomaticControlGroupStyleBody(configuration: configuration)
  }
}

extension ControlGroupStyle where Self == AutomaticControlGroupStyle {
  /// The default control group layout, a fixed alias of
  /// ``HorizontalControlGroupStyle``.
  public static var automatic: AutomaticControlGroupStyle { .init() }
}

extension AutomaticControlGroupStyle: ReuseTransparentStyle {}

/// The `vertical` composition for ``ControlGroup``: the optional label in the
/// `separator` role above a leading-aligned column of the controls, one cell
/// apart.
public struct VerticalControlGroupStyle: ControlGroupStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyControlGroupStyle.vertical" }

  /// Renders the optional label above a leading-aligned column of the controls
  /// spaced one cell apart.
  ///
  /// - Parameter configuration: The optional label and the retained controls.
  /// - Returns: The column that renders in the group's place.
  @MainActor
  public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    VerticalControlGroupStyleBody(configuration: configuration)
  }
}

extension ControlGroupStyle where Self == VerticalControlGroupStyle {
  /// The optional label above a leading-aligned column of the controls.
  public static var vertical: VerticalControlGroupStyle { .init() }
}

extension VerticalControlGroupStyle: ReuseTransparentStyle {}

private protocol AnyControlGroupStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(
    configuration: ControlGroupStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyControlGroupStyleBox where S: ControlGroupStyle {

  @MainActor
  func resolveBody(
    configuration: ControlGroupStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

private struct AutomaticControlGroupStyleBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View { HorizontalControlGroupStyleBody(configuration: configuration) }
}

private struct HorizontalControlGroupStyleBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label { label.foregroundStyle(.separator) }
      HStack(spacing: 1) { configuration.content }
    }
  }
}

private struct VerticalControlGroupStyleBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label { label.foregroundStyle(.separator) }
      VStack(alignment: .leading, spacing: 1) { configuration.content }
    }
  }
}

private struct CompactMenuControlGroupStyleBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    Menu {
      if let label = configuration.label { label } else { Text("Controls") }
    } content: {
      configuration.content
    }
  }
}

/// The `horizontal` composition for ``ControlGroup``: the optional label in the
/// `separator` role above a row of the controls, one cell apart.
public struct HorizontalControlGroupStyle: ControlGroupStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyControlGroupStyle.horizontal" }
  /// Renders the optional label above a row of the controls spaced one cell
  /// apart.
  ///
  /// - Parameter configuration: The optional label and the retained controls.
  /// - Returns: The column that renders in the group's place.
  @MainActor
  public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    HorizontalControlGroupStyleBody(configuration: configuration)
  }
}
extension ControlGroupStyle where Self == HorizontalControlGroupStyle {
  /// The optional label above a row of the controls.
  public static var horizontal: HorizontalControlGroupStyle { .init() }
}
extension HorizontalControlGroupStyle: ReuseTransparentStyle {}

/// The `compactMenu` composition for ``ControlGroup``: the controls become the
/// commands of a public ``Menu``.
///
/// The menu's trigger title is the group's label, or the fixed text "Controls"
/// when the group was declared without one. Because the content slot is
/// retained, moving a group between this style and an inline one keeps the
/// controls' state; while the menu is closed the commands have no live focus
/// targets or actions and their tasks are cancelled. The menu contributes its
/// own trigger, focus stop, and Escape dismissal.
public struct CompactMenuControlGroupStyle: ControlGroupStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyControlGroupStyle.compactMenu" }
  /// Renders a ``Menu`` whose trigger is the group's label, or the text
  /// "Controls" when it has none, and whose commands are the group's controls.
  ///
  /// - Parameter configuration: The optional label and the retained controls.
  /// - Returns: The menu that renders in the group's place.
  @MainActor
  public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    CompactMenuControlGroupStyleBody(configuration: configuration)
  }
}
extension ControlGroupStyle where Self == CompactMenuControlGroupStyle {
  /// The controls inside a ``Menu`` whose trigger title is the group's label,
  /// or the fixed text "Controls" when the group has none.
  public static var compactMenu: CompactMenuControlGroupStyle { .init() }
}
extension CompactMenuControlGroupStyle: ReuseTransparentStyle {}
