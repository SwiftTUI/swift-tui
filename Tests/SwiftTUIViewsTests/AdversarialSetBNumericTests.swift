import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Adversarial set B, numeric saturation (031–037). STUI-608, STUI-615,
// STUI-903 and STUI-891 each came from arithmetic that assumed a mid-range,
// finite input. These cases push the control and progress helpers to the
// representable edges. Cases that could trap run in a child process so a
// trap is reported as a failure instead of ending the test run.
@Suite("Adversarial set B: numeric saturation")
struct AdversarialSetBNumericTests {
  @Test func setB031MinimumDeltaSaturatesInsteadOfWrapping() {
    #expect(steppedControlValue(from: 0, delta: Int.min, step: 1, bounds: nil) == Int.min)
    #expect(steppedControlValue(from: 0, delta: Int.min, step: 2, bounds: nil) == Int.min)
    #expect(steppedControlValue(from: 0, delta: Int.min, step: Int.min, bounds: 0...10) == 0)
    #expect(steppedControlValue(from: Int.max, delta: 1, step: Int.max, bounds: nil) == Int.max)
    #expect(!stepperCanAdjust(Int.min, delta: Int.min, step: 1, bounds: nil))
    #expect(!stepperCanAdjust(Int.max, delta: Int.max, step: Int.max, bounds: nil))
  }

  @Test func setB032IntegerSliderAtTheFarEdgeOfIntRangeDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
      let track = CellRect(origin: .init(x: 10, y: 0), size: .init(width: 10, height: 1))
      let upper = sliderValue(at: 18.5, in: track, bounds: 0...Int.max, step: 1)
      #expect(upper == Int.max, "\(upper)")
      let lower = sliderValue(at: 11.5, in: track, bounds: Int.min...0, step: 1)
      #expect(lower == Int.min, "\(lower)")
      let huge = Int.controlValueFromTrack(9.3e18, bounds: Int.min...Int.max, step: 1)
      #expect(huge == Int.max, "\(huge)")
    }
  }

  @MainActor
  @Test func setB033NaNModelNeverAdjustsOrWritesNaN() {
    #expect(!stepperCanAdjust(Double.nan, delta: 1, step: 1, bounds: 0.0...10.0))
    var value = Double.nan
    var writes: [Double] = []
    let binding = Binding(
      get: { value },
      set: {
        value = $0
        writes.append($0)
      })
    let changed = updateBoundControlValue(binding, delta: 1, step: 1, bounds: 0.0...10.0)
    let allFinite = writes.allSatisfy { $0.isFinite }
    #expect(allFinite, "\(writes)")
    if changed {
      #expect(value.isFinite, "an accepted adjustment must leave a finite value: \(value)")
    }
    #expect(formattedControlValue(Double.nan, bounds: 0.0...10.0, step: 1) != "nan")
  }

  @Test func setB034LargeDoubleValuesFormatWithoutTrapping() async {
    await #expect(processExitsWith: .success) {
      let formatted = formattedControlValue(1e16, bounds: nil, step: 1.0)
      #expect(!formatted.isEmpty)
      #expect(!formatted.contains("e"), "\(formatted)")
    }
    await #expect(processExitsWith: .success) {
      let stepped = formattedControlValue(1e22, bounds: 0.0...1e23, step: 1e21)
      #expect(!stepped.isEmpty)
    }
    await #expect(processExitsWith: .success) {
      #expect(metricValueString(1e19) != "0")
      #expect(!metricValueString(-1e19).isEmpty)
    }
  }

  @Test func setB035StepLargerThanTheRangeStillReachesBothBounds() {
    #expect(steppedControlValue(from: 3, delta: 1, step: 100, bounds: 0...10) == 10)
    #expect(steppedControlValue(from: 10, delta: -1, step: 100, bounds: 0...10) == 0)
    #expect(steppedControlValue(from: 0, delta: 1, step: 100, bounds: 0...10) == 10)
    let track = CellRect(origin: .init(x: 10, y: 0), size: .init(width: 10, height: 1))
    #expect(sliderValue(at: 14.5, in: track, bounds: 0...10, step: 100) == 0)
    #expect(sliderValue(at: 18.5, in: track, bounds: 0...10, step: 100) == 10)
    #expect(Double.controlValueFromTrack(0.0, bounds: 0.0...1.0, step: 5.0) == 0)
    #expect(Double.controlValueFromTrack(1.0, bounds: 0.0...1.0, step: 5.0) == 1)
    #expect(Double.controlValueFromTrack(1.4, bounds: 0.0...1.0, step: 5.0) == 1)
  }

  @Test func setB036DegenerateSliderSpansStayFiniteAndInBounds() {
    let flat = continuousSliderSteps(for: 5.0...5.0)
    #expect(flat.track.isFinite && flat.track > 0, "\(flat)")
    #expect(flat.adjustment.isFinite && flat.adjustment > 0, "\(flat)")
    let subnormal = continuousSliderSteps(for: 0.0...(100 * Double.leastNonzeroMagnitude))
    #expect(subnormal.track.isFinite && subnormal.track > 0, "\(subnormal)")
    let vast = continuousSliderSteps(for: 0.0...Double.greatestFiniteMagnitude)
    #expect(vast.track.isFinite && vast.adjustment.isFinite, "\(vast)")
    let overflowing = sliderFraction(value: 7, bounds: 5.0...5.0)
    #expect(overflowing.isFinite && (0...1).contains(overflowing), "\(overflowing)")
    let exact = sliderFraction(value: 5, bounds: 5.0...5.0)
    #expect(exact.isFinite && (0...1).contains(exact), "\(exact)")
    let fromNaN = Double.controlValueFromTrack(.nan, bounds: 0.0...1.0, step: 0.5)
    #expect(fromNaN == 0, "a NaN track sample must land on the lower bound: \(fromNaN)")
    let fromInfinity = Double.controlValueFromTrack(.infinity, bounds: 0.0...1.0, step: 0.5)
    #expect(fromInfinity == 1, "\(fromInfinity)")
  }

  @Test func setB037ProgressSummariesAgreeWithTheClampedFraction() async {
    #expect(progressSummaryText(value: 1, total: .nan) == "100%")
    #expect(progressSummaryText(value: 0.5, total: -0.0) == "100%")
    #expect(progressSummaryText(value: 2.55, total: 10) == "2.6/10")
    #expect(progressSummaryText(value: 1e300, total: 1e-300) == "0/0")
    #expect(progressFraction(value: 0.05, total: 0.1) == 0.5)
    let half = progressSummaryText(value: 0.05, total: 0.1)
    #expect(half != "0.1/0.1", "half of a tenth must not read as complete: \(half)")
    let nearlyEmpty = progressSummaryText(value: 0.04, total: 0.1)
    #expect(nearlyEmpty != "0.0/0.1", "40% must not read as empty: \(nearlyEmpty)")
    await #expect(processExitsWith: .success) {
      #expect(meterSummaryText(value: .nan, total: 1) == "0%")
    }
    await #expect(processExitsWith: .success) {
      #expect(meterSummaryText(value: .infinity, total: 0) == "100%")
    }
    await #expect(processExitsWith: .success) {
      #expect(!progressSummaryText(value: 1e19, total: 1e19).isEmpty)
    }
  }
}
