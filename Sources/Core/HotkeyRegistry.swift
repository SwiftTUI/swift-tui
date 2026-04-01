/// A registered hotkey binding with metadata for help display.
package struct HotkeyBinding: Equatable, Sendable {
  package var key: LocalKeyPress
  package var label: String
  package var group: String?
  package var commandID: String?

  package init(
    key: LocalKeyPress,
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

/// A focus-independent registry of hotkey bindings that dispatches key
/// combinations regardless of which view is focused.
///
/// Bindings are registered during view resolution (depth-first, innermost
/// first). Dispatch iterates in registration order so the most specific
/// handler wins.
@MainActor
package final class HotkeyRegistry: Equatable {
  package typealias Handler = @MainActor (LocalKeyPress) -> Bool

  private var entries: [(binding: HotkeyBinding, handler: Handler)] = []

  package init() {}

  nonisolated package static func == (lhs: HotkeyRegistry, rhs: HotkeyRegistry) -> Bool {
    lhs === rhs
  }

  package func register(
    binding: HotkeyBinding,
    handler: @escaping Handler
  ) {
    entries.append((binding: binding, handler: handler))
  }

  /// Dispatches a key press to all registered handlers. Returns `true` if
  /// any handler consumed the event.
  @discardableResult
  package func dispatch(_ keyPress: LocalKeyPress) -> Bool {
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

  package func snapshot() -> [(binding: HotkeyBinding, handler: Handler)] {
    entries
  }

  package func restore(_ snapshot: [(binding: HotkeyBinding, handler: Handler)]) {
    guard !snapshot.isEmpty else {
      return
    }
    entries.append(contentsOf: snapshot)
  }
}
