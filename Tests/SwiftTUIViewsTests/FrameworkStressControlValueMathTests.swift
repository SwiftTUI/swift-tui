import Testing

@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI control value math stress behavior", .serialized)
struct FrameworkStressControlValueMathTests {
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
}
