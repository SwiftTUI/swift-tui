import Synchronization

/// Records invalidations requested by synchronous frame callbacks, separately
/// from an independent producer that happens to run during the same frame.
/// The scope closes before returning so inherited tasks cannot extend it later.
package final class SynchronousInvalidationScope {
  @TaskLocal private static var current: SynchronousInvalidationScope?

  private struct State {
    var isOpen = true
    var didRequestInvalidation = false
  }

  private let scheduler: ObjectIdentifier
  private let state = Mutex(State())

  private init(scheduler: FrameScheduler) {
    self.scheduler = ObjectIdentifier(scheduler)
  }

  @MainActor
  package static func track<Value>(
    scheduler: FrameScheduler,
    _ operation: () throws -> Value
  ) rethrows -> (value: Value, didRequestInvalidation: Bool) {
    let scope = SynchronousInvalidationScope(scheduler: scheduler)
    defer { scope.close() }
    let value = try $current.withValue(scope, operation: operation)
    return (value, scope.close())
  }

  package static func record(scheduler: FrameScheduler) {
    guard let scope = current, scope.scheduler == ObjectIdentifier(scheduler) else { return }
    scope.state.withLock { state in
      if state.isOpen {
        state.didRequestInvalidation = true
      }
    }
  }

  @discardableResult
  private func close() -> Bool {
    state.withLock { state in
      state.isOpen = false
      return state.didRequestInvalidation
    }
  }
}

extension SynchronousInvalidationScope: Sendable {}
