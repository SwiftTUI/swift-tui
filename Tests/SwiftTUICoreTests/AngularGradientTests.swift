import Testing

@testable import SwiftTUICore

/// `AngularGradient.location(atAngle:)` against SwiftUI as measured in the
/// org's report 2026-09-19-001. Angles are screen angles: zero at three
/// o'clock, increasing clockwise.
@Suite
struct AngularGradientTests {
  private let colors = Gradient(colors: [Color.red, Color.blue])

  private func location(
    start: Double, end: Double, at degrees: Double
  ) -> Double {
    AngularGradient(
      gradient: colors, startAngle: .degrees(start), endAngle: .degrees(end)
    ).location(atAngle: degrees * .pi / 180)
  }

  @Test("a conic gradient is one turn, clockwise from three o'clock")
  func conic() {
    let gradient = AngularGradient(gradient: colors)
    #expect(abs(gradient.location(atAngle: 0)) < 1e-9)
    #expect(abs(gradient.location(atAngle: .pi / 4) - 0.125) < 1e-9)
    #expect(abs(gradient.location(atAngle: .pi / 2) - 0.25) < 1e-9)
    // `atan2` reports the upper half of the screen as negative angles.
    #expect(abs(gradient.location(atAngle: -.pi / 2) - 0.75) < 1e-9)
  }

  @Test("a positive angle rotates a conic gradient clockwise")
  func conicAngle() {
    let gradient = AngularGradient(gradient: colors, angle: .degrees(45))
    #expect(abs(gradient.location(atAngle: .pi / 4)) < 1e-9)
    #expect(abs(gradient.location(atAngle: 3 * .pi / 4) - 0.25) < 1e-9)
  }

  @Test("a span of less than a turn splits its missing area at the midpoint")
  func partialSpan() {
    // Measured: 0 to 90 runs the gradient, 90 to 225 is the last color, and 225
    // to 360 is the first.
    #expect(abs(location(start: 0, end: 90, at: 45) - 0.5) < 1e-9)
    #expect(location(start: 0, end: 90, at: 100) == 1)
    #expect(location(start: 0, end: 90, at: 224) == 1)
    #expect(location(start: 0, end: 90, at: 226) == 0)
    #expect(location(start: 0, end: 90, at: 350) == 0)
    // Measured: 0 to 180 splits its missing half turn at 270.
    #expect(location(start: 0, end: 180, at: 269) == 1)
    #expect(location(start: 0, end: 180, at: 271) == 0)
  }

  @Test("a span of more than a turn draws its last complete turn")
  func overfullSpan() {
    // Measured: 0 to 540 draws 180 to 540, and location is the angle's share of
    // the whole span.
    #expect(abs(location(start: 0, end: 540, at: 185) - 185.0 / 540) < 1e-9)
    #expect(abs(location(start: 0, end: 540, at: 5) - 365.0 / 540) < 1e-9)
    #expect(abs(location(start: 0, end: 540, at: 135) - 495.0 / 540) < 1e-9)
  }

  @Test("a negative span runs the gradient counter-clockwise")
  func reversedSpan() {
    // Measured: 90 to 0 is red at 90 and blue at 0. From 90 to 225 is the first
    // color and from 225 to 360 is the last.
    #expect(abs(location(start: 90, end: 0, at: 85) - 5.0 / 90) < 1e-9)
    #expect(abs(location(start: 90, end: 0, at: 5) - 85.0 / 90) < 1e-9)
    #expect(location(start: 90, end: 0, at: 100) == 0)
    #expect(location(start: 90, end: 0, at: 230) == 1)
  }

  @Test("values that are not finite do not trap")
  func nonFinite() {
    #expect(location(start: 0, end: 90, at: .nan) == 0)
    #expect(location(start: .infinity, end: 90, at: 10) == 0)
  }

  @Test("the angles interpolate, which is how the gradient animates")
  func animatableData() {
    var gradient = AngularGradient(gradient: colors, angle: .radians(0))
    var data = gradient.animatableData
    data.second.second = .init(1, 1 + 2 * .pi)
    gradient.animatableData = data
    #expect(gradient.startAngle == .radians(1))
    #expect(gradient.endAngle == .radians(1 + 2 * .pi))
  }
}
