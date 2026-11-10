/// Copy-on-write heap-allocated box for large value types.
///
/// Use this to store value types that exceed ~200 bytes inline inside other
/// value types (structs, enums, tuples). The box reduces inline size to a
/// single pointer (8 bytes) while preserving value semantics through COW.
package final class _BoxStorage<Value: Equatable & Sendable>: Sendable {
  /// Immutable, so a reader on any thread borrows the value in place: no
  /// lock, and no copy unless the reader keeps the value.
  package let value: Value

  package init(_ value: sending Value) {
    self.value = value
  }
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
      // The storage is immutable, so a mutation always moves to a new box.
      // Boxed values are read many times per frame and written rarely.
      var value = _storage.value
      defer { _storage = _BoxStorage(value) }
      yield &value
    }
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs._storage === rhs._storage || lhs._storage.value == rhs._storage.value
  }
}
