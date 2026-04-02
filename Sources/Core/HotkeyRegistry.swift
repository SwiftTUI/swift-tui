/// A registered hotkey binding with metadata for help display.
package struct HotkeyBinding: Equatable, Sendable {
  package var key: KeyPress
  package var label: String
  package var group: String?
  package var commandID: String?

  package init(
    key: KeyPress,
    label: String = "",
    group: String? = nil,
    commandID: String? = nil
  ) {
    self.key = key
    self.label = label
    self.group = group
    self.commandID = commandID
  }
}

package typealias HotkeyHandler = @MainActor (KeyPress) -> Bool

/// A retained hotkey registration tied to the subtree that authored it.
package struct HotkeyRegistrationSnapshot {
  package var identity: Identity
  package var binding: HotkeyBinding
  package var handler: HotkeyHandler

  package init(
    identity: Identity,
    binding: HotkeyBinding,
    handler: @escaping HotkeyHandler
  ) {
    self.identity = identity
    self.binding = binding
    self.handler = handler
  }
}

/// A focus-independent registry of hotkey bindings that dispatches key
/// combinations regardless of which view is focused.
///
/// Bindings are registered during view resolution (depth-first, innermost
/// first). Dispatch iterates in registration order so the most specific
/// handler wins.
@MainActor
package final class HotkeyRegistry: Equatable {
  package typealias Handler = HotkeyHandler

  private var entries: [HotkeyRegistrationSnapshot] = []

  package init() {}

  nonisolated package static func == (lhs: HotkeyRegistry, rhs: HotkeyRegistry) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity = .init(components: [] as [IdentityComponent]),
    binding: HotkeyBinding,
    handler: @escaping Handler
  ) {
    entries.append(
      .init(
        identity: identity,
        binding: binding,
        handler: handler
      )
    )
  }

  /// Dispatches a key press to all registered handlers. Returns `true` if
  /// any handler consumed the event.
  @discardableResult
  package func dispatch(_ keyPress: KeyPress) -> Bool {
    for entry in entries {
      if entry.handler(keyPress) {
        return true
      }
    }
    return false
  }

  /// All registered bindings, for help display.
  package func registeredBindings() -> [HotkeyBinding] {
    entries.map(\.binding)
  }

  package func reset() {
    entries.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> [HotkeyRegistrationSnapshot] {
    entries
  }

  package func restore(_ snapshot: [HotkeyRegistrationSnapshot]) {
    guard !snapshot.isEmpty else {
      return
    }
    entries.append(contentsOf: snapshot)
  }
}
