import SwiftTUICore

// Control value math: the `AdjustableControlValue` abstraction and its helpers.
//
// `AdjustableControlValue` is the numeric abstraction behind `Stepper`,
// `Slider`, and other value controls — `Int` and `Double` conform. The free
// functions clamp, step, and snap values, derive a slider value from a pointer
// location, and render a compact slider track. The `private` block at the end
// is the `Double`-only display-string machinery: it rounds a value to the
// fewest decimal places that still round-trips within tolerance, then trims
// trailing zeros.
//
// Split out of `SelectionAndValueSupport.swift`. The `private` formatting
// cluster travels here with its only callers (the `Double` conformance and the
// slider helpers) — so it stays `private` with zero access widening.

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
  at locationX: Double,
  in trackRect: CellRect,
  bounds: ClosedRange<Value>,
  step: Value
) -> Value {
  let usableRect: CellRect =
    if trackRect.size.width > 2 {
      .init(
        origin: .init(x: trackRect.origin.x + 1, y: trackRect.origin.y),
        size: .init(width: max(1, trackRect.size.width - 2), height: trackRect.size.height)
      )
    } else {
      trackRect
    }

  guard usableRect.size.width > 1 else {
    return Value.controlValueFromTrack(
      bounds.lowerBound.controlDoubleValue,
      bounds: bounds,
      step: step
    )
  }

  let firstCenter = Double(usableRect.origin.x) + 0.5
  let lastCenter =
    Double(usableRect.origin.x + max(0, usableRect.size.width - 1)) + 0.5
  let finiteLocationX = locationX.isFinite ? locationX : firstCenter
  let clampedX = min(max(finiteLocationX, firstCenter), lastCenter)
  let normalized =
    (clampedX - firstCenter)
    / max(leastMeaningfulControlDelta, lastCenter - firstCenter)
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

    text =
      fraction.isEmpty
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
