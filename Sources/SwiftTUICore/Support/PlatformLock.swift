// A small compatibility layer so package targets can use the same lock API on
// Apple platforms and on early non-Apple bring-up targets like WASI.
import Synchronization

package final class OSAllocatedUnfairLock<State>: Sendable {
  private let rawLock: Mutex<State>

  package init(
    uncheckedState initialState: sending State
  ) {
    rawLock = Mutex(initialState)
  }

  @discardableResult
  package func withLock<Result>(
    _ body: (inout sending State) throws -> sending Result
  ) rethrows -> sending Result {
    try rawLock.withLock(body)
  }

  @discardableResult
  package func withLockUnchecked<Result>(
    _ body: (inout sending State) throws -> sending Result
  ) rethrows -> sending Result {
    try rawLock.withLock(body)
  }
}
