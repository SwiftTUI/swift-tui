public import SwiftTUICore

/// The set of key presses that cause the interactive run loop to exit
/// with ``RunLoopExitReason/userExit(_:)``.
///
/// Configure per `WindowGroup` with ``WindowGroup/exitOnKeys(_:)`` or
/// ``WindowGroup/exitOnKey(_:modifiers:)``. Each call replaces the
/// previously configured set wholesale — there is no accumulation.
///
/// The default is a single binding: `Ctrl+D`. Pass an empty array to
/// disable framework-provided exit keys entirely; the runtime will then
/// only exit on OS signals, `stdin` EOF, or an explicit exit returned by
/// a consumer `keyHandler` / `keyCommand`.
///
/// Consumer `keyCommand`s and non-edit focused `onKeyPress` handlers win over
/// the exit bindings. This lets an app-owned mode claim a normally terminating
/// character while returning `.ignored` outside that mode so the same scene
/// binding still exits. Native text-edit focus preserves the established
/// behavior in which an exit binding wins before text insertion.
public struct ExitKeyBindings: Sendable, Equatable {
  public var keys: [KeyPress]

  public init(_ keys: [KeyPress]) {
    self.keys = keys
  }

  /// Framework default: `Ctrl+D`.
  public static let `default` = ExitKeyBindings([
    KeyPress(.character("d"), modifiers: .ctrl)
  ])

  /// No keys cause the run loop to exit.
  public static let none = ExitKeyBindings([])

  /// Returns `true` when `keyPress` is configured as an exit key.
  @inlinable
  public func contains(_ keyPress: KeyPress) -> Bool {
    keys.contains(keyPress)
  }
}
