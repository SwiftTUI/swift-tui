public import SwiftTUICore

/// Defines the composition of a ``LabeledContent`` through its authored slots.
///
/// This is a body-producing family: the framework hands
/// ``LabeledContentStyle/makeBody(configuration:)`` the captured label and
/// content, and the view it returns renders in the labeled content's place. A
/// style owns the arrangement, the spacing between the two slots, and any
/// leader, rule, or tint it draws around them.
///
/// A labeled content view is passive. Styling introduces no focus stop, action,
/// or accessibility role of its own, and controls authored inside a slot keep
/// their own behavior. A slot placed in the body keeps its authoring scope, so
/// state and tasks declared in it still belong to the declaration site. Unlike
/// ``ControlGroupStyle``, this family does not retain a slot's child state when
/// a style omits the slot or hosts it somewhere else, so keep a slot in the
/// body when its content owns state.
///
/// ``AnyLabeledContentStyle/automatic`` places the label and the content on one
/// baseline with a flexible spacer between them;
/// ``AnyLabeledContentStyle/stacked`` puts the content below the label. Both
/// paint the label in the `separator` semantic role. Apply a style with
/// `labeledContentStyle(_:)`, which stores it in the environment for that
/// subtree; the nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform. A style
/// may store dynamic properties, which are prepared before `makeBody` runs.
///
/// ```swift
/// struct DottedLeaderLabeledContentStyle: LabeledContentStyle {
///   func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
///     HStack(alignment: .firstTextBaseline, spacing: 1) {
///       configuration.label.foregroundStyle(.separator)
///       Text(String(repeating: "·", count: 8))
///       configuration.content
///     }
///   }
/// }
///
/// LabeledContent("Name", value: "Ada")
///   .labeledContentStyle(DottedLeaderLabeledContentStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol LabeledContentStyle: Sendable {
  /// The view type ``LabeledContentStyle/makeBody(configuration:)`` returns.
  associatedtype Body: View

  /// The name this style reports in snapshots, debug bundles, and style
  /// diagnostics.
  ///
  /// The default implementation returns the reflected type name; the built-ins
  /// pin theirs, such as `"AnyLabeledContentStyle.stacked"`. It is diagnostic
  /// text and not identity, so nothing should branch on its value.
  var snapshotLabel: String { get }

  /// Composes the authored label and content into the rendered body.
  ///
  /// The method runs on the main actor once per resolve of the styled view.
  ///
  /// - Parameter configuration: The captured label and content slots plus the
  ///   style environment for this declaration.
  /// - Returns: The view that renders in the labeled content's place.
  @ViewBuilder @MainActor
  func makeBody(configuration: LabeledContentStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _labeledContentStyleValueTypeWitness: Void { get }
}

extension LabeledContentStyle {
  /// The reflected type name of the conformance, used when a style does not
  /// pin a label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _labeledContentStyleValueTypeWitness: Void { () }
}

extension LabeledContentStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to LabeledContentStyle"
  )
  public static var _labeledContentStyleValueTypeWitness: Void { () }
}

/// Authored slots and environment supplied to a ``LabeledContentStyle``.
///
/// The configuration has two groups of members.
/// ``LabeledContentStyleConfiguration/label`` and
/// ``LabeledContentStyleConfiguration/content`` are the captured authored
/// slots: views that render the content the declaration was written with,
/// keeping that content's authoring scope.
/// ``LabeledContentStyleConfiguration/styleEnvironment`` is read-only render
/// state, the snapshot a style derives its paints from.
///
/// Both slots are always present, so neither is optional. The declaration has
/// no interactive state, so the configuration carries no binding and no route
/// wrapper. The framework builds this value while it resolves a
/// ``LabeledContent``; test targets build one directly through the fixture
/// initializer (see <doc:Testing-Styles>).
public struct LabeledContentStyleConfiguration: Sendable {
  /// The captured, authored label.
  ///
  /// Placing this view in the body renders the label the declaration was
  /// written with and keeps that content's state and authoring scope. The
  /// built-in styles paint it in the `separator` semantic role.
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

  /// The captured, authored content, which is the value side of the pair.
  ///
  /// Placing this view in the body renders the content the declaration was
  /// written with and keeps that content's state and authoring scope.
  public struct Content: View, Sendable {
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
    ///   content.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  /// The authored label slot, ready to place in the style's body.
  public var label: Label
  /// The authored content slot, ready to place in the style's body.
  public var content: Content
  /// The appearance, theme, ambient paints, and cell metrics in effect where
  /// the declaration appears.
  ///
  /// Built-in styles resolve every color through this snapshot; a custom style
  /// that calls `theme.style(for:)`, `resolvedStyle(for:)`, or the chrome
  /// helpers matches them.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs the configuration from fixture state for a style test without
  /// a live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    label: Label,
    content: Content,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``LabeledContentStyle``, the value the
/// environment carries.
///
/// `labeledContentStyle(_:)` stores one of these for its subtree, and every
/// built-in is available as a static on this type. The value participates in
/// retained reuse: the stateless built-ins compare equal by type, and a custom
/// style compares by value when it conforms to `Equatable`.
public struct AnyLabeledContentStyle: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package let snapshotLabel: String
  private let box: any AnyLabeledContentStyleBox

  /// Erases a concrete labeled content style.
  ///
  /// - Parameter style: The conformance to store. Its `snapshotLabel` is
  ///   copied out for diagnostics.
  public init<S: LabeledContentStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }

  /// The label and the content on one baseline, separated by a flexible
  /// spacer, with the label in the `separator` role.
  public static var automatic: Self {
    Self(AutomaticLabeledContentStyle())
  }

  /// The content on the line below the label, both leading-aligned and with no
  /// spacing between them.
  public static var stacked: Self {
    Self(StackedLabeledContentStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: LabeledContentStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyLabeledContentStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` composition for ``LabeledContent``: one row on the first
/// text baseline, the label in the `separator` role, a flexible spacer, then
/// the content.
///
/// The spacer pushes the content to the trailing edge of whatever width the
/// row is proposed, which is what lines several labeled rows up in a form.
public struct AutomaticLabeledContentStyle: LabeledContentStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyLabeledContentStyle.automatic" }

  /// Renders the label, a flexible spacer, and the content in a row aligned on
  /// the first text baseline.
  ///
  /// - Parameter configuration: The captured label and content slots.
  /// - Returns: The row that renders in the labeled content's place.
  @MainActor
  public func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    AutomaticLabeledContentStyleBody(configuration: configuration)
  }
}

extension LabeledContentStyle where Self == AutomaticLabeledContentStyle {
  /// The label and the content on one baseline, separated by a flexible
  /// spacer.
  public static var automatic: AutomaticLabeledContentStyle { .init() }
}

extension AutomaticLabeledContentStyle: ReuseTransparentStyle {}

/// The `stacked` composition for ``LabeledContent``: the label in the
/// `separator` role with the content on the line below it, both leading-aligned
/// and with no spacing between them.
public struct StackedLabeledContentStyle: LabeledContentStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyLabeledContentStyle.stacked" }

  /// Renders the label above the content in a leading-aligned column.
  ///
  /// - Parameter configuration: The captured label and content slots.
  /// - Returns: The column that renders in the labeled content's place.
  @MainActor
  public func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    StackedLabeledContentStyleBody(configuration: configuration)
  }
}

extension LabeledContentStyle where Self == StackedLabeledContentStyle {
  /// The content on the line below the label.
  public static var stacked: StackedLabeledContentStyle { .init() }
}

extension StackedLabeledContentStyle: ReuseTransparentStyle {}

private protocol AnyLabeledContentStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(
    configuration: LabeledContentStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

extension ConcreteStyleBox: AnyLabeledContentStyleBox where S: LabeledContentStyle {

  @MainActor
  func resolveBody(
    configuration: LabeledContentStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

private struct AutomaticLabeledContentStyleBody: View {
  let configuration: LabeledContentStyleConfiguration

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      configuration.label.foregroundStyle(.separator)
      Spacer()
      configuration.content
    }
  }
}

private struct StackedLabeledContentStyleBody: View {
  let configuration: LabeledContentStyleConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.label.foregroundStyle(.separator)
      configuration.content
    }
  }
}
