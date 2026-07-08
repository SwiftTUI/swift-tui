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
