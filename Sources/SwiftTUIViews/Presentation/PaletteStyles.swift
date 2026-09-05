public import SwiftTUICore

/// Composes a command palette from its declaration's command data.
public protocol PaletteStyle: Sendable {
  associatedtype Body: View
  var snapshotLabel: String { get }
  @ViewBuilder @MainActor
  func makeBody(configuration: PaletteStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _paletteStyleValueTypeWitness: Void { get }
}

extension PaletteStyle {
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
public struct PaletteStyleConfiguration: Sendable {
  public struct Command: Identifiable, Sendable {
    /// Opaque contribution identity, independent of its displayed strings.
    public var id: AnyID
    public var name: String
    public var description: String?
    public var isEnabled: Bool
    private var routeIdentity: Identity?
    private var activation: (@MainActor @Sendable () -> Void)?

    /// Constructs command data with an inert route and activation method.
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
    @ViewBuilder @MainActor
    public func route<Content: View>(@ViewBuilder content: () -> Content) -> some View {
      if let routeIdentity {
        StyleRouteView(
          target: .init(identity: routeIdentity, family: "PaletteStyle", role: "command"),
          content: content())
      } else {
        content()
      }
    }

    /// Invokes the enabled contribution and requests coordinated dismissal.
    /// Changing displayed command data cannot enable a disabled contribution.
    @MainActor public func perform() {
      guard isEnabled else { return }
      activation?()
    }
  }

  public var title: String
  public var commands: [Command]
  public var terminalSize: CellSize
  public var controlProminence: ControlProminence
  public var styleEnvironment: StyleEnvironmentSnapshot
  private var dismissal: (@MainActor @Sendable () -> Void)?

  /// Constructs an inert palette fixture without a presentation binding.
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
  @MainActor public func dismiss() { dismissal?() }

  package mutating func bindDismissal(_ dismissal: @escaping @MainActor @Sendable () -> Void) {
    self.dismissal = dismissal
  }
}

/// Type-erased storage for a concrete palette style.
public struct AnyPaletteStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyPaletteStyleBox

  public init<S: PaletteStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyPaletteStyleBox(style: style)
  }
  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }
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

private protocol AnyPaletteStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyPaletteStyleBox) -> Bool
  @MainActor func resolveBody(configuration: PaletteStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

private struct ConcreteAnyPaletteStyleBox<S: PaletteStyle>: AnyPaletteStyleBox {
  let style: S
  func isEqualForReuse(to other: any AnyPaletteStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
  @MainActor
  func resolveBody(configuration: PaletteStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel, in: context)
  }
}
