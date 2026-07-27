/// Suspends the live terminal input reader for the duration of `body`.
///
/// The terminal capability probes write a query escape sequence and then read
/// the reply from the *input* file descriptor — the same descriptor the live
/// ``InputReader``'s dispatch source owns once the run loop is up. Whichever
/// side wins the race consumes the reply: when the reader wins, the probe
/// burns its full timeout ladder (the historical 0.5–1 s first-image stall)
/// and mis-detects the terminal's graphics support (F42). Conformers
/// guarantee that, once `body` starts, no reader event handler is in flight
/// and none will fire until `body` returns — so the probe reads an
/// uncontended descriptor and real terminals answer in milliseconds.
package protocol TerminalInputSuspending: Sendable {
  func withInputSuspended<T>(_ body: () throws -> T) rethrows -> T
}

/// Extends descriptor-probe suspension across an awaited terminal handoff.
package protocol TerminalInputHandoffSuspending: TerminalInputSuspending {
  /// Suspends the live reader across an asynchronous terminal-ownership handoff.
  ///
  /// The suspension remains balanced when `body` throws or observes
  /// cancellation. The body stays on the main actor because terminal mode and
  /// run-loop ownership are main-actor-confined.
  @MainActor
  func withInputSuspended<T: Sendable>(
    _ body: @MainActor @Sendable () async throws -> T
  ) async rethrows -> T
}
