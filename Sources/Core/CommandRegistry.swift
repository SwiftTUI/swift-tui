/// A `(KeyEvent, EventModifiers)` pair used as a command-registration
/// lookup key in `CommandRegistry`.
///
/// Distinct from the public `KeyPress` input-event type in
/// `LocalKeyHandlerRegistry.swift`. `KeyPress` represents a key event
/// arriving from the runtime; `KeyBinding` is the registration key a
/// command claims. Phase 4's `keyCommand` dispatch adapter translates
/// `KeyPress` → `KeyBinding` at the dispatch boundary, so consolidation
/// would destroy the intentional role separation.
package struct KeyBinding: Equatable, Hashable, Sendable {
  package var key: KeyEvent
  package var modifiers: EventModifiers

  package init(key: KeyEvent, modifiers: EventModifiers) {
    self.key = key
    self.modifiers = modifiers
  }
}

/// A registered key command.
package struct RegisteredKeyCommand: Sendable {
  package var binding: KeyBinding
  package var description: String
  package var isEnabled: Bool
  package var action: @MainActor @Sendable () -> Void

  package init(
    binding: KeyBinding,
    description: String,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.binding = binding
    self.description = description
    self.isEnabled = isEnabled
    self.action = action
  }
}

/// A registered palette command (no key binding).
package struct RegisteredPaletteCommand: Sendable {
  package var name: String
  package var description: String?
  package var isEnabled: Bool
  package var action: @MainActor @Sendable () -> Void

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

/// Collects commands declared at ActionScope roots and dispatches key
/// events to the shallowest claiming scope along the current focus
/// chain.
///
/// Registrations are scope-identity-keyed. Dispatch walks the supplied
/// `scopePath` from index 0 (shallowest) to the end (leafmost) and
/// consumes the event at the first scope whose registrations contain a
/// matching binding. If that match is disabled, the event is consumed
/// but no action fires — strict shallowest-wins semantics.
@MainActor
package final class CommandRegistry: Equatable {
  private var keyCommandsByScope: [Identity: [KeyBinding: RegisteredKeyCommand]] = [:]
  private var paletteCommandsByScope: [Identity: [RegisteredPaletteCommand]] = [:]

  package init() {}

  nonisolated package static func == (lhs: CommandRegistry, rhs: CommandRegistry) -> Bool {
    lhs === rhs
  }

  /// Registers (or replaces) a key command at the given scope identity.
  package func registerKeyCommand(
    at scope: Identity,
    binding: KeyBinding,
    description: String,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    var table = keyCommandsByScope[scope] ?? [:]
    table[binding] = RegisteredKeyCommand(
      binding: binding,
      description: description,
      isEnabled: isEnabled,
      action: action
    )
    keyCommandsByScope[scope] = table
  }

  /// Appends a palette command at the given scope identity.
  package func registerPaletteCommand(
    at scope: Identity,
    command: RegisteredPaletteCommand
  ) {
    var list = paletteCommandsByScope[scope] ?? []
    list.append(command)
    paletteCommandsByScope[scope] = list
  }

  /// Returns the registered key command at `scope` that matches
  /// `binding`, if any.
  package func keyCommand(
    at scope: Identity,
    matching binding: KeyBinding
  ) -> RegisteredKeyCommand? {
    keyCommandsByScope[scope]?[binding]
  }

  /// Returns all palette commands registered at `scope`.
  package func paletteCommands(at scope: Identity) -> [RegisteredPaletteCommand] {
    paletteCommandsByScope[scope] ?? []
  }

  /// Walks the focus chain shallowest-first and fires the first
  /// matching enabled keyCommand. A disabled match still consumes the
  /// event. Returns true if the event was consumed (fired or blocked)
  /// and false if no scope on the chain claims the binding.
  @discardableResult
  package func dispatch(
    key binding: KeyBinding,
    along scopePath: [Identity]
  ) -> Bool {
    for scope in scopePath {
      guard let match = keyCommand(at: scope, matching: binding) else {
        continue
      }
      if match.isEnabled {
        match.action()
      }
      return true
    }
    return false
  }

  /// Returns all palette commands visible along the given focus chain,
  /// ordered shallowest-first.
  package func paletteCommands(along scopePath: [Identity]) -> [RegisteredPaletteCommand] {
    scopePath.flatMap { paletteCommandsByScope[$0] ?? [] }
  }

  /// Clears every registration.
  package func reset() {
    keyCommandsByScope.removeAll(keepingCapacity: true)
    paletteCommandsByScope.removeAll(keepingCapacity: true)
  }
}
