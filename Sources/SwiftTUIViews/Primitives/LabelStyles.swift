public import SwiftTUICore

/// Defines the composition of a ``Label`` through its authored slots.
///
/// This is a body-producing family: the framework hands
/// ``LabelStyle/makeBody(configuration:)`` the captured title and icon, and
/// the view it returns renders in the label's place. Composition, spacing, and
/// paint are the customization; a style may place either slot anywhere,
/// decorate it, or leave it out.
///
/// A label is passive. Styling introduces no focus stop, action, or
/// accessibility role of its own, and controls authored inside a slot keep
/// their own behavior. A slot placed in the body keeps its authoring scope, so
/// state and tasks declared in it still belong to the declaration site. Unlike
/// ``ControlGroupStyle``, this family does not retain a slot's child state when
/// a style omits the slot or hosts it somewhere else, so keep a slot in the
/// body when its content owns state.
///
/// The built-ins are ``AnyLabelStyle/titleAndIcon`` (the icon first, then one
/// cell of spacing, then the title), ``AnyLabelStyle/titleOnly``, and
/// ``AnyLabelStyle/iconOnly``. ``AnyLabelStyle/automatic`` is a fixed alias of
/// `titleAndIcon`, not a fourth treatment. Apply a style with
/// `labelStyle(_:)`, which stores it in the environment for that subtree; the
/// nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform. A style
/// may store dynamic properties, which are prepared before `makeBody` runs.
///
/// ```swift
/// struct CaptionLabelStyle: LabelStyle {
///   func makeBody(configuration: LabelStyleConfiguration) -> some View {
///     VStack(alignment: .center, spacing: 0) {
///       configuration.icon
///       configuration.title.foregroundStyle(.separator)
///     }
///   }
/// }
///
/// Label("Save") { Text("*") }
///   .labelStyle(CaptionLabelStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol LabelStyle: Sendable {
  /// The view type ``LabelStyle/makeBody(configuration:)`` returns.
  associatedtype Body: View

  /// The name this style reports in snapshots, debug bundles, and style
  /// diagnostics.
  ///
  /// The default implementation returns the reflected type name; the built-ins
  /// pin theirs, such as `"AnyLabelStyle.iconOnly"`. It is diagnostic text and
  /// not identity, so nothing should branch on its value.
  var snapshotLabel: String { get }

  /// Composes the authored title and icon into the label's rendered body.
  ///
  /// The method runs on the main actor once per resolve of the styled label.
  ///
  /// - Parameter configuration: The captured title and icon slots plus the
  ///   style environment for this label.
  /// - Returns: The view that renders in the label's place.
  @ViewBuilder @MainActor
  func makeBody(configuration: LabelStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _labelStyleValueTypeWitness: Void { get }
}

extension LabelStyle {
  /// The reflected type name of the conformance, used when a style does not
  /// pin a label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _labelStyleValueTypeWitness: Void { () }
}

extension LabelStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to LabelStyle"
  )
  public static var _labelStyleValueTypeWitness: Void { () }
}

/// Authored slots and environment supplied to a ``LabelStyle``.
///
/// The configuration has two groups of members. ``LabelStyleConfiguration/title``
/// and ``LabelStyleConfiguration/icon`` are the captured authored slots: views
/// that render the content the label was declared with, keeping that content's
/// authoring scope. ``LabelStyleConfiguration/styleEnvironment`` is read-only
/// render state, the snapshot a style derives its paints from.
///
/// A label has no interactive state, so the configuration carries no binding
/// and no route wrapper. The framework builds this value while it resolves a
/// ``Label``; test targets build one directly through the fixture initializer
/// (see <doc:Testing-Styles>).
public struct LabelStyleConfiguration: Sendable {
  /// The captured, authored title.
  ///
  /// Placing this view in the body renders the title the label was declared
  /// with and keeps that content's state and authoring scope. Omitting it
  /// drops the title from the rendered label.
  public struct Title: View, Sendable {
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
    ///   title.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  /// The captured, authored icon.
  ///
  /// Placing this view in the body renders the icon or glyph view the label
  /// was declared with and keeps that content's state and authoring scope.
  /// Omitting it drops the icon from the rendered label.
  public struct Icon: View, Sendable {
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
    ///   icon.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  /// The authored title slot, ready to place in the style's body.
  public var title: Title
  /// The authored icon slot, ready to place in the style's body.
  public var icon: Icon
  /// The appearance, theme, ambient paints, and cell metrics in effect where
  /// the label was declared.
  ///
  /// Built-in styles resolve every color through this snapshot; a custom style
  /// that calls `theme.style(for:)`, `resolvedStyle(for:)`, or the chrome
  /// helpers matches them.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs the configuration from fixture state for a style test without
  /// a live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    title: Title,
    icon: Icon,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.title = title
    self.icon = icon
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``LabelStyle``, the value the
/// environment carries.
///
/// `labelStyle(_:)` stores one of these for its subtree, and every built-in is
/// available as a static on this type. The value participates in retained
/// reuse: the stateless built-ins compare equal by type, and a custom style
/// compares by value when it conforms to `Equatable`.
public struct AnyLabelStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyLabelStyleBox

  /// Erases a concrete label style.
  ///
  /// - Parameter style: The conformance to store. Its `snapshotLabel` is
  ///   copied out for diagnostics.
  public init<S: LabelStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }

  /// The default label composition, a fixed alias of ``AnyLabelStyle/titleAndIcon``.
  public static var automatic: Self {
    Self(AutomaticLabelStyle())
  }

  /// The icon, one cell of spacing, then the title, aligned on their centers.
  public static var titleAndIcon: Self {
    Self(TitleAndIconLabelStyle())
  }

  /// The title alone, with the authored icon left out of the body.
  public static var titleOnly: Self {
    Self(TitleOnlyLabelStyle())
  }

  /// The icon alone, with the authored title left out of the body.
  public static var iconOnly: Self {
    Self(IconOnlyLabelStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: LabelStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyLabelStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` composition for ``Label``: a fixed alias of
/// ``TitleAndIconLabelStyle``.
///
/// It renders the same body as `titleAndIcon`, the icon followed by one cell of
/// spacing and the title, and differs only in the label it reports.
public struct AutomaticLabelStyle: LabelStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyLabelStyle.automatic" }

  /// Renders the icon, one cell of spacing, and the title in a
  /// center-aligned row.
  ///
  /// - Parameter configuration: The captured title and icon slots.
  /// - Returns: The row that renders in the label's place.
  @MainActor
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    TitleAndIconLabelStyleBody(configuration: configuration)
  }
}

extension LabelStyle where Self == AutomaticLabelStyle {
  /// The default label composition, a fixed alias of ``TitleAndIconLabelStyle``.
  public static var automatic: AutomaticLabelStyle { .init() }
}

extension AutomaticLabelStyle: ReuseTransparentStyle {}

/// The `titleAndIcon` composition for ``Label``: the icon, one cell of
/// spacing, then the title, aligned on their centers.
public struct TitleAndIconLabelStyle: LabelStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyLabelStyle.titleAndIcon" }

  /// Renders the icon, one cell of spacing, and the title in a
  /// center-aligned row.
  ///
  /// - Parameter configuration: The captured title and icon slots.
  /// - Returns: The row that renders in the label's place.
  @MainActor
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    TitleAndIconLabelStyleBody(configuration: configuration)
  }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
  /// The icon, one cell of spacing, then the title.
  public static var titleAndIcon: TitleAndIconLabelStyle { .init() }
}

extension TitleAndIconLabelStyle: ReuseTransparentStyle {}

/// The `titleOnly` composition for ``Label``: the title alone, with the
/// authored icon left out of the body.
public struct TitleOnlyLabelStyle: LabelStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyLabelStyle.titleOnly" }

  /// Renders the captured title and nothing else.
  ///
  /// - Parameter configuration: The captured title and icon slots.
  /// - Returns: The title slot, rendered in the label's place.
  @MainActor
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    TitleOnlyLabelStyleBody(configuration: configuration)
  }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
  /// The title alone, with the authored icon left out of the body.
  public static var titleOnly: TitleOnlyLabelStyle { .init() }
}

extension TitleOnlyLabelStyle: ReuseTransparentStyle {}

/// The `iconOnly` composition for ``Label``: the icon alone, with the
/// authored title left out of the body.
public struct IconOnlyLabelStyle: LabelStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyLabelStyle.iconOnly" }

  /// Renders the captured icon and nothing else.
  ///
  /// - Parameter configuration: The captured title and icon slots.
  /// - Returns: The icon slot, rendered in the label's place.
  @MainActor
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    IconOnlyLabelStyleBody(configuration: configuration)
  }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
  /// The icon alone, with the authored title left out of the body.
  public static var iconOnly: IconOnlyLabelStyle { .init() }
}

extension IconOnlyLabelStyle: ReuseTransparentStyle {}

private protocol AnyLabelStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(
    configuration: LabelStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyLabelStyleBox where S: LabelStyle {

  @MainActor
  func resolveBody(
    configuration: LabelStyleConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

private struct TitleAndIconLabelStyleBody: View {
  let configuration: LabelStyleConfiguration

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      configuration.icon
      configuration.title
    }
  }
}

private struct TitleOnlyLabelStyleBody: View {
  let configuration: LabelStyleConfiguration

  var body: some View { configuration.title }
}

private struct IconOnlyLabelStyleBody: View {
  let configuration: LabelStyleConfiguration

  var body: some View { configuration.icon }
}
