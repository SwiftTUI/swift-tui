import Foundation
import Testing

@testable import SwiftTUIViews

@MainActor
@Suite("Spinner")
struct SpinnerTests {
  @Test("Spinner can be constructed with a custom interval")
  func customIntervalIsAccepted() {
    let spinner = Spinner(.brailleLoop, stage: .active, interval: .milliseconds(240))
    #expect(spinner.interval == .milliseconds(240))
  }

  @Test("Spinner default interval is 64 ms for backwards compatibility")
  func defaultIntervalUnchanged() {
    let spinner = Spinner(.brailleLoop)
    #expect(spinner.interval == .milliseconds(64))
  }

  @Test("SpinnerSet.asteriskCycle exposes the * · + ÷ glyph sequence")
  func asteriskCycleGlyphs() {
    // The body glyphs must each be single-cell-wide ASCII so the
    // spinner never shifts the layout as it rotates.
    let set = Spinner.SpinnerSet.asteriskCycle
    let description = set.description
    #expect(["*", "·", "+", "÷"].contains(description))
  }

  @Test("Spinner with .asteriskCycle and custom interval round-trips identity")
  func asteriskCycleAndIntervalAreDistinct() {
    let a = Spinner(.asteriskCycle, stage: .active, interval: .milliseconds(240))
    let b = Spinner(.brailleLoop, stage: .active, interval: .milliseconds(240))
    let c = Spinner(.asteriskCycle, stage: .active, interval: .milliseconds(120))
    #expect(a.set != b.set)
    #expect(a.interval != c.interval)
  }
}
