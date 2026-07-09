private protocol SelectionTagValueBox: Sendable {
  var baseValue: Any { get }

  func isEqual(
    to other: any SelectionTagValueBox
  ) -> Bool
}

private struct TypedSelectionTagValueBox<Value: Hashable & Sendable>: SelectionTagValueBox {
  let value: Value

  var baseValue: Any {
    value
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

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.includeOptional == rhs.includeOptional
      && lhs.valueBox.isEqual(to: rhs.valueBox)
  }
}
