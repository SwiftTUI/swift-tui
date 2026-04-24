public import Core

/// A snapshot of a palette command visible from the current focus
/// chain, exposed via `EnvironmentValues.activePaletteCommands`.
///
/// Consumer-authored palette surfaces read this value to render and
/// dispatch the commands active at the current focus. The snapshot is
/// updated by the runtime after each frame, so a palette view that
/// reads it sees the commands authored by every scope on the current
/// focus chain — shallowest first.
public struct ActivePaletteCommand: Sendable {
  public let name: String
  public let description: String?
  public let isEnabled: Bool
  public let action: @MainActor @Sendable () -> Void

  package init(
    name: String,
    description: String?,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.name = name
    self.description = description
    self.isEnabled = isEnabled
    self.action = action
  }
}

private enum ActivePaletteCommandsKey: EnvironmentKey {
  static let defaultValue: [ActivePaletteCommand] = []
}

extension EnvironmentValues {
  /// The palette commands active along the current focus chain,
  /// ordered shallowest-first. Consumer-authored palette views read
  /// this to discover what actions the user can invoke now.
  public var activePaletteCommands: [ActivePaletteCommand] {
    get { self[ActivePaletteCommandsKey.self] }
    set { self[ActivePaletteCommandsKey.self] = newValue }
  }
}

extension ActionScope where Self: View & Sendable {
  /// Declares a searchable, consumer-invocable command at this scope's
  /// root. The framework does not ship a palette surface; consumer
  /// code is responsible for presenting a palette view and querying
  /// `EnvironmentValues.activePaletteCommands` to discover the
  /// commands visible from the current focus chain.
  ///
  /// Palette commands stack at each scope identity in authored order.
  /// A command remains visible while its scope is on the focus chain;
  /// disabled commands still appear so the palette can render them
  /// greyed out, but activating a disabled command is a no-op.
  @MainActor
  public func paletteCommand(
    name: String,
    description: String? = nil,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    modifier(
      PaletteCommandRegistrationModifier(
        name: name,
        description: description,
        isEnabled: isEnabled,
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }
}

public struct PaletteCommandRegistrationModifier: PrimitiveViewModifier, Sendable {
  package let name: String
  package let description: String?
  package let isEnabled: Bool
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  package let action: @MainActor @Sendable () -> Void

  package init(
    name: String,
    description: String?,
    isEnabled: Bool,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.name = name
    self.description = description
    self.isEnabled = isEnabled
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    let dynamicPropertyScope = currentImperativeAuthoringContextSnapshot() ?? authoringContext
    context.commandRegistry?.registerPaletteCommand(
      at: node.identity,
      command: RegisteredPaletteCommand(
        name: name,
        description: description,
        isEnabled: isEnabled,
        action: {
          withImperativeAuthoringContext(dynamicPropertyScope) {
            action()
          }
        }
      )
    )
    return [node]
  }
}
