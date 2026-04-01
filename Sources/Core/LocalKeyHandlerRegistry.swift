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
  public static let option = Self(rawValue: 1 << 1)
  public static let control = Self(rawValue: 1 << 2)
}

/// A key identity paired with modifier flags, used internally by the view layer.
/// A key identity paired with modifier flags.
public struct LocalKeyPress: Equatable, Hashable, Sendable {
  public var key: LocalKeyEvent
  public var modifiers: EventModifiers

  public init(_ key: LocalKeyEvent, modifiers: EventModifiers = []) {
    self.key = key
    self.modifiers = modifiers
  }
}

public enum LocalKeyEvent: Equatable, Hashable, Sendable {
  case character(Character)
  case enter
  case space
  case tab
  case shiftTab
  case arrowLeft
  case arrowRight
  case arrowUp
  case arrowDown
  case backspace
  case escape
  case ctrlC
}

@MainActor
package final class LocalKeyHandlerRegistry: Equatable {
  package typealias Handler = @MainActor (LocalKeyEvent) -> Bool
  package typealias KeyPressHandler = @MainActor (LocalKeyPress) -> Bool

  private var handlers: [Identity: Handler] = [:]
  private var keyPressHandlers: [Identity: KeyPressHandler] = [:]

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
  }

  package func register(
    identity: Identity,
    keyPressHandler: @escaping KeyPressHandler
  ) {
    keyPressHandlers[identity] = keyPressHandler
  }

  @discardableResult
  package func dispatch(
    identity: Identity,
    event: LocalKeyEvent
  ) -> Bool {
    handlers[identity]?(event) ?? false
  }

  @discardableResult
  package func dispatch(
    identity: Identity,
    keyPress: LocalKeyPress
  ) -> Bool {
    if let handler = keyPressHandlers[identity], handler(keyPress) {
      return true
    }
    return handlers[identity]?(keyPress.key) ?? false
  }

  package func hasHandler(
    identity: Identity
  ) -> Bool {
    handlers[identity] != nil || keyPressHandlers[identity] != nil
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
    keyPressHandlers.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> [Identity: Handler] {
    handlers
  }

  package func snapshotKeyPressHandlers() -> [Identity: KeyPressHandler] {
    keyPressHandlers
  }

  package func restore(_ snapshot: [Identity: Handler]) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handler) in snapshot {
      handlers[identity] = handler
    }
  }

  package func restoreKeyPressHandlers(_ snapshot: [Identity: KeyPressHandler]) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handler) in snapshot {
      keyPressHandlers[identity] = handler
    }
  }
}
