import Synchronization
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite("SwiftTUI runtime and transport stress behavior", .serialized)
struct FrameworkStressRuntimeTransportTests {}

// MARK: - Attempt 001: scroll-location alternation

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 001 alternating scroll locations keep event boundaries")
  func runtimeTransport001AlternatingScrollLocationsKeepEventBoundaries() {
    // Hypothesis: a scroll burst that returns to an earlier cell can merge across
    // the intervening location and apply deltas to the wrong hit-test target.
    let first = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 1),
      location: .init(x: 2, y: 3)
    )
    let second = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 2),
      location: .init(x: 8, y: 3)
    )
    let third = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 3),
      location: .init(x: 2, y: 3)
    )

    #expect(
      coalescedInputEvents([.mouse(first), .mouse(second), .mouse(third)]) == [
        .mouse(first), .mouse(second), .mouse(third)
      ]
    )
  }
}
