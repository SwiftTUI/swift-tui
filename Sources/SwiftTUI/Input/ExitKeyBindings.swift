public import SwiftTUICore

/// The set of key presses that cause the interactive run loop to exit
/// with ``RunLoopExitReason/userExit(_:)``.
///
/// Configure per `WindowGroup` with ``WindowGroup/exitOnKeys(_:)`` or
/// ``WindowGroup/exitOnKey(_:modifiers:)``. Each call replaces the
/// previously configured set wholesale — there is no accumulation.
///
/// The default is a single binding: `Ctrl+C`. Pass an empty array to
/// disable framework-provided exit keys entirely; the runtime will then
/// only exit on OS signals, `stdin` EOF, or an explicit exit returned by
/// a consumer `keyHandler` / `keyCommand`.
///
/// Consumer `keyCommand`s registered at any in-focus scope win over the
/// exit bindings — scope dispatch runs first. This lets a focused view
/// claim `Ctrl+C` (or any other exit key) for domain-specific behavior
/// without removing the binding globally.
public struct ExitKeyBindings: Sendable, Equatable {
  public var keys: [KeyPress]

  public init(_ keys: [KeyPress]) {
    self.keys = keys
  }

  /// Framework default: `Ctrl+C`.
  public static let `default` = ExitKeyBindings([
    KeyPress(.character("c"), modifiers: .ctrl)
  ])

  /// No keys cause the run loop to exit.
  public static let none = ExitKeyBindings([])

  /// Returns `true` when `keyPress` is configured as an exit key.
  @inlinable
  public func contains(_ keyPress: KeyPress) -> Bool {
    keys.contains(keyPress)
  }
}
