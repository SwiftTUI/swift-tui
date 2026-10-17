import SwiftTUICore

// Bound-selection helpers.
//
// These write a selection-tag choice back through a `Binding`:
// `setBoundSelection` resolves a tag to the binding's value type and assigns
// it; `stepBoundSelection` advances the binding by a signed delta through an
// ordered list of tags. Both are used by `Picker`, `List`, `Table`, and
// `TabView` keyboard/pointer handling.
//
// Split out of `SelectionAndValueSupport.swift`. They build on the
// selection-tag matching helpers in `PickerSelectionSupport.swift`.

@MainActor
func setBoundSelection<SelectionValue: Hashable>(
  _ binding: Binding<SelectionValue>,
  to tag: SelectionTag
) -> Bool {
  guard let nextSelection = pickerSelectionValue(from: tag, as: SelectionValue.self) else {
    return false
  }
  if binding.wrappedValue != nextSelection {
    binding.wrappedValue = nextSelection
  }
  return true
}

@MainActor
func stepBoundSelection<SelectionValue: Hashable>(
  _ binding: Binding<SelectionValue>,
  orderedTags: [SelectionTag],
  delta: Int,
  isEnabled: (Int) -> Bool = { _ in true }
) -> Bool {
  guard delta != 0, !orderedTags.isEmpty else { return false }
  let current = binding.wrappedValue
  let direction = delta.signum()
  let currentIndex =
    orderedTags.firstIndex {
      pickerSelectionMatches($0, selection: current)
    } ?? (direction > 0 ? -1 : orderedTags.count)
  var candidate = currentIndex + direction
  var remaining = delta.magnitude
  var visited: Set<SelectionValue> = [current]
  var destination: SelectionValue?
  while orderedTags.indices.contains(candidate) {
    if isEnabled(candidate),
      let value = pickerSelectionValue(from: orderedTags[candidate], as: SelectionValue.self),
      visited.insert(value).inserted
    {
      destination = value
      remaining -= 1
      if remaining == 0 { break }
    }
    candidate += direction
  }
  guard let destination else { return false }
  binding.wrappedValue = destination
  return true
}
