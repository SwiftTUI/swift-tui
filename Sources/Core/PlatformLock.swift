// A small compatibility layer so package targets can use the same lock API on
// Apple platforms and on early non-Apple bring-up targets like WASI.
#if canImport(os)
  import os

  package final class OSAllocatedUnfairLock<State>: Sendable {
    nonisolated(unsafe) private let rawLock: os.OSAllocatedUnfairLock<State>

    package init(
      uncheckedState initialState: State
    ) {
      rawLock = os.OSAllocatedUnfairLock(uncheckedState: initialState)
    }

    @discardableResult
    package func withLock<Result>(
      _ body: (inout State) throws -> Result
    ) rethrows -> Result {
      try rawLock.withLockUnchecked(body)
    }

    @discardableResult
    package func withLockUnchecked<Result>(
      _ body: (inout State) throws -> Result
    ) rethrows -> Result {
      try rawLock.withLockUnchecked(body)
    }
  }
#else
  // WASI support is currently focused on making the pure framework layers build.
  // The runtime remains out of scope, and those layers execute single-threaded in
  // current bring-up flows, so a no-op lock is sufficient for now.
  package final class OSAllocatedUnfairLock<State>: Sendable {
    nonisolated(unsafe) private var state: State

    package init(
      uncheckedState initialState: State
    ) {
      state = initialState
    }

    @discardableResult
    package func withLock<Result>(
      _ body: (inout State) throws -> Result
    ) rethrows -> Result {
      try body(&state)
    }

    @discardableResult
    package func withLockUnchecked<Result>(
      _ body: (inout State) throws -> Result
    ) rethrows -> Result {
      try body(&state)
    }
  }
#endif
