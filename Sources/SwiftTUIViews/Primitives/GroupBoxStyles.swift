public import SwiftTUICore

/// Defines the composition of a ``GroupBox`` through its authored slots.
///
/// This is a body-producing family: the framework hands
/// ``GroupBoxStyle/makeBody(configuration:)`` the optional label, the captured
/// content, and the control prominence in effect, and the view it returns
/// renders in the group box's place. The style owns the chrome: border,
/// padding, title placement, and paint.
///
/// A group box is passive. Styling introduces no focus stop, action, or
/// accessibility role of its own, and controls authored inside a slot keep
/// their own behavior. A slot placed in the body keeps its authoring scope, so
/// state and tasks declared in it still belong to the declaration site. Unlike
/// ``ControlGroupStyle``, this family does not retain a slot's child state when
/// a style omits the slot or hosts it somewhere else, so keep a slot in the
/// body when its content owns state.
///
/// To match the built-in chrome, read
/// `configuration.styleEnvironment.groupBoxChrome(prominence:)`: it returns the
/// foreground and border paints the bordered built-in draws, a neutral border
/// at standard prominence and the accent tone at
/// `ControlProminence.increased`.
///
/// ``AnyGroupBoxStyle/bordered`` frames the content in a rounded border with
/// one cell of interior padding; ``AnyGroupBoxStyle/plain`` renders the label
/// and content with no border or padding.
/// ``AnyGroupBoxStyle/automatic`` is a fixed alias of `bordered`, not a third
/// treatment. Apply a style with `groupBoxStyle(_:)`, which stores it in the
/// environment for that subtree; the nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform. A style
/// may store dynamic properties, which are prepared before `makeBody` runs.
///
/// ```swift
/// struct BracketGroupBoxStyle: GroupBoxStyle {
///   func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
///     let chrome = configuration.styleEnvironment.groupBoxChrome(
///       prominence: configuration.controlProminence)
///     return VStack(alignment: .leading, spacing: 0) {
///       if let label = configuration.label {
///         HStack(spacing: 1) {
///           Text("[")
///           label
///           Text("]")
///         }
///         .foregroundStyle(chrome.borderStyle)
///       }
///       configuration.content.padding(.leading, 1)
///     }
///   }
/// }
///
/// GroupBox("Deploy") { form }
///   .groupBoxStyle(BracketGroupBoxStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol GroupBoxStyle: Sendable {
  /// The view type ``GroupBoxStyle/makeBody(configuration:)`` returns.
  associatedtype Body: View

  /// The name this style reports in snapshots, debug bundles, and style
  /// diagnostics.
  ///
  /// The default implementation returns the reflected type name; the built-ins
  /// pin theirs, such as `"AnyGroupBoxStyle.plain"`. It is diagnostic text and
  /// not identity, so nothing should branch on its value.
  var snapshotLabel: String { get }

  /// Composes the optional label and the captured content into the group box's
  /// rendered body.
  ///
  /// The method runs on the main actor once per resolve of the styled group
  /// box.
  ///
  /// - Parameter configuration: The optional label slot, the content slot, the
  ///   control prominence, and the style environment for this group box.
  /// - Returns: The view that renders in the group box's place.
  @ViewBuilder @MainActor
  func makeBody(configuration: GroupBoxStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _groupBoxStyleValueTypeWitness: Void { get }
}

extension GroupBoxStyle {
  /// The reflected type name of the conformance, used when a style does not
  /// pin a label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _groupBoxStyleValueTypeWitness: Void { () }
}

extension GroupBoxStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to GroupBoxStyle"
  )
  public static var _groupBoxStyleValueTypeWitness: Void { () }
}

/// Authored slots and environment supplied to a ``GroupBoxStyle``.
///
/// The configuration has two groups of members.
/// ``GroupBoxStyleConfiguration/label`` and
/// ``GroupBoxStyleConfiguration/content`` are the captured authored slots:
/// views that render the content the group box was declared with, keeping that
/// content's authoring scope. ``GroupBoxStyleConfiguration/controlProminence``
/// and ``GroupBoxStyleConfiguration/styleEnvironment`` are read-only render
/// state.
///
/// A group box has no interactive state, so the configuration carries no
/// binding and no route wrapper. The framework builds this value while it
/// resolves a ``GroupBox``; test targets build one directly through the
/// fixture initializer (see <doc:Testing-Styles>).
public struct GroupBoxStyleConfiguration: Sendable {
  /// The captured, authored label.
  ///
  /// Placing this view in the body renders the title the group box was
  /// declared with and keeps that content's state and authoring scope. The
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

  /// The captured, authored content the box frames.
  ///
  /// Placing this view in the body renders the content the group box was
  /// declared with and keeps that content's state and authoring scope.
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

  /// The authored label slot, or `nil` when the group box was declared without
  /// a label.
  ///
  /// The distinction is by initializer, not by what the label renders: a group
  /// box declared with only a content builder has no label slot, while one
  /// declared with a label builder that returns `EmptyView` has a present slot
  /// that draws nothing. A style that reserves a title row should branch on
  /// this value rather than on the rendered height.
  public var label: Label?
  /// The authored content slot, ready to place in the style's body.
  public var content: Content
  /// The control prominence in effect where the group box was declared, read
  /// from the environment.
  ///
  /// The bordered built-in uses it to pick the border tone: neutral at
  /// `standard`, the accent tone at `increased`.
  public var controlProminence: ControlProminence
  /// The appearance, theme, ambient paints, and cell metrics in effect where
  /// the group box was declared.
  ///
  /// Call `groupBoxChrome(prominence:)` on it for the same foreground and
  /// border paints the bordered built-in draws.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs the configuration from fixture state for a style test without
  /// a live render (see <doc:Testing-Styles>).
  ///
  /// - Parameters:
  ///   - label: The label slot, or `nil` to model a group box declared without
  ///     one.
  @_spi(StyleFixtures)
  public init(
    label: Label?,
    content: Content,
    controlProminence: ControlProminence,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self.controlProminence = controlProminence
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``GroupBoxStyle``, the value the
/// environment carries.
///
/// `groupBoxStyle(_:)` stores one of these for its subtree, and every built-in
/// is available as a static on this type. The value participates in retained
/// reuse: the stateless built-ins compare equal by type, and a custom style
/// compares by value when it conforms to `Equatable`.
public struct AnyGroupBoxStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyGroupBoxStyleBox

  /// Erases a concrete group box style.
  ///
  /// - Parameter style: The conformance to store. Its `snapshotLabel` is
  ///   copied out for diagnostics.
  public init<S: GroupBoxStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }

  /// The default group box chrome, a fixed alias of
  /// ``AnyGroupBoxStyle/bordered``.
  public static var automatic: Self {
    Self(AutomaticGroupBoxStyle())
  }

  /// A label above content framed by a rounded border with one cell of
  /// interior padding, the border neutral at standard prominence and accent
  /// toned at increased prominence.
  public static var bordered: Self {
    Self(BorderedGroupBoxStyle())
  }

  /// The label above the content with no border and no padding.
  public static var plain: Self {
    Self(PlainGroupBoxStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: GroupBoxStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyGroupBoxStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` composition for ``GroupBox``: a fixed alias of
/// ``BorderedGroupBoxStyle``.
///
/// It renders the same bordered body and differs only in the label it reports.
public struct AutomaticGroupBoxStyle: GroupBoxStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyGroupBoxStyle.automatic" }

  /// Renders the bordered body: the optional label in the `separator` role
  /// above content that is padded one cell and framed by a rounded border.
  ///
  /// - Parameter configuration: The label and content slots, the control
  ///   prominence, and the style environment.
  /// - Returns: The framed column that renders in the group box's place.
  @MainActor
  public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    BorderedGroupBoxStyleBody(configuration: configuration)
  }
}

extension GroupBoxStyle where Self == AutomaticGroupBoxStyle {
  /// The default group box chrome, a fixed alias of ``BorderedGroupBoxStyle``.
  public static var automatic: AutomaticGroupBoxStyle { .init() }
}

extension AutomaticGroupBoxStyle: ReuseTransparentStyle {}

/// The `bordered` composition for ``GroupBox``: the optional label in the
/// `separator` role above content padded one cell on every side and framed by
/// a rounded border.
///
/// Both paints come from `groupBoxChrome(prominence:)`, so the border is
/// neutral at standard prominence and accent toned at increased prominence.
/// The body also carries a stack minimum-height hint covering the border and
/// its padded interior, plus the label row when one is present, so a box beside
/// a centered sibling keeps its chrome instead of collapsing.
public struct BorderedGroupBoxStyle: GroupBoxStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyGroupBoxStyle.bordered" }

  /// Renders the optional label above content that is padded one cell and
  /// framed by a rounded border in the chrome's border paint.
  ///
  /// - Parameter configuration: The label and content slots, the control
  ///   prominence, and the style environment.
  /// - Returns: The framed column that renders in the group box's place.
  @MainActor
  public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    BorderedGroupBoxStyleBody(configuration: configuration)
  }
}

extension GroupBoxStyle where Self == BorderedGroupBoxStyle {
  /// A label above content framed by a rounded border with one cell of
  /// interior padding.
  public static var bordered: BorderedGroupBoxStyle { .init() }
}

extension BorderedGroupBoxStyle: ReuseTransparentStyle {}

/// The `plain` composition for ``GroupBox``: the optional label in the
/// `separator` role above the content, with no border, padding, or minimum
/// height of its own.
public struct PlainGroupBoxStyle: GroupBoxStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyGroupBoxStyle.plain" }

  /// Renders the optional label above the content in a leading-aligned column
  /// with no chrome.
  ///
  /// - Parameter configuration: The label and content slots, the control
  ///   prominence, and the style environment.
  /// - Returns: The column that renders in the group box's place.
  @MainActor
  public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    PlainGroupBoxStyleBody(configuration: configuration)
  }
}

extension GroupBoxStyle where Self == PlainGroupBoxStyle {
  /// The label above the content with no border and no padding.
  public static var plain: PlainGroupBoxStyle { .init() }
}

extension PlainGroupBoxStyle: ReuseTransparentStyle {}

private protocol AnyGroupBoxStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(
    configuration: GroupBoxStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

extension ConcreteStyleBox: AnyGroupBoxStyleBox where S: GroupBoxStyle {

  @MainActor
  func resolveBody(
    configuration: GroupBoxStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

private struct BorderedGroupBoxStyleBody: View {
  let configuration: GroupBoxStyleConfiguration

  var body: some View {
    let chrome = configuration.styleEnvironment.groupBoxChrome(
      prominence: configuration.controlProminence)
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label {
        label.foregroundStyle(.separator)
      }
      VStack(alignment: .leading, spacing: 0) {
        configuration.content
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(chrome.borderStyle)
      }
      .foregroundStyle(chrome.foregroundStyle)
    }
    // A stack-minimum hint, not a flexible frame: a flexible frame fills any
    // finite height proposal, so a group box beside a centered sibling or
    // under a fixed-height parent would grow past its chrome.
    .layoutMetadata(.init(minimumHeight: (configuration.label == nil ? 0 : 1) + 3))
  }
}

private struct PlainGroupBoxStyleBody: View {
  let configuration: GroupBoxStyleConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label {
        label.foregroundStyle(.separator)
      }
      configuration.content
    }
  }
}
