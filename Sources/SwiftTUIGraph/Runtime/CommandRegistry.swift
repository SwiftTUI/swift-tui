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

  /// Whether `key` may register and dispatch as a keyCommand with no
  /// modifiers. Function keys never produce text and are not consumed by
  /// text editing, so bare F-key commands are safe; every other key stays
  /// framework-reserved when unmodified (typing, arrow navigation, Tab,
  /// Enter, Escape).
  package static func allowsModifierlessCommands(for key: KeyEvent) -> Bool {
    if case .functionKey = key {
      return true
    }
    return false
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

package struct CommandRegistrySnapshot: Sendable {
  package var keyCommandsByScope: [Identity: [KeyBinding: RegisteredKeyCommand]]
  package var ownersByScope: [Identity: RuntimeRegistrationOwnerKey]

  package init(
    keyCommandsByScope: [Identity: [KeyBinding: RegisteredKeyCommand]] = [:],
    ownersByScope: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    self.keyCommandsByScope = keyCommandsByScope
    self.ownersByScope = ownersByScope
  }

  package var isEmpty: Bool {
    keyCommandsByScope.isEmpty
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
  private var ownersByScope: [Identity: RuntimeRegistrationOwnerKey] = [:]

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
    // No duplicate-overwrite alarm here (F104): this live table carries the
    // previous frame's entries across re-resolves (registration is eager;
    // publication reconciles later), so `table[binding] != nil` is the
    // NORMAL per-frame re-registration shape, not a collision — a
    // trace-enabled gate run false-positived 91 times on exactly this. The
    // node-record path can't see binding granularity either (it re-receives
    // this scope's whole merged table per registration), so the command
    // family stays unchecked.
    table[binding] = RegisteredKeyCommand(
      binding: binding,
      description: description,
      isEnabled: isEnabled,
      action: action
    )
    keyCommandsByScope[scope] = table
    ownersByScope[scope] = .current(identity: scope)
    ViewNodeContext.current?.recordCommandRegistration(
      CommandRegistrySnapshot(
        keyCommandsByScope: [scope: table],
        ownersByScope: [scope: ownersByScope[scope] ?? .init(identity: scope)]
      )
    )
  }

  /// Returns the registered key command at `scope` that matches
  /// `binding`, if any.
  package func keyCommand(
    at scope: Identity,
    matching binding: KeyBinding
  ) -> RegisteredKeyCommand? {
    keyCommandsByScope[scope]?[binding]
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

  /// Clears every registration.
  package func reset() {
    keyCommandsByScope.removeAll(keepingCapacity: true)
    ownersByScope.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> CommandRegistrySnapshot {
    CommandRegistrySnapshot(
      keyCommandsByScope: keyCommandsByScope,
      ownersByScope: ownersByScope
    )
  }

  package func restore(_ snapshot: CommandRegistrySnapshot) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, commands) in snapshot.keyCommandsByScope {
      keyCommandsByScope[identity] = commands
      ownersByScope[identity] = snapshot.ownersByScope[identity] ?? .init(identity: identity)
    }
  }

  /// Removes every key-command registered at any identity whose path is
  /// rooted at one of `roots`. Call this when a subtree is about to
  /// re-resolve in a partial invalidation pass, so re-registrations
  /// don't duplicate stale entries and abandoned scopes don't linger in
  /// dispatch lookups.
  package func removeSubtrees(rootedAt roots: [Identity]) {
    guard !roots.isEmpty else { return }
    for identity in keyCommandsByScope.keys
    where (ownersByScope[identity] ?? .init(identity: identity)).matchesAnySubtreeRoot(roots) {
      keyCommandsByScope.removeValue(forKey: identity)
      ownersByScope.removeValue(forKey: identity)
    }
  }
}
