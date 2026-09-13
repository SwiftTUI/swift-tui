public import SwiftTUICore

/// Resolves the connector and indent strings an outline draws its hierarchy with.
///
/// An outline style is a presentation-value style: it implements
/// ``OutlineStyle/resolvePresentation(for:)`` and returns an
/// `OutlineStylePresentation` holding four strings, one per prefix piece an
/// outline row can need. It never builds a body, so ``OutlineGroup`` keeps
/// expansion state, disclosure, selection, focus, keyboard navigation, and
/// accessibility semantics whatever the style resolves.
///
/// ASCII substitution is deliberately not an outline style: capability-driven
/// glyph degradation is rasterizer fallback behavior.
///
/// Apply a style with `outlineStyle(_:)`, which writes the public
/// `EnvironmentValues.outlineStyle` slot for the subtree, so the nearest
/// modifier above an outline wins. The built-ins are
/// ``AnyOutlineStyle/automatic``, ``AnyOutlineStyle/rounded``, and
/// ``AnyOutlineStyle/plain``; `.automatic` is a fixed alias of `.rounded`.
///
/// A conforming type must be a value type and `Sendable`, because the
/// environment carries it across resolves. The resolved presentation is not
/// validated and has no per-field fallback: the four strings are used as
/// returned, so keep each one a single terminal line of the same display width
/// as its siblings if the columns are to align.
///
/// ```swift
/// struct HeavyOutlineStyle: OutlineStyle {
///   var snapshotLabel: String { "HeavyOutlineStyle" }
///
///   func resolvePresentation(
///     for configuration: OutlineStyleConfiguration
///   ) -> OutlineStylePresentation {
///     .init(
///       continuingIndenter: "┃ ",
///       emptyIndenter: "  ",
///       branchConnector: "┣━ ",
///       leafConnector: "┗━ "
///     )
///   }
/// }
/// ```
///
/// See <doc:Style-System>, <doc:Authoring-Styles>, and <doc:Collections>.
public protocol OutlineStyle: Sendable {
  /// The label reported in snapshots and diagnostics.
  ///
  /// Diagnostic text, not identity: do not branch on it. ``AnyOutlineStyle``
  /// stamps this label onto the resolved presentation's `snapshotLabel`,
  /// replacing the variant label the presentation carried.
  var snapshotLabel: String { get }

  /// Resolves the connector and indent strings for one outline level.
  ///
  /// Called on the main actor while each outline level resolves. The returned
  /// value is used as returned; nothing about it is clamped or replaced.
  ///
  /// - Parameter configuration: The style environment for this resolve.
  /// - Returns: The indenters and connectors the outline rows are prefixed with.
  @MainActor
  func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation
}

extension OutlineStyle {
  /// The reflected type name, supplied when a conforming type declares no label.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state an outline style may consult.
///
/// Outline connector choice currently needs only the style environment, so this
/// carries no authored view slot, no binding, and no focus or selection state.
public struct OutlineStyleConfiguration: Sendable {
  /// The theme, appearance, inherited paints, and cell metrics captured from the
  /// environment, for deriving connectors that suit the terminal instead of
  /// hardcoding them.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a
  /// live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.styleEnvironment = styleEnvironment
  }
}

private protocol AnyOutlineStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  var debugDescription: String { get }

  @MainActor
  func presentation(for configuration: OutlineStyleConfiguration) -> OutlineStylePresentation
}

extension ConcreteStyleBox: AnyOutlineStyleBox where S: OutlineStyle {

  var snapshotLabel: String {
    style.snapshotLabel
  }

  var debugDescription: String {
    String(reflecting: style)
  }

  @MainActor
  func presentation(for configuration: OutlineStyleConfiguration) -> OutlineStylePresentation {
    var presentation = style.resolvePresentation(for: configuration)
    presentation.snapshotLabel = style.snapshotLabel
    return presentation
  }

}

/// Type-erased storage for an outline style, the value the environment carries.
///
/// This is the type of the public `EnvironmentValues.outlineStyle` slot, so an
/// outline row can read the style in force with
/// `@Environment(\.outlineStyle)`. Resolving through the eraser overwrites the
/// presentation's `snapshotLabel` with the wrapped style's label, so a
/// presentation variant label such as `"OutlineStylePresentation.rounded"`
/// survives only when ``OutlineStyle/resolvePresentation(for:)`` is called
/// directly.
public struct AnyOutlineStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyOutlineStyleBox

  /// Wraps a concrete outline style for storage in the environment.
  ///
  /// - Parameter style: The style to erase. It is kept boxed, so reuse
  ///   comparisons still see the concrete value.
  public init<S: OutlineStyle>(
    _ style: S
  ) {
    box = ConcreteStyleBox(style: style)
  }

  /// The default outline style, a fixed alias of ``rounded``.
  public static var automatic: Self {
    Self(AutomaticOutlineStyle())
  }

  /// Box-drawing connectors whose last child curves into its row: `"├─ "` for a
  /// row with siblings below it and `"╰─ "` for the last one, over `"│ "` and
  /// `"  "` indenters.
  public static var rounded: Self {
    Self(RoundedOutlineStyle())
  }

  /// The same connectors as ``rounded`` with a square last-child corner: `"└─ "`
  /// instead of `"╰─ "`.
  public static var plain: Self {
    Self(PlainOutlineStyle())
  }

  /// The wrapped style's ``OutlineStyle/snapshotLabel``.
  public var description: String {
    box.snapshotLabel
  }

  /// The wrapped style's ``OutlineStyle/snapshotLabel``, the same text as
  /// ``description``.
  public var debugDescription: String {
    box.snapshotLabel
  }

  @MainActor
  package func presentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    let resolved = box.presentation(for: configuration)
    return StyleMisuse.validatedPresentation(
      resolved, problems: resolved.validationProblems, family: "OutlineStyle",
      styleLabel: description, identity: ViewNodeContext.current?.identity,
      report: { ImperativeRuntimeIssueQueue.record($0) },
      fallback: { Self.automatic.box.presentation(for: configuration) }
    )
  }
}

extension AnyOutlineStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default outline style: a fixed alias of ``RoundedOutlineStyle``.
///
/// It resolves the same rounded connector set, and it does not consult the
/// configuration to do so.
public struct AutomaticOutlineStyle: OutlineStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics,
  /// `"OutlineStyle.automatic"`.
  public var snapshotLabel: String {
    "OutlineStyle.automatic"
  }

  /// Resolves the rounded connector set for every style environment.
  ///
  /// - Parameter configuration: The style environment, which this style ignores.
  /// - Returns: `OutlineStylePresentation.rounded`.
  @MainActor
  public func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    .rounded
  }
}

/// An outline style with rounded leaf connectors.
///
/// Rows carry `"│ "` where an ancestor continues below and two spaces where it
/// does not; a row with siblings after it is prefixed `"├─ "`, and the last row
/// of a level is prefixed `"╰─ "`.
public struct RoundedOutlineStyle: OutlineStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"OutlineStyle.rounded"`.
  public var snapshotLabel: String {
    "OutlineStyle.rounded"
  }

  /// Resolves the rounded connector set for every style environment.
  ///
  /// - Parameter configuration: The style environment, which this style ignores.
  /// - Returns: `OutlineStylePresentation.rounded`.
  @MainActor
  public func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    .rounded
  }
}

/// An outline style that uses box-drawing connectors throughout.
///
/// Identical to ``RoundedOutlineStyle`` except for the last row of a level,
/// which is prefixed with the square `"└─ "` rather than the curved `"╰─ "`.
public struct PlainOutlineStyle: OutlineStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"OutlineStyle.plain"`.
  public var snapshotLabel: String {
    "OutlineStyle.plain"
  }

  /// Resolves the square-cornered connector set for every style environment.
  ///
  /// - Parameter configuration: The style environment, which this style ignores.
  /// - Returns: `OutlineStylePresentation.plain`.
  @MainActor
  public func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    .plain
  }
}

extension AutomaticOutlineStyle: ReuseTransparentStyle {}
extension RoundedOutlineStyle: ReuseTransparentStyle {}
extension PlainOutlineStyle: ReuseTransparentStyle {}
