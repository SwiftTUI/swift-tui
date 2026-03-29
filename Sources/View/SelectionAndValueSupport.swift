import Core

protocol OptionalSelectionValue {
  static func parallelOptionalSelectionValue(from tag: AnyHashable) -> Self?
}

protocol OptionalSelectionMatchable {
  var parallelWrappedTagValue: AnyHashable? { get }
}

extension Optional: OptionalSelectionValue where Wrapped: Hashable {
  static func parallelOptionalSelectionValue(from tag: AnyHashable) -> Wrapped?? {
    guard let wrapped = tag.base as? Wrapped else {
      return nil
    }
    return .some(wrapped)
  }
}

extension Optional: OptionalSelectionMatchable where Wrapped: Hashable {
  var parallelWrappedTagValue: AnyHashable? {
    switch self {
    case .some(let wrapped):
      return AnyHashable(wrapped)
    case .none:
      return nil
    }
  }
}

func pickerSelectionMatches<SelectionValue: Hashable>(
  _ tag: SelectionTag,
  selection: SelectionValue
) -> Bool {
  if AnyHashable(selection) == tag.value {
    return true
  }

  guard tag.includeOptional,
    let optionalSelection = selection as? any OptionalSelectionMatchable
  else {
    return false
  }

  return optionalSelection.parallelWrappedTagValue == tag.value
}

func pickerSelectionValue<SelectionValue: Hashable>(
  from tag: SelectionTag,
  as _: SelectionValue.Type
) -> SelectionValue? {
  if let exactValue = tag.value.base as? SelectionValue {
    return exactValue
  }

  guard tag.includeOptional,
    let optionalType = SelectionValue.self as? any OptionalSelectionValue.Type
  else {
    return nil
  }

  return optionalType.parallelOptionalSelectionValue(from: tag.value) as? SelectionValue
}

func clampedControlValue(
  _ value: Int,
  to bounds: ClosedRange<Int>?
) -> Int {
  guard let bounds else {
    return value
  }
  return min(max(value, bounds.lowerBound), bounds.upperBound)
}

func steppedControlValue(
  from value: Int,
  delta: Int,
  bounds: ClosedRange<Int>?
) -> Int {
  clampedControlValue(value + delta, to: bounds)
}

func stepperCanAdjust(
  _ value: Int,
  delta: Int,
  bounds: ClosedRange<Int>?
) -> Bool {
  steppedControlValue(from: value, delta: delta, bounds: bounds) != value
}

func pointerSelectionDelta(
  deltaX: Int,
  deltaY: Int
) -> Int? {
  if deltaY != 0 {
    return deltaY
  }
  if deltaX != 0 {
    return deltaX
  }
  return nil
}

func pointerValueDelta(
  deltaX: Int,
  deltaY: Int
) -> Int? {
  if deltaX != 0 {
    return deltaX
  }
  if deltaY != 0 {
    return -deltaY
  }
  return nil
}

func sliderValue(
  at locationX: Int,
  in trackRect: Rect,
  bounds: ClosedRange<Int>,
  step: Int
) -> Int {
  let effectiveStep = max(1, step)
  var candidates: [Int] = [bounds.lowerBound]
  var nextValue = bounds.lowerBound
  while nextValue < bounds.upperBound {
    nextValue = min(bounds.upperBound, nextValue + effectiveStep)
    if nextValue != candidates.last {
      candidates.append(nextValue)
    }
  }

  let usableRect: Rect =
    if trackRect.size.width > 2 {
      .init(
        origin: .init(x: trackRect.origin.x + 1, y: trackRect.origin.y),
        size: .init(width: max(1, trackRect.size.width - 2), height: trackRect.size.height)
      )
    } else {
      trackRect
    }

  let clampedX = min(
    max(locationX, usableRect.origin.x),
    usableRect.origin.x + max(0, usableRect.size.width - 1)
  )

  guard candidates.count > 1, usableRect.size.width > 1 else {
    return candidates[0]
  }

  let normalized =
    Double(clampedX - usableRect.origin.x)
    / Double(max(1, usableRect.size.width - 1))
  let candidateIndex = min(
    max(0, Int((normalized * Double(candidates.count - 1)).rounded())),
    candidates.count - 1
  )
  return candidates[candidateIndex]
}

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
    max(currentIndex + direction, 0),
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

struct PointerRouteView<Content: View>: View, ResolvableView {
  var identity: Identity
  var content: Content

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let wrapperContext = context.replacingIdentity(with: identity)
    let child = content.resolve(
      in: wrapperContext.child(component: "content")
    )
    return [
      ResolvedNode(
        identity: identity,
        kind: .view("PointerRoute"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        semanticMetadata: .init(participatesInPointerHitTesting: true)
      )
    ]
  }
}
