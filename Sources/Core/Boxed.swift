import Synchronization

/// Copy-on-write heap-allocated box for large value types.
///
/// Use this to store value types that exceed ~200 bytes inline inside other
/// value types (structs, enums, tuples). The box reduces inline size to a
/// single pointer (8 bytes) while preserving value semantics through COW.
package final class _BoxStorage<Value: Equatable & Sendable>: Sendable {
  private let state: Mutex<Value>

  package init(_ value: sending Value) {
    state = Mutex(value)
  }

  package func snapshot() -> Value {
    state.withLock { $0 }
  }

  package func replace(with value: sending Value) {
    state.withLock { $0 = value }
  }
}

package struct Boxed<Value: Equatable & Sendable>: Equatable, Sendable {
  private var _storage: _BoxStorage<Value>

  package init(_ value: Value) {
    _storage = _BoxStorage(value)
  }

  package var value: Value {
    _read {
      let value = _storage.snapshot()
      yield value
    }
    _modify {
      if !isKnownUniquelyReferenced(&_storage) {
        _storage = _BoxStorage(_storage.snapshot())
      }
      var value = _storage.snapshot()
      defer { _storage.replace(with: value) }
      yield &value
    }
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs._storage === rhs._storage || lhs._storage.snapshot() == rhs._storage.snapshot()
  }
}
