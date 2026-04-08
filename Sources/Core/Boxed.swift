/// Copy-on-write heap-allocated box for large value types.
///
/// Use this to store value types that exceed ~200 bytes inline inside other
/// value types (structs, enums, tuples).  The box reduces inline size to a
/// single pointer (8 bytes) while preserving value semantics through COW.
package final class _BoxStorage<Value: Sendable>: @unchecked Sendable {
  package var value: Value
  package init(_ value: Value) { self.value = value }
}

package struct Boxed<Value: Equatable & Sendable>: Equatable, Sendable {
  private var _storage: _BoxStorage<Value>

  package init(_ value: Value) {
    _storage = _BoxStorage(value)
  }

  package var value: Value {
    _read {
      yield _storage.value
    }
    _modify {
      if !isKnownUniquelyReferenced(&_storage) {
        _storage = _BoxStorage(_storage.value)
      }
      yield &_storage.value
    }
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs._storage === rhs._storage || lhs._storage.value == rhs._storage.value
  }
}
