/// The result of a key press handler.
public enum KeyPressResult: Equatable, Sendable {
  /// The key event was not handled and should propagate.
  case ignored
  /// The key event was consumed.
  case handled
}

/// Keyboard modifier flags shared across key and mouse events.
public struct EventModifiers: OptionSet, Equatable, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let shift = Self(rawValue: 1 << 0)
  public static let alt = Self(rawValue: 1 << 1)
  public static let ctrl = Self(rawValue: 1 << 2)
}

/// A key identity paired with modifier flags.
public struct KeyPress: Equatable, Hashable, Sendable {
  public var key: KeyEvent
  public var modifiers: EventModifiers

  public init(_ key: KeyEvent, modifiers: EventModifiers = []) {
    self.key = key
    self.modifiers = modifiers
  }
}

public enum KeyEvent: Equatable, Hashable, Sendable {
  case character(Character)
  case `return`
  case space
  case tab
  case arrowLeft
  case arrowRight
  case arrowUp
  case arrowDown
  case backspace
  case escape
  case home
  case end
}

@MainActor
package final class LocalKeyHandlerRegistry: Equatable {
  package typealias Handler = @MainActor (KeyEvent) -> Bool
  package typealias KeyPressHandler = @MainActor (KeyPress) -> Bool
  package typealias PasteHandler = @MainActor (String) -> Bool

  private var handlers: [Identity: Handler] = [:]
  private var keyPressHandlers: [Identity: [KeyPressHandler]] = [:]
  private var pasteHandlers: [Identity: [PasteHandler]] = [:]
  private var ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]

  package init() {}

  nonisolated package static func == (lhs: LocalKeyHandlerRegistry, rhs: LocalKeyHandlerRegistry)
    -> Bool
  {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    handler: @escaping Handler
  ) {
    handlers[identity] = handler
    ownersByIdentity[identity] = .current(identity: identity)
    ViewNodeContext.current?.recordKeyHandlerRegistration(
      identity: identity,
      handler: handler
    )
  }

  package func register(
    identity: Identity,
    keyPressHandler: @escaping KeyPressHandler
  ) {
    keyPressHandlers[identity, default: []].append(keyPressHandler)
    ownersByIdentity[identity] = .current(identity: identity)
    ViewNodeContext.current?.recordKeyPressHandlerRegistration(
      identity: identity,
      handler: keyPressHandler
    )
  }

  package func register(
    identity: Identity,
    pasteHandler: @escaping PasteHandler
  ) {
    pasteHandlers[identity, default: []].append(pasteHandler)
    ownersByIdentity[identity] = .current(identity: identity)
    ViewNodeContext.current?.recordPasteHandlerRegistration(
      identity: identity,
      handler: pasteHandler
    )
  }

  @discardableResult
  package func dispatch(
    identity: Identity,
    event: KeyEvent
  ) -> Bool {
    handlers[identity]?(event) ?? false
  }

  @discardableResult
  package func dispatch(
    identity: Identity,
    keyPress: KeyPress
  ) -> Bool {
    if let handlers = keyPressHandlers[identity] {
      for handler in handlers.reversed() {
        if handler(keyPress) {
          return true
        }
      }
    }
    return handlers[identity]?(keyPress.key) ?? false
  }

  @discardableResult
  package func dispatchPaste(
    identity: Identity,
    content: String
  ) -> Bool {
    guard let handlers = pasteHandlers[identity] else {
      return false
    }

    for handler in handlers.reversed() {
      if handler(content) {
        return true
      }
    }
    return false
  }

  package func hasHandler(
    identity: Identity
  ) -> Bool {
    handlers[identity] != nil || keyPressHandlers[identity]?.isEmpty == false
  }

  package func hasPasteHandler(
    identity: Identity
  ) -> Bool {
    pasteHandlers[identity]?.isEmpty == false
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
    keyPressHandlers.removeAll(keepingCapacity: true)
    pasteHandlers.removeAll(keepingCapacity: true)
    ownersByIdentity.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    for identity in handlers.keys.filter({ matchesAnySubtreeRoot($0, roots: roots) }) {
      handlers.removeValue(forKey: identity)
    }
    for identity in keyPressHandlers.keys.filter({ matchesAnySubtreeRoot($0, roots: roots) }) {
      keyPressHandlers.removeValue(forKey: identity)
    }
    for identity in pasteHandlers.keys.filter({ matchesAnySubtreeRoot($0, roots: roots) }) {
      pasteHandlers.removeValue(forKey: identity)
    }
    pruneOwnerMap()
  }

  package func snapshot() -> [Identity: Handler] {
    handlers
  }

  package func snapshotKeyPressHandlers() -> [Identity: [KeyPressHandler]] {
    keyPressHandlers
  }

  package func snapshotPasteHandlers() -> [Identity: [PasteHandler]] {
    pasteHandlers
  }

  package func restore(
    _ snapshot: [Identity: Handler],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handler) in snapshot {
      handlers[identity] = handler
      self.ownersByIdentity[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
    }
  }

  package func restoreKeyPressHandlers(
    _ snapshot: [Identity: [KeyPressHandler]],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handlers) in snapshot {
      keyPressHandlers[identity] = handlers
      self.ownersByIdentity[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
    }
  }

  package func restorePasteHandlers(
    _ snapshot: [Identity: [PasteHandler]],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handlers) in snapshot {
      pasteHandlers[identity] = handlers
      self.ownersByIdentity[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
    }
  }

  private func matchesAnySubtreeRoot(
    _ identity: Identity,
    roots: [Identity]
  ) -> Bool {
    (ownersByIdentity[identity] ?? .init(identity: identity)).matchesAnySubtreeRoot(roots)
  }

  private func pruneOwnerMap() {
    let liveIdentities = Set(handlers.keys)
      .union(keyPressHandlers.keys)
      .union(pasteHandlers.keys)
    ownersByIdentity = ownersByIdentity.filter { liveIdentities.contains($0.key) }
  }
}
