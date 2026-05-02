import Synchronization

final class LockedBox<Value: Sendable>: Sendable {
  private let storage: Mutex<Value>

  init(_ value: Value) {
    storage = Mutex(value)
  }

  var value: Value {
    get { storage.withLock { $0 } }
    set { storage.withLock { $0 = newValue } }
  }

  @discardableResult
  func withLock<Result>(
    _ body: (inout sending Value) -> sending Result
  ) -> sending Result {
    storage.withLock(body)
  }
}
