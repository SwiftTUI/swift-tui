import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCNumericTests {
  @Test func setC177ContinuousSliderSteps() {
    func check(_ bounds: ClosedRange<Double>, _ track: Double, _ adjustment: Double) {
      let steps = continuousSliderSteps(for: bounds)
      #expect(abs(steps.track - track) < 1e-12, "\(bounds): \(steps)")
      #expect(abs(steps.adjustment - adjustment) < 1e-12, "\(bounds): \(steps)")
    }
    check(0...1, 0.01, 0.1)
    check(0...3, 0.01, 0.1)
    check(0...0.5, 0.001, 0.01)
    check(0...100, 1, 10)
    check(5...5, 1, 1)
  }

  @Test func setC178FormattedValueCleansFloatNoise() {
    #expect(Double.formattedControlValue(0.1 + 0.2, bounds: 0...1, step: 0.1) == "0.3")
    #expect(Double.formattedControlValue(0.1 + 0.2, bounds: nil, step: 0.1) == "0.3")
  }

  @Test func setC179TrimmedControlStringAvoidsExponents() {
    #expect(trimmedControlString(1e-7) == "0.0000001")
    #expect(trimmedControlString(1.25e-5) == "0.0000125")
    #expect(trimmedControlString(1e21) == "1000000000000000000000")
    #expect(trimmedControlString(-2.5e-3) == "-0.0025")
    #expect(trimmedControlString(0) == "0")
  }

  @Test func setC180SteppedValuesLandExactly() {
    #expect(Double.steppedControlValue(from: 0.9, delta: 1, step: 0.1, bounds: 0...1) == 1)
    #expect(Double.steppedControlValue(from: 1.0, delta: 1, step: 0.1, bounds: 0...1) == 1)
    #expect(Double.steppedControlValue(from: 0.3, delta: -3, step: 0.1, bounds: 0...1) == 0)
  }

  @Test func setC181ProgressSummaryText() {
    #expect(progressSummaryText(value: 0.25, total: 1) == "0.25/1")
    #expect(progressSummaryText(value: 2.25, total: 10) == "2.3/10")
    #expect(progressSummaryText(value: 5, total: 0) == "100%")
    #expect(progressSummaryText(value: 0, total: .infinity) == "0%")
  }

  @Test func setC182IntTrackValueNearMaxDoesNotTrap() {
    let top = Int.controlValueFromTrack(Double(Int.max - 1), bounds: 0...Int.max, step: 2)
    #expect(top >= 0 && top <= Int.max)
    let middle = Int.controlValueFromTrack(Double(Int.max / 2), bounds: 0...Int.max, step: 3)
    #expect(middle >= 0 && middle <= Int.max && middle % 3 == 0)
  }

  @Test func setC183ContinuousSliderArrowsReachOneExactly() throws {
    let box = SetCNumericBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC183"),
      size: .init(width: 40, height: 4)
    ) { Slider("Effort", value: box.value, in: 0...1) }
    defer { h.shutdown() }
    _ = try h.focusText("Effort")
    for _ in 0..<10 { _ = try h.pressKey(.init(.arrowRight)) }
    #expect(box.current == 1, "\(box.current)")
    #expect(!h.frame.contains("0.99"), "\(h.frame)")
  }

  @Test func setC184DoubleStepperShowsCleanDecimal() throws {
    let box = SetCNumericBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC184"),
      size: .init(width: 40, height: 4)
    ) { Stepper("Retries", value: box.value, in: 0...1, step: 0.1) }
    defer { h.shutdown() }
    _ = try h.focusText("Retries")
    for _ in 0..<3 { _ = try h.pressKey(.init(.arrowRight)) }
    #expect(abs(box.current - 0.3) < 1e-12, "\(box.current)")
    #expect(h.frame.contains("0.3"), "\(h.frame)")
    #expect(!h.frame.contains("0.30000"), "\(h.frame)")
  }

  @Test func setC185TrackClickAtLastCellReachesUpperBound() throws {
    let box = SetCNumericBox()
    box.current = 0.5
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC185"),
      size: .init(width: 40, height: 4)
    ) { Slider("Effort", value: box.value, in: 0...1) }
    defer { h.shutdown() }
    let last = try #require(h.point(forText: "─", chooseLast: true), "\(h.frame)")
    _ = try h.click(last)
    #expect(box.current == 1, "\(box.current) after clicking \(last): \(h.frame)")
    let first = try #require(h.point(forText: "━"), "\(h.frame)")
    _ = try h.click(first)
    #expect(box.current < 0.1, "\(box.current) after clicking \(first): \(h.frame)")
  }

  @Test func setC186SliderMarkerPositionEdges() {
    #expect(sliderMarkerPosition(fraction: 1, width: 1) == 0)
    #expect(sliderMarkerPosition(fraction: .nan, width: 5) == 0)
    #expect(sliderMarkerPosition(fraction: 0.5, width: 2) == 1)
  }
}

@MainActor
private final class SetCNumericBox {
  var current = 0.0
  var value: Binding<Double> {
    .init(get: { self.current }, set: { self.current = $0 })
  }
}
