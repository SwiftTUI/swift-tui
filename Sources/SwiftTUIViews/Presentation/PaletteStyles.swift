public import SwiftTUICore

/// Composes a command palette from its declaration's command data.
///
/// A palette style is a body-producing style:
/// ``PaletteStyle/makeBody(configuration:)`` returns the view the presented
/// palette renders. The ``PaletteStyleConfiguration`` hands it the palette's
/// title and the commands the scopes in effect contributed, each carrying its
/// display strings, whether it is enabled, an opaque identity, a
/// ``PaletteStyleConfiguration/Command/route(content:)`` wrapper, and a
/// ``PaletteStyleConfiguration/Command/perform()`` method; the configuration
/// itself carries ``PaletteStyleConfiguration/dismiss()``.
///
/// The style owns what the palette shows: filtering, ordering, selection, the
/// key handling inside its own body, and how a row looks. The declaration keeps
/// the presentation binding, the sheet the palette sits in, the contributions
/// themselves, and the rule that performing a command dismisses the palette. A
/// style cannot enable a disabled contribution or reach one the scope has
/// withdrawn.
///
/// The built-in ``AnyPaletteStyle/automatic`` is ``DefaultPaletteStyle``. Apply
/// one with `paletteStyle(_:)` outside the `paletteSheet(...)` declaration: the
/// palette reads the nearest style from the environment where the sheet is
/// declared, so a modifier applied to the sheet's own content is not read.
/// Conform with a `Sendable` struct or enum; a class cannot conform.
///
/// ```swift
/// struct TwoColumnPaletteStyle: PaletteStyle {
///   func makeBody(configuration: PaletteStyleConfiguration) -> some View {
///     VStack(alignment: .leading) {
///       Text(configuration.title)
///       ForEach(configuration.commands) { command in
///         command.route {
///           Button(command.name) { command.perform() }
///             .disabled(!command.isEnabled)
///         }
///       }
///       Button("Cancel") { configuration.dismiss() }
///     }
///   }
/// }
/// ```
///
/// See <doc:Style-System>, <doc:Authoring-Styles>, and
/// <doc:Commands-And-Key-Input>.
public protocol PaletteStyle: Sendable {
  /// The view type ``makeBody(configuration:)`` returns, normally inferred from
  /// the body.
  associatedtype Body: View
  /// The label reported in snapshots and diagnostics. Defaults to the reflected
  /// type name; the built-in pins `"AnyPaletteStyle.automatic"`. It is
  /// diagnostic text, not identity.
  var snapshotLabel: String { get }
  /// Builds the palette's body from its title, commands, and dismissal.
  ///
  /// Called on the main actor while the palette is presented. Wrap each row in
  /// that command's ``PaletteStyleConfiguration/Command/route(content:)`` so a
  /// pointer press reaches it, and call
  /// ``PaletteStyleConfiguration/Command/perform()`` to run one.
  ///
  /// - Parameter configuration: The palette's title, its commands, and the
  ///   render state.
  /// - Returns: The view the presented palette renders.
  @ViewBuilder @MainActor
  func makeBody(configuration: PaletteStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _paletteStyleValueTypeWitness: Void { get }
}

extension PaletteStyle {
  /// The reflected type name, used when a conformance does not pin a label.
  public var snapshotLabel: String { String(reflecting: Self.self) }
  @_documentation(visibility: internal)
  public static var _paletteStyleValueTypeWitness: Void { () }
}

extension PaletteStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to PaletteStyle"
  )
  public static var _paletteStyleValueTypeWitness: Void { () }
}

/// The title, commands, and source environment of a presented palette.
///
/// The commands are captured contribution data, not authored views: a style
/// draws its own row for each one and reaches its behavior through
/// ``Command/route(content:)`` and ``Command/perform()``. The remaining members
/// are read-only render state captured where the palette was declared, plus
/// ``dismiss()`` for closing the palette without running anything.
public struct PaletteStyleConfiguration: Sendable {
  /// One command contributed to the presented palette.
  ///
  /// The display strings, the enabled flag, and an opaque identity are data;
  /// the behavior is in ``route(content:)``, which marks a row as this
  /// command's pointer target, and ``perform()``, which runs it. A style may
  /// filter, reorder, and re-render commands freely, but the contribution
  /// itself belongs to the `paletteCommand(...)` declaration that supplied it.
  public struct Command: Identifiable, Sendable {
    /// Opaque contribution identity, independent of its displayed strings.
    public var id: AnyID
    /// The command's display name. ``DefaultPaletteStyle`` filters on this
    /// string and on nothing else.
    public var name: String
    /// Secondary text for the row, such as a hint about what the command does.
    /// `nil` when the contribution supplied none.
    public var description: String?
    /// Whether the contribution can run. Assigning to it on this copy changes
    /// only what a style draws: ``perform()`` checks the contribution behind
    /// the copy, so a disabled command stays inert.
    public var isEnabled: Bool
    private var routeIdentity: Identity?
    private var activation: (@MainActor @Sendable () -> Void)?

    /// Constructs command data with an inert route and activation method.
    ///
    /// The fixture form for a style test: ``route(content:)`` installs no
    /// pointer target and ``perform()`` does nothing, because no live
    /// contribution stands behind it (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<ID: Hashable & Sendable>(
      id: ID, name: String, description: String? = nil, isEnabled: Bool = true
    ) {
      self.id = AnyID(id)
      self.name = name
      self.description = description
      self.isEnabled = isEnabled
    }

    package init(
      contribution: ActivePaletteCommand, routeIdentity: Identity,
      activation: @escaping @MainActor @Sendable () -> Void
    ) {
      id = AnyID(contribution.identity)
      name = contribution.name
      description = contribution.description
      isEnabled = contribution.isEnabled
      self.routeIdentity = routeIdentity
      self.activation = activation
    }

    /// Marks content as this command's pointer activation target.
    ///
    /// Wrap the row a style draws for this command: the framework supplies the
    /// route identity, so a primary press anywhere inside `content` runs the
    /// command exactly as ``perform()`` does. Routing one command twice reports
    /// a `style.duplicateRoute` runtime issue and the first wrapper wins.
    /// Omitting the wrapper costs only the pointer target, and the style's own
    /// key handling still reaches ``perform()``. Inert on a fixture-built
    /// command.
    ///
    /// - Parameter content: The row to make clickable.
    /// - Returns: `content` carrying this command's pointer route.
    @ViewBuilder @MainActor
    public func route<Content: View>(@ViewBuilder content: () -> Content) -> some View {
      styleRoute(
        target: routeIdentity.map { routeIdentity in
          StyleRouteTarget(identity: routeIdentity, family: "PaletteStyle", role: "command")
        }, content: content())
    }

    /// Invokes the enabled contribution and requests coordinated dismissal.
    ///
    /// Runs the contribution's action and then closes the palette through the
    /// declaration's coordinator, so a style does not call
    /// ``PaletteStyleConfiguration/dismiss()`` as well. A disabled command does
    /// nothing, and changing displayed command data cannot enable a disabled
    /// contribution. Inert on a fixture-built command.
    @MainActor public func perform() {
      guard isEnabled else { return }
      activation?()
    }
  }

  /// The palette's title, as the presenting declaration supplied it.
  public var title: String
  /// The commands the scopes in effect contributed, in contribution order. A
  /// style filters, reorders, and renders them; it cannot add to them.
  public var commands: [Command]
  /// The terminal's size in cells when the palette resolved, for sizing the
  /// body relative to the terminal rather than to a fixed width.
  public var terminalSize: CellSize
  /// The `ControlProminence` in effect where the palette was declared.
  public var controlProminence: ControlProminence
  /// The `StyleEnvironmentSnapshot` where the palette was declared: the
  /// detected appearance, the active theme, the ambient paints, and the enabled
  /// state, from which a style derives its colors.
  public var styleEnvironment: StyleEnvironmentSnapshot
  private var dismissal: (@MainActor @Sendable () -> Void)?

  /// Constructs an inert palette fixture without a presentation binding.
  ///
  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style's body resolves against fixture state
  /// without a live render; ``dismiss()`` and every command's
  /// ``Command/perform()`` do nothing (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    title: String, commands: [Command], terminalSize: CellSize,
    controlProminence: ControlProminence, styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.title = title
    self.commands = commands
    self.terminalSize = terminalSize
    self.controlProminence = controlProminence
    self.styleEnvironment = styleEnvironment
  }

  /// Requests dismissal through the declaration's presentation coordinator.
  ///
  /// Closes the palette without running a command, which is what a cancel
  /// affordance in the body should call; the declaration's binding stays the
  /// source of truth for whether the palette is open (see
  /// <doc:Dismissal-Is-Data>). Running a command through
  /// ``Command/perform()`` already dismisses, so the two are not combined.
  /// Inert on a fixture.
  @MainActor public func dismiss() { dismissal?() }

  package mutating func bindDismissal(_ dismissal: @escaping @MainActor @Sendable () -> Void) {
    self.dismissal = dismissal
  }
}

/// Type-erased storage for a palette style, the value the environment carries.
///
/// `paletteStyle(_:)` stores one of these for a subtree; a presented palette
/// reads the nearest one. ``AnyPaletteStyle/automatic`` is the only built-in,
/// and ``AnyPaletteStyle/init(_:)`` wraps a custom conformance. The built-in
/// compares equal for retained reuse by type; a custom style compares by value
/// when it is `Equatable`.
public struct AnyPaletteStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyPaletteStyleBox

  /// Wraps `style` for storage in the environment.
  ///
  /// - Parameter style: The concrete ``PaletteStyle`` to erase.
  public init<S: PaletteStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }
  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }
  /// The framework palette: a filter field, keyboard selection, and up to
  /// twelve visible rows (``DefaultPaletteStyle``).
  public static var automatic: Self { Self(DefaultPaletteStyle()) }

  @MainActor
  package func resolveBody(configuration: PaletteStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyPaletteStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

private protocol AnyPaletteStyleBox: AnyStyleBox {
  @MainActor func resolveBody(configuration: PaletteStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

extension ConcreteStyleBox: AnyPaletteStyleBox where S: PaletteStyle {
  @MainActor
  func resolveBody(configuration: PaletteStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}
