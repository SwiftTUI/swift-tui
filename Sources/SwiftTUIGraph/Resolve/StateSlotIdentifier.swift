/// The discovered-property path a dynamic-property update pass reached a
/// wrapper's container through: stored-field indices from the enclosing view
/// (or enclosing dynamic property) down to the wrapper's container, in
/// `Mirror` child order.
///
/// Empty for wrappers stored directly on a view (or reached outside the
/// update pass) — the legacy ordinal-only identity. Non-empty exactly when a
/// wrapper was bound through a discovered dynamic property, which is what
/// gives two instances of one composed wrapper distinct slot identities even
/// though their source-location ordinals coincide.
package struct StateSlotPath: Hashable, Sendable {
  package var fieldIndices: [Int]

  package static let root = StateSlotPath(fieldIndices: [])

  package init(fieldIndices: [Int]) {
    self.fieldIndices = fieldIndices
  }

  package var isEmpty: Bool {
    fieldIndices.isEmpty
  }

  package func appending(_ fieldIndex: Int) -> StateSlotPath {
    StateSlotPath(fieldIndices: fieldIndices + [fieldIndex])
  }
}

extension StateSlotPath: CustomStringConvertible {
  package var description: String {
    fieldIndices.map(String.init).joined(separator: ".")
  }
}

/// A state slot's identity within its owning node: the source-location
/// ordinal fused with the discovered-property path that reached it. An empty
/// path is exactly the pre-path key — top-level wrappers keep their identity
/// and storage unchanged.
package struct StateSlotIdentifier: Hashable, Sendable {
  package var path: StateSlotPath
  package var ordinal: Int

  package init(ordinal: Int, path: StateSlotPath = .root) {
    self.ordinal = ordinal
    self.path = path
  }

  /// The authored source position encoded in ``ordinal``
  /// (`(line << 16) | column`), when this is an authored ordinal rather
  /// than a synthetic negative-base one. Diagnostics only.
  package var authoredSourcePosition: (line: Int, column: Int)? {
    guard ordinal >= 0 else {
      return nil
    }
    return (line: ordinal >> 16, column: ordinal & 0xFFFF)
  }
}

extension StateSlotIdentifier: CustomStringConvertible {
  package var description: String {
    let position: String
    if let source = authoredSourcePosition {
      position = "line \(source.line), column \(source.column)"
    } else {
      position = "synthetic \(ordinal)"
    }
    guard !path.isEmpty else {
      return "[\(ordinal) (\(position))]"
    }
    return "[path \(path) → \(ordinal) (\(position))]"
  }
}
