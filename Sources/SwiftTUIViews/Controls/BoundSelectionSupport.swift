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
  delta: Int
) -> Bool {
  guard let direction = delta == 0 ? nil : delta.signum(),
    !orderedTags.isEmpty
  else {
    return false
  }

  let currentIndex =
    orderedTags.firstIndex { tag in
      pickerSelectionMatches(tag, selection: binding.wrappedValue)
    }
    ?? (direction > 0 ? -1 : orderedTags.count)
  let nextIndex = min(
    max(currentIndex + delta, 0),
    orderedTags.count - 1
  )
  guard nextIndex != currentIndex else {
    return false
  }

  return setBoundSelection(
    binding,
    to: orderedTags[nextIndex]
  )
}
