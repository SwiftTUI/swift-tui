import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The part of review finding 1 that predates the transitions work. This
/// file uses only API that exists at swift-tui 0.22.2 and is run there too.
@MainActor
@Suite("Transition stages review baseline", .serialized)
struct TransitionStagesReviewBaselineTests {
  private static let letters = "ABCDEFGHIJKLMNOPQRST"
  private static let linear = Animation.linear(duration: .milliseconds(800))

  @Test("a view that leaves inside a departing view with a transition plans no overlay of its own")
  func nestedBuiltInTransitionsPlanOneRemoval() throws {
    let probe = try StagesReviewProbe(named: "nested-built-in") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          HStack(spacing: 0) { Text(Self.letters).transition(.opacity) }
            .transition(.offset(x: 8, y: 0))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      // One view left the tree: the stack, with the text in it. The text's
      // presence inside the stack did not change, so its own transition has
      // nothing to play.
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      // The stack is half way along its eight columns, drawn once.
      #expect(probe.line(1) == "    " + Self.letters, "\(probe.frame)")
    }
  }
}
