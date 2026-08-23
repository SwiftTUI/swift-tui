public import SwiftTUICore

/// The set of key presses that cause the interactive run loop to exit
/// with ``RunLoopExitReason/userExit(_:)``.
///
/// Configure per `WindowGroup` with ``WindowGroup/exitOnKeys(_:)`` or
/// ``WindowGroup/exitOnKey(_:modifiers:)``. Each call replaces the
/// previously configured set wholesale: there is no accumulation.
///
/// The default is a single binding: `Ctrl+C`. Pass an empty array to
/// disable framework-provided exit keys entirely. The runtime will then
/// only exit on OS signals, `stdin` EOF, or an explicit exit returned by
/// a consumer `keyHandler` / `keyCommand`.
///
/// Consumer `keyCommand`s and non-edit focused `onKeyPress` handlers win over
/// the exit bindings. This lets an app-owned mode claim a normally terminating
/// character while returning `.ignored` outside that mode so the same scene
/// binding still exits. A focused text input sees a *modified* exit chord
/// first, but only as an edit: `Ctrl+C` copies a non-empty selection and the
/// session continues, while the same key with nothing selected exits. A bare
/// character configured as an exit key still exits before the editor can
/// insert it.
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
