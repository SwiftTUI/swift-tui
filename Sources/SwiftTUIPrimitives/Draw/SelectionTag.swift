private protocol SelectionTagValueBox: Sendable {
  var baseValue: Any { get }
  var identityValue: AnyID { get }
  var identityComponent: String { get }

  func isEqual(
    to other: any SelectionTagValueBox
  ) -> Bool
}

private struct TypedSelectionTagValueBox<Value: Hashable & Sendable>: SelectionTagValueBox {
  let value: Value

  var baseValue: Any {
    value
  }

  var identityValue: AnyID {
    AnyID(value)
  }

  var identityComponent: String {
    "\(String(reflecting: Value.self)):\(String(reflecting: value))"
  }

  func isEqual(
    to other: any SelectionTagValueBox
  ) -> Bool {
    guard let otherValue = other.baseValue as? Value else {
      return false
    }
    return otherValue == value
  }
}

/// A type-erased selection identity used by lists, tables, and pickers.
public struct SelectionTag: Equatable, Sendable {
  private let valueBox: any SelectionTagValueBox
  public var includeOptional: Bool

  public init<Value: Hashable & Sendable>(
    value: Value,
    includeOptional: Bool = true
  ) {
    valueBox = TypedSelectionTagValueBox(value: value)
    self.includeOptional = includeOptional
  }

  package func value<Value>(
    as _: Value.Type = Value.self
  ) -> Value? {
    valueBox.baseValue as? Value
  }

  package var baseValue: Any {
    valueBox.baseValue
  }

  /// Type-sensitive selection identity used by containers that preserve a
  /// declared child's lifetime independently from its current position.
  package var identityValue: AnyID {
    valueBox.identityValue
  }

  /// Human-readable component for the corresponding structural identity.
  /// Runtime lifetime equality still uses ``identityValue``; this text only
  /// keeps diagnostics and resolved identity paths comprehensible.
  package var identityComponent: String {
    valueBox.identityComponent
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.includeOptional == rhs.includeOptional
      && lhs.valueBox.isEqual(to: rhs.valueBox)
  }
}
