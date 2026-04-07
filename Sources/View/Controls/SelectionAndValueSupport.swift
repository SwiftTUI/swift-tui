package import Core

protocol AdjustableControlValue: Comparable, SignedNumeric, Sendable {
  init(_ value: Int)
  var controlDoubleValue: Double { get }
  static func sanitizedControlStep(_ step: Self) -> Self
  static func steppedControlValue(
    from value: Self,
    delta: Int,
    step: Self,
    bounds: ClosedRange<Self>?
  ) -> Self
  static func controlValueFromTrack(
    _ rawValue: Double,
    bounds: ClosedRange<Self>,
    step: Self
  ) -> Self
  static func formattedControlValue(
    _ value: Self,
    bounds: ClosedRange<Self>?,
    step: Self
  ) -> String
}

extension Int: AdjustableControlValue {
  var controlDoubleValue: Double { Double(self) }

  static func sanitizedControlStep(_ step: Int) -> Int {
    Swift.max(1, abs(step))
  }

  static func steppedControlValue(
    from value: Int,
    delta: Int,
    step: Int,
    bounds: ClosedRange<Int>?
  ) -> Int {
    let scaledDelta = delta * sanitizedControlStep(step)
    return clampedControlValue(value + scaledDelta, to: bounds)
  }

  static func controlValueFromTrack(
    _ rawValue: Double,
    bounds: ClosedRange<Int>,
    step: Int
  ) -> Int {
    let sanitizedStep = sanitizedControlStep(step)
    let lower = Double(bounds.lowerBound)
    let upper = Double(bounds.upperBound)
    let clampedRaw = Swift.min(Swift.max(rawValue, lower), upper)
    let snapped =
      lower
      + ((clampedRaw - lower) / Double(sanitizedStep)).rounded() * Double(sanitizedStep)
    return clampedControlValue(Int(snapped.rounded()), to: bounds)
  }

  static func formattedControlValue(
    _ value: Int,
    bounds _: ClosedRange<Int>?,
    step _: Int
  ) -> String {
    "\(value)"
  }
}

extension Double: AdjustableControlValue {
  var controlDoubleValue: Double { self }

  static func sanitizedControlStep(_ step: Double) -> Double {
    let magnitude = abs(step)
    guard magnitude.isFinite, magnitude > 0 else {
      return 1
    }
    return magnitude
  }

  static func steppedControlValue(
    from value: Double,
    delta: Int,
    step: Double,
    bounds: ClosedRange<Double>?
  ) -> Double {
    let sanitizedStep = sanitizedControlStep(step)
    let stepped = value + Double(delta) * sanitizedStep
    return cleanedControlDouble(
      clampedControlValue(stepped, to: bounds),
      step: sanitizedStep,
      bounds: bounds
    )
  }

  static func controlValueFromTrack(
    _ rawValue: Double,
    bounds: ClosedRange<Double>,
    step: Double
  ) -> Double {
    let sanitizedStep = sanitizedControlStep(step)
    let lower = bounds.lowerBound
    let upper = bounds.upperBound
    let clampedRaw = Swift.min(Swift.max(rawValue, lower), upper)
    let snapped =
      lower
      + ((clampedRaw - lower) / sanitizedStep).rounded() * sanitizedStep
    return cleanedControlDouble(
      clampedControlValue(snapped, to: bounds),
      step: sanitizedStep,
      bounds: bounds
    )
  }

  static func formattedControlValue(
    _ value: Double,
    bounds: ClosedRange<Double>?,
    step: Double
  ) -> String {
    let sanitizedStep = sanitizedControlStep(step)
    let cleaned = cleanedControlDouble(
      clampedControlValue(value, to: bounds),
      step: sanitizedStep,
      bounds: bounds
    )
    return trimmedControlString(cleaned)
  }
}

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

func clampedControlValue<Value: Comparable>(
  _ value: Value,
  to bounds: ClosedRange<Value>?
) -> Value {
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
  steppedControlValue(
    from: value,
    delta: delta,
    step: 1,
    bounds: bounds
  )
}

func steppedControlValue<Value: AdjustableControlValue>(
  from value: Value,
  delta: Int,
  step: Value,
  bounds: ClosedRange<Value>?
) -> Value {
  Value.steppedControlValue(
    from: value,
    delta: delta,
    step: step,
    bounds: bounds
  )
}

func stepperCanAdjust(
  _ value: Int,
  delta: Int,
  bounds: ClosedRange<Int>?
) -> Bool {
  stepperCanAdjust(
    value,
    delta: delta,
    step: 1,
    bounds: bounds
  )
}

func stepperCanAdjust<Value: AdjustableControlValue>(
  _ value: Value,
  delta: Int,
  step: Value,
  bounds: ClosedRange<Value>?
) -> Bool {
  steppedControlValue(
    from: value,
    delta: delta,
    step: step,
    bounds: bounds
  ) != value
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

func sliderValue<Value: AdjustableControlValue>(
  at locationX: Int,
  in trackRect: Rect,
  bounds: ClosedRange<Value>,
  step: Value
) -> Value {
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

  guard usableRect.size.width > 1 else {
    return Value.controlValueFromTrack(
      bounds.lowerBound.controlDoubleValue,
      bounds: bounds,
      step: step
    )
  }

  let normalized =
    Double(clampedX - usableRect.origin.x)
    / Double(max(1, usableRect.size.width - 1))
  let rawValue =
    bounds.lowerBound.controlDoubleValue
    + normalized * (bounds.upperBound.controlDoubleValue - bounds.lowerBound.controlDoubleValue)
  return Value.controlValueFromTrack(
    rawValue,
    bounds: bounds,
    step: step
  )
}

func formattedControlValue<Value: AdjustableControlValue>(
  _ value: Value,
  bounds: ClosedRange<Value>?,
  step: Value
) -> String {
  Value.formattedControlValue(
    value,
    bounds: bounds,
    step: step
  )
}

func sliderTrack<Value: AdjustableControlValue>(
  value: Value,
  bounds: ClosedRange<Value>
) -> String {
  let segmentCount = 8
  let lower = bounds.lowerBound.controlDoubleValue
  let upper = bounds.upperBound.controlDoubleValue
  let span = max(leastMeaningfulControlDelta, upper - lower)
  let normalized = (value.controlDoubleValue - lower) / span
  let position = min(
    max(0, Int((normalized * Double(segmentCount - 1)).rounded())),
    segmentCount - 1
  )

  var characters = Array(repeating: Character("─"), count: segmentCount)
  for index in 0..<position {
    characters[index] = Character("━")
  }
  characters[position] = Character("●")
  return String(characters)
}

private let leastMeaningfulControlDelta = 1e-12
private let maxControlFractionDigits = 6

private func cleanedControlDouble(
  _ value: Double,
  step: Double,
  bounds: ClosedRange<Double>?
) -> Double {
  guard value.isFinite else {
    return value
  }

  let minimumPrecision = controlDisplayPrecision(
    step: step,
    bounds: bounds
  )
  let tolerance = max(
    leastMeaningfulControlDelta,
    abs(step) * 1e-6
  )

  for precision in minimumPrecision...maxControlFractionDigits {
    let rounded = roundedControlDouble(
      value,
      precision: precision
    )
    if abs(rounded - value) <= tolerance {
      return rounded
    }
  }

  return value
}

private func controlDisplayPrecision(
  step: Double,
  bounds: ClosedRange<Double>?
) -> Int {
  let componentPrecisions =
    [trimmedDecimalPlaces(for: step)]
    + [bounds?.lowerBound, bounds?.upperBound]
      .compactMap { $0 }
      .map(trimmedDecimalPlaces(for:))
  return min(
    max(0, componentPrecisions.max() ?? 0),
    maxControlFractionDigits
  )
}

private func roundedControlDouble(
  _ value: Double,
  precision: Int
) -> Double {
  guard precision > 0 else {
    return value.rounded()
  }

  var scale = 1.0
  for _ in 0..<precision {
    scale *= 10
  }
  return (value * scale).rounded() / scale
}

private func trimmedDecimalPlaces(
  for value: Double
) -> Int {
  let text = String(value)
  if let exponentIndex = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
    let significand = String(text[..<exponentIndex])
    let exponentText = String(text[text.index(after: exponentIndex)...])
    let exponent = Int(exponentText) ?? 0
    return max(0, decimalPlaces(in: significand) - exponent)
  }
  return decimalPlaces(in: text)
}

private func decimalPlaces(
  in text: String
) -> Int {
  guard let decimalIndex = text.firstIndex(of: ".") else {
    return 0
  }

  var fraction = String(text[text.index(after: decimalIndex)...])
  while fraction.last == "0" {
    fraction.removeLast()
  }
  return fraction.count
}

private func trimmedControlString(
  _ value: Double
) -> String {
  var text = String(value)
  if text.contains("e") || text.contains("E") {
    text = fixedControlString(
      value,
      precision: maxControlFractionDigits
    )
  }

  if let decimalIndex = text.firstIndex(of: ".") {
    var fraction = text[text.index(after: decimalIndex)...]
    while fraction.last == "0" {
      fraction.removeLast()
    }

    text = fraction.isEmpty
      ? String(text[..<decimalIndex])
      : "\(text[..<decimalIndex]).\(fraction)"
  }

  return text == "-0" ? "0" : text
}

private func fixedControlString(
  _ value: Double,
  precision: Int
) -> String {
  let rounded = roundedControlDouble(
    value,
    precision: precision
  )
  let isNegative = rounded < 0
  var scale = 1.0
  for _ in 0..<precision {
    scale *= 10
  }

  let scaledMagnitude = Int64(abs(rounded * scale).rounded())
  let integerScale = Int64(scale.rounded())
  let whole = scaledMagnitude / integerScale
  let fraction = scaledMagnitude % integerScale

  guard precision > 0 else {
    return "\(isNegative ? "-" : "")\(whole)"
  }

  let fractionText = String(fraction)
  let paddedFraction =
    fractionText.count < precision
    ? String(repeating: "0", count: precision - fractionText.count) + fractionText
    : fractionText
  return "\(isNegative ? "-" : "")\(whole).\(paddedFraction)"
}

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

package let controlFocusRailGlyph = "▌"

@MainActor
@ViewBuilder
package func controlFocusRail(
  isVisible: Bool,
  style: AnyShapeStyle,
  inactiveStyle: AnyShapeStyle = AnyShapeStyle(.background),
  reservesSpaceWhenHidden: Bool = false
) -> some View {
  if isVisible {
    Text(controlFocusRailGlyph)
      .foregroundStyle(style)
  } else if reservesSpaceWhenHidden {
    Text(String(repeating: " ", count: controlFocusRailGlyph.count))
      .foregroundStyle(inactiveStyle)
  }
}

@MainActor
@ViewBuilder
package func highlightedControlRow<Row: View>(
  _ row: Row,
  isHighlighted: Bool,
  backgroundStyle: AnyShapeStyle
) -> some View {
  if isHighlighted {
    row.background {
      Rectangle().fill(backgroundStyle)
    }
  } else {
    row
  }
}

@MainActor
package func controlFocusRow<Content: View>(
  showsRail: Bool,
  railStyle: AnyShapeStyle,
  isHighlighted: Bool,
  backgroundStyle: AnyShapeStyle,
  inactiveRailStyle: AnyShapeStyle = AnyShapeStyle(.background),
  reservesRailSpaceWhenHidden: Bool = false,
  spacing: Int = 1,
  @ViewBuilder content: () -> Content
) -> some View {
  highlightedControlRow(
    HStack(alignment: .center, spacing: spacing) {
      if showsRail || reservesRailSpaceWhenHidden {
        controlFocusRail(
          isVisible: showsRail,
          style: railStyle,
          inactiveStyle: inactiveRailStyle,
          reservesSpaceWhenHidden: reservesRailSpaceWhenHidden
        )
      }
      content()
    },
    isHighlighted: isHighlighted,
    backgroundStyle: backgroundStyle
  )
}

@MainActor
func registerMultilineTextEntryBinding(
  _ binding: Binding<String>,
  scrollPosition: Binding<ScrollPosition>,
  in context: ResolveContext
) {
  guard context.environmentValues.isEnabled else {
    return
  }

  let dynamicPropertyScope = currentAuthoringContext()
  context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
    withAuthoringContext(dynamicPropertyScope) {
      mutateTextEntryBinding(
        binding,
        event: event,
        allowsNewlines: true,
        scrollPosition: scrollPosition
      )
    }
  }
}

@MainActor
package func mutateTextEntryBinding(
  _ binding: Binding<String>,
  event: KeyEvent,
  allowsNewlines: Bool,
  scrollPosition: Binding<ScrollPosition>?
) -> Bool {
  switch event {
  case .character(let character):
    binding.wrappedValue.append(character)
    return true
  case .space:
    binding.wrappedValue.append(" ")
    return true
  case .return where allowsNewlines:
    binding.wrappedValue.append("\n")
    return true
  case .backspace:
    guard !binding.wrappedValue.isEmpty else {
      return false
    }
    binding.wrappedValue.removeLast()
    return true
  case .arrowUp:
    guard let scrollPosition else {
      return true
    }
    var next = scrollPosition.wrappedValue
    next.scrollBy(y: -1)
    scrollPosition.wrappedValue = next
    return true
  case .arrowDown:
    guard let scrollPosition else {
      return true
    }
    var next = scrollPosition.wrappedValue
    next.scrollBy(y: 1)
    scrollPosition.wrappedValue = next
    return true
  case .arrowLeft, .arrowRight:
    return true
  default:
    return false
  }
}

@MainActor
package func textEditorBody(
  displayText: String,
  chrome: ControlChrome,
  scrollPosition: Binding<ScrollPosition>,
  focusActive: Bool = false
) -> some View {
  ScrollView(.vertical, showsIndicators: true, position: scrollPosition) {
    VStack(alignment: .leading, spacing: 0) {
      Text(displayText)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(chrome.foregroundStyle)
        .drawMetadata(.init(opacity: chrome.opacity))
    }
    .padding(.init(horizontal: 1, vertical: 1))
  }
  .background {
    RoundedRectangle(cornerRadius: 1).chromeFill(chrome.backgroundStyle)
  }
  .overlay {
    RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
      chrome.borderStyle,
      style: focusActive ? .thick : .init(),
      backgroundStyle: chrome.borderBackgroundStyle
    )
  }
  .layoutMetadata(.init(minimumHeight: 3))
}

struct PointerRouteView<Content: View>: View, ResolvableView {
  var identity: Identity
  var content: Content

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let wrapperContext = context.replacingIdentity(with: identity)
    let child = content.resolve(
      in: wrapperContext.child(component: .named("content"))
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
