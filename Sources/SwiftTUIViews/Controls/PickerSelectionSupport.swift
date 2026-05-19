import SwiftTUICore

// Picker selection-tag matching.
//
// A `Picker` tags each option with a `SelectionTag` and must decide which tag
// matches the bound selection. The tricky case is an optional selection
// (`SelectionValue == T?`): a tag carrying a plain `T` should match a bound
// `.some(T)`. These protocols and helpers handle that bridging.
//
// Split out of `SelectionAndValueSupport.swift` so that file holds only the
// adjustable numeric-control support.

protocol OptionalSelectionValue {
  static func optionalSelectionValue(from tagValue: Any) -> Self?
}

protocol OptionalSelectionMatchable {
  var wrappedTagValue: Any? { get }
}

extension Optional: OptionalSelectionValue where Wrapped: Hashable {
  static func optionalSelectionValue(from tagValue: Any) -> Wrapped?? {
    guard let wrapped = tagValue as? Wrapped else {
      return nil
    }
    return .some(wrapped)
  }
}

extension Optional: OptionalSelectionMatchable where Wrapped: Hashable {
  var wrappedTagValue: Any? {
    switch self {
    case .some(let wrapped):
      return wrapped
    case .none:
      return nil
    }
  }
}

func pickerSelectionMatches<SelectionValue: Hashable>(
  _ tag: SelectionTag,
  selection: SelectionValue
) -> Bool {
  if let exactValue = tag.value(as: SelectionValue.self),
    exactValue == selection
  {
    return true
  }

  guard tag.includeOptional,
    let optionalSelection = selection as? any OptionalSelectionMatchable
  else {
    return false
  }

  guard
    let wrappedTagValue = optionalSelection.wrappedTagValue as? any Hashable,
    let tagValue = tag.baseValue as? any Hashable
  else {
    return false
  }

  return AnyHashable(wrappedTagValue) == AnyHashable(tagValue)
}

func pickerSelectionValue<SelectionValue: Hashable>(
  from tag: SelectionTag,
  as _: SelectionValue.Type
) -> SelectionValue? {
  if let exactValue = tag.value(as: SelectionValue.self) {
    return exactValue
  }

  guard tag.includeOptional,
    let optionalType = SelectionValue.self as? any OptionalSelectionValue.Type
  else {
    return nil
  }

  return optionalType.optionalSelectionValue(from: tag.baseValue) as? SelectionValue
}
