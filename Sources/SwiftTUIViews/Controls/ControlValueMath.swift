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
  static func accessibilityValue(_ value: Double) -> Self?
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
  static func controlFraction(_ value: Self, bounds: ClosedRange<Self>) -> Double
  static func controlValue(at fraction: Double, bounds: ClosedRange<Self>, step: Self) -> Self
  static func formattedControlValue(
    _ value: Self,
    bounds: ClosedRange<Self>?,
    step: Self
  ) -> String
}

extension Int: AdjustableControlValue {
  var controlDoubleValue: Double { Double(self) }
  static func accessibilityValue(_ value: Double) -> Int? { Int(exactly: value) }

  static func sanitizedControlStep(_ step: Int) -> Int {
    // `Int.min` has no `Int` magnitude; it clamps to the largest step.
    Swift.max(1, Int(clamping: step.magnitude))
  }

  static func steppedControlValue(
    from value: Int,
    delta: Int,
    step: Int,
    bounds: ClosedRange<Int>?
  ) -> Int {
    // Saturate at `Int`'s edges instead of trapping. The travel and the room
    // left in its direction are both exact as `UInt`, and a bounded result
    // clamps from the edge exactly as it would from the unrepresentable value.
    let (distance, overflow) = delta.magnitude.multipliedReportingOverflow(
      by: sanitizedControlStep(step).magnitude
    )
    let stepped: Int
    if delta < 0 {
      let room = UInt(bitPattern: value &- Int.min)
      stepped = overflow || distance > room ? Int.min : value &- Int(bitPattern: distance)
    } else {
      let room = UInt(bitPattern: Int.max &- value)
      stepped = overflow || distance > room ? Int.max : value &+ Int(bitPattern: distance)
    }
    return clampedControlValue(stepped, to: bounds)
  }

  static func controlValueFromTrack(
    _ rawValue: Double,
    bounds: ClosedRange<Int>,
    step: Int
  ) -> Int {
    guard !rawValue.isNaN, rawValue > Double(bounds.lowerBound) else { return bounds.lowerBound }
    guard rawValue < Double(bounds.upperBound) else { return bounds.upperBound }
    return snappedTrackValue(Int128(rawValue.rounded()), bounds: bounds, step: step)
  }

  static func controlFraction(_ value: Int, bounds: ClosedRange<Int>) -> Double {
    guard bounds.upperBound > bounds.lowerBound else { return 0 }
    let bounded = clampedControlValue(value, to: bounds)
    // Subtract exactly before converting: adjacent values above 2^53 remain distinct.
    return Double(Int128(bounded) - Int128(bounds.lowerBound))
      / Double(Int128(bounds.upperBound) - Int128(bounds.lowerBound))
  }

  static func controlValue(at fraction: Double, bounds: ClosedRange<Int>, step: Int) -> Int {
    guard fraction > 0 else { return bounds.lowerBound }
    guard fraction < 1 else { return bounds.upperBound }
    let distance = Int128(bounds.upperBound) - Int128(bounds.lowerBound)
    let offset = Int128((Double(distance) * fraction).rounded())
    return snappedTrackValue(Int128(bounds.lowerBound) + offset, bounds: bounds, step: step)
  }

  private static func snappedTrackValue(_ value: Int128, bounds: ClosedRange<Int>, step: Int) -> Int
  {
    let lower = Int128(bounds.lowerBound)
    let quantum = Int128(sanitizedControlStep(step))
    let distance = value - lower
    let count = (distance + quantum / 2) / quantum
    let snapped = lower + count * quantum
    return Int(Swift.min(Swift.max(snapped, lower), Int128(bounds.upperBound)))
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
  static func accessibilityValue(_ value: Double) -> Double? { value.isFinite ? value : nil }

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
    let lower = bounds.lowerBound
    let upper = bounds.upperBound
    guard !rawValue.isNaN, rawValue > lower else { return lower }
    guard rawValue < upper else { return upper }
    let quantum = sanitizedControlStep(step)
    let count = ((rawValue - lower) / quantum).rounded()
    // If the grid is finer than Double can represent, the sample already
    // has all available precision. Never manufacture infinity from a finite sample.
    let candidate = lower + count * quantum
    let snapped = candidate.isFinite ? candidate : rawValue
    return clampedControlValue(
      cleanedControlDouble(snapped, step: quantum, bounds: bounds), to: bounds)
  }

  static func controlFraction(_ value: Double, bounds: ClosedRange<Double>) -> Double {
    let lower = bounds.lowerBound
    let upper = bounds.upperBound
    guard upper > lower, !value.isNaN, value > lower else { return 0 }
    guard value < upper else { return 1 }
    let span = upper - lower
    // Halving all operands avoids overflow for opposite finite extremes.
    let fraction =
      span.isFinite
      ? (value - lower) / span
      : (value / 2 - lower / 2) / (upper / 2 - lower / 2)
    return fraction.isFinite ? Swift.min(Swift.max(fraction, 0), 1) : 0
  }

  static func controlValue(at fraction: Double, bounds: ClosedRange<Double>, step: Double) -> Double
  {
    guard fraction > 0 else { return bounds.lowerBound }
    guard fraction < 1 else { return bounds.upperBound }
    let raw = (1 - fraction) * bounds.lowerBound + fraction * bounds.upperBound
    return controlValueFromTrack(raw, bounds: bounds, step: step)
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
  guard value.controlDoubleValue.isFinite else { return false }
  let next = steppedControlValue(from: value, delta: delta, step: step, bounds: bounds)
  return next.controlDoubleValue.isFinite && next != value
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
    // `Int.min` has no negation; the wheel moves as far as it can.
    return deltaY == .min ? .max : -deltaY
  }
  return nil
}

func sliderValue<Value: AdjustableControlValue>(
  at locationX: Double,
  in trackRect: CellRect,
  bounds: ClosedRange<Value>,
  step: Value,
  currentValue: Value? = nil
) -> Value {
  // The style's protected track slot is the complete interaction surface.
  // Decorative caps belong outside that slot; the primitive cannot infer them.
  let usableRect = trackRect
  guard usableRect.size.width > 1 else {
    return bounds.lowerBound
  }

  let firstCenter = Double(usableRect.origin.x) + 0.5
  let lastCenter =
    Double(usableRect.origin.x + max(0, usableRect.size.width - 1)) + 0.5
  let finiteLocationX = locationX.isFinite ? locationX : firstCenter
  let clampedX = min(max(finiteLocationX, firstCenter), lastCenter)
  if let currentValue, currentValue.controlDoubleValue.isFinite,
    bounds.contains(currentValue),
    Int((clampedX - firstCenter).rounded())
      == sliderMarkerPosition(
        fraction: Value.controlFraction(currentValue, bounds: bounds),
        width: usableRect.size.width)
  {
    // Several values can share a terminal cell. Pressing the current marker
    // preserves the model instead of snapping it to a different value in that cell.
    return currentValue
  }
  let normalized =
    (clampedX - firstCenter)
    / (lastCenter - firstCenter)
  return Value.controlValue(at: normalized, bounds: bounds, step: step)
}

/// Derives the effective steps for a continuous (`step: nil`) slider.
///
/// The track step is the fine quantum pointer drags snap to — the largest
/// power of ten no greater than 1/100 of the span, so dragged values stay
/// near-continuous yet display with short, stable decimals. The adjustment
/// step (arrow keys, wheel) is ten track quanta — roughly a tenth of the
/// span, matching the keyboard feel of a continuous SwiftUI slider.
package func continuousSliderSteps(
  for bounds: ClosedRange<Double>
) -> (track: Double, adjustment: Double) {
  let span = bounds.upperBound - bounds.lowerBound
  let target = span / 100
  // A subnormal target underflows the quantum to zero in the first loop,
  // and `0 * 10 <= target` then never exits the second. Treat such a span
  // as degenerate, like a non-positive one.
  guard span.isFinite, span > 0, target.isNormal else {
    return (track: 1, adjustment: 1)
  }

  var quantum = 1.0
  while quantum > target {
    quantum /= 10
  }
  while quantum * 10 <= target {
    quantum *= 10
  }
  return (track: quantum, adjustment: quantum * 10)
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

func sliderFraction<Value: AdjustableControlValue>(
  value: Value,
  bounds: ClosedRange<Value>
) -> Double {
  Value.controlFraction(value, bounds: bounds)
}

private func cleanedControlDouble(
  _ value: Double,
  step: Double,
  bounds: ClosedRange<Double>?
) -> Double {
  guard value.isFinite, value != 0 else { return value }
  let minimumPrecision = controlDisplayPrecision(step: step, bounds: bounds)
  if trimmedDecimalPlaces(for: value) <= minimumPrecision { return value }
  // Cleanup removes floating-point operation noise, not meaningful small values.
  let tolerance = min(abs(step) * 1e-6, max(abs(value) * 1e-14, value.ulp * 4))
  for precision in minimumPrecision...max(minimumPrecision, 17) {
    let rounded = roundedControlDouble(value, precision: precision)
    if rounded.isFinite, abs(rounded - value) <= tolerance { return rounded }
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
  return min(324, max(0, componentPrecisions.max() ?? 0))
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
  guard scale.isFinite, (value * scale).isFinite else { return value }
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

/// Expands Double's shortest round-trip decimal representation using string
/// arithmetic. No scaled Int conversion, fixed precision cap, or lost tiny values.
func trimmedControlString(_ value: Double) -> String {
  guard value.isFinite else { return "0" }
  if value == 0 { return "0" }
  var text = String(value)
  if let exponentIndex = text.firstIndex(where: { $0 == "e" || $0 == "E" }),
    let exponent = Int(text[text.index(after: exponentIndex)...])
  {
    let negative = text.first == "-"
    let mantissa = text[
      (negative ? text.index(after: text.startIndex) : text.startIndex)..<exponentIndex]
    let parts = mantissa.split(separator: ".")
    let digits = parts.joined()
    let decimalPosition = parts[0].count + exponent
    if decimalPosition <= 0 {
      text = "0." + String(repeating: "0", count: -decimalPosition) + digits
    } else if decimalPosition >= digits.count {
      text = digits + String(repeating: "0", count: decimalPosition - digits.count)
    } else {
      let split = digits.index(digits.startIndex, offsetBy: decimalPosition)
      text = String(digits[..<split]) + "." + digits[split...]
    }
    if negative { text = "-" + text }
  }
  if text.contains(".") {
    while text.last == "0" { text.removeLast() }
    if text.last == "." { text.removeLast() }
  }
  return text
}

func sliderMarkerPosition(fraction: Double, width: Int) -> Int {
  let last = max(0, width - 1)
  let normalized = fraction.isFinite ? min(max(fraction, 0), 1) : 0
  if normalized == 1 { return last }
  return min(last, max(0, Int((normalized * Double(last)).rounded())))
}
