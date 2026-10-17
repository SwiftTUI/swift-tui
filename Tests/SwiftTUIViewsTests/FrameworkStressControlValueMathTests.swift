import SwiftTUICore
import Testing

@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI control value math stress behavior", .serialized)
struct FrameworkStressControlValueMathTests {
  @Test(
    "finite control formatting round-trips the representable extremes",
    arguments: [
      Double.leastNonzeroMagnitude, 1e-300, 1e-14, 1e-7, 1e16, 1e22,
      Double.greatestFiniteMagnitude,
    ])
  func finiteFormattingRoundTrips(value: Double) {
    for signed in [value, -value] {
      let formatted = formattedControlValue(signed, bounds: nil, step: value)
      #expect(Double(formatted) == signed)
      #expect(!formatted.contains("e"))
    }
  }

  @Test("integer track interpolation preserves adjacent large values")
  func adjacentIntegerTrackValues() {
    let lower = Int.max - 4
    let bounds = lower...Int.max
    for index in 0...4 {
      #expect(Int.controlValue(at: Double(index) / 4, bounds: bounds, step: 1) == lower + index)
    }
    #expect(
      Double.controlFraction(
        0, bounds: -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude) == 0.5)
  }

  @Test("pressing a quantized marker preserves every model value", arguments: 2...16)
  func markerRoundTrip(width: Int) {
    let track = CellRect(origin: .init(x: -10, y: 0), size: .init(width: width, height: 1))
    for value in 0...10 {
      let cell = sliderMarkerPosition(fraction: Double(value) / 10, width: width)
      #expect(
        sliderValue(
          at: Double(cell - 10) + 0.5, in: track, bounds: 0...10,
          step: 1, currentValue: value) == value)
    }
  }

  @Test("stress control value math 001 negative integer step uses its magnitude")
  func controlValueMath001NegativeIntegerStepUsesMagnitude() {
    // Hypothesis: a negative authored step can invert the requested delta instead of being sanitized.
    #expect(steppedControlValue(from: 5, delta: 2, step: -3, bounds: nil) == 11)
  }

  @Test("stress control value math 002 zero integer step still advances one unit")
  func controlValueMath002ZeroIntegerStepAdvancesOneUnit() {
    // Hypothesis: a zero authored step can make a Stepper permanently inert.
    #expect(steppedControlValue(from: 3, delta: 1, step: 0, bounds: nil) == 4)
  }

  @Test("stress control value math 003 oversized integer increment clamps to upper bound")
  func controlValueMath003OversizedIntegerIncrementClampsUpperBound() {
    // Hypothesis: scaling the delta before clamping can overshoot rather than land on the bound.
    #expect(steppedControlValue(from: 4, delta: 20, step: 3, bounds: -5...9) == 9)
  }

  @Test("stress control value math 004 oversized integer decrement clamps to lower bound")
  func controlValueMath004OversizedIntegerDecrementClampsLowerBound() {
    // Hypothesis: a large negative delta can bypass the lower-bound clamp.
    #expect(steppedControlValue(from: 4, delta: -20, step: 3, bounds: -5...9) == -5)
  }

  @Test("stress control value math 005 upper-bound integer cannot adjust farther outward")
  func controlValueMath005UpperBoundCannotAdjustOutward() {
    // Hypothesis: comparing the raw stepped value can report adjustability after clamping is inert.
    #expect(!stepperCanAdjust(10, delta: 4, step: 3, bounds: 0...10))
  }

  @Test("stress control value math 006 upper-bound integer can immediately reverse")
  func controlValueMath006UpperBoundCanImmediatelyReverse() {
    // Hypothesis: a prior outward clamp can incorrectly suppress the next inward adjustment.
    #expect(stepperCanAdjust(10, delta: -1, step: 3, bounds: 0...10))
    #expect(steppedControlValue(from: 10, delta: -1, step: 3, bounds: 0...10) == 7)
  }

  @Test("stress control value math 007 negative double step uses its magnitude")
  func controlValueMath007NegativeDoubleStepUsesMagnitude() {
    // Hypothesis: floating-point step sanitization can preserve the sign and reverse adjustment.
    #expect(steppedControlValue(from: 0.5, delta: 1, step: -0.25, bounds: nil) == 0.75)
  }

  @Test("stress control value math 008 zero double step falls back to one")
  func controlValueMath008ZeroDoubleStepFallsBackToOne() {
    // Hypothesis: a zero floating-point step can propagate an inert value through cleanup.
    #expect(steppedControlValue(from: 0.25, delta: 1, step: 0.0, bounds: nil) == 1.25)
  }

  @Test("stress control value math 009 infinite double step falls back to one")
  func controlValueMath009InfiniteDoubleStepFallsBackToOne() {
    // Hypothesis: an infinite step can escape sanitization and poison the bound comparison.
    #expect(
      steppedControlValue(from: 0.25, delta: 1, step: .infinity, bounds: 0.0...2.0)
        == 1.25
    )
  }

  @Test("stress control value math 010 NaN double step falls back to one")
  func controlValueMath010NaNDoubleStepFallsBackToOne() {
    // Hypothesis: NaN can survive abs-based validation because ordinary comparisons are false.
    #expect(
      steppedControlValue(from: 0.25, delta: 1, step: .nan, bounds: 0.0...2.0)
        == 1.25
    )
  }

  @Test("stress control value math 011 track snapping is anchored to a nonzero lower bound")
  func controlValueMath011TrackSnappingUsesNonzeroLowerBound() {
    // Hypothesis: snapping can accidentally use zero as its grid origin for shifted ranges.
    #expect(Double.controlValueFromTrack(0.62, bounds: 0.1...1.1, step: 0.25) == 0.6)
  }

  @Test("stress control value math 012 half-step track tie rounds upward")
  func controlValueMath012HalfStepTrackTieRoundsUpward() {
    // Hypothesis: binary floating-point noise can resolve an exact half-step toward the lower tick.
    #expect(Double.controlValueFromTrack(0.225, bounds: 0.0...1.0, step: 0.15) == 0.3)
  }

  @Test("stress control value math 013 formatted negative zero is canonical zero")
  func controlValueMath013FormattedNegativeZeroIsCanonicalZero() {
    // Hypothesis: trimming a rounded negative zero can leak the sign into authored control labels.
    #expect(formattedControlValue(-0.0, bounds: -1.0...1.0, step: 0.1) == "0")
  }

  @Test("an Int.min integer step is the largest representable step")
  func intMinIntegerStepSaturatesToLargestStep() {
    // `Int.min` has no `Int` magnitude; it must sanitize, not trap.
    #expect(Int.sanitizedControlStep(Int.min) == Int.max)
    #expect(Int.sanitizedControlStep(-Int.max) == Int.max)
    #expect(steppedControlValue(from: 5, delta: 1, step: Int.min, bounds: 0...10) == 10)
    #expect(steppedControlValue(from: 5, delta: -1, step: Int.min, bounds: 0...10) == 0)
  }

  @Test("integer stepping saturates at Int's edges instead of trapping")
  func integerSteppingSaturatesAtIntEdges() {
    #expect(steppedControlValue(from: 5, delta: 1, step: Int.max, bounds: 0...10) == 10)
    #expect(steppedControlValue(from: 5, delta: 1, step: Int.max, bounds: nil) == Int.max)
    #expect(steppedControlValue(from: -5, delta: -1, step: Int.max, bounds: nil) == Int.min)
    #expect(steppedControlValue(from: Int.max, delta: 1, step: 1, bounds: nil) == Int.max)
    #expect(steppedControlValue(from: Int.min, delta: -3, step: 2, bounds: nil) == Int.min)
    #expect(!stepperCanAdjust(Int.max, delta: 1, step: 1, bounds: nil))
    #expect(stepperCanAdjust(Int.max, delta: -1, step: 1, bounds: nil))
    // A result that stays representable is exact even when delta * step is not.
    #expect(steppedControlValue(from: Int.min, delta: 2, step: Int.max, bounds: nil) == Int.max - 1)
    #expect(steppedControlValue(from: Int.max, delta: -2, step: Int.max, bounds: nil) == -Int.max)
  }
}
