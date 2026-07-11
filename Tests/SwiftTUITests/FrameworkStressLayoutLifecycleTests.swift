import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI layout and lifecycle stress behavior", .serialized)
struct FrameworkStressLayoutLifecycleTests {}

@MainActor
private final class StressLayoutLifecycleProbe {
  var events: [String] = []
  var count = 0
  var secondaryCount = 0
}

// MARK: - Attempt 001: ViewThatFits selection churn

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 001 ViewThatFits selection tracks changing candidate fit")
  func stress001ViewThatFitsSelectionTracksChangingCandidateFit() throws {
    // Hypothesis: retained layout may keep the previously selected candidate
    // after the first candidate crosses the proposal boundary.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL001", "Root"),
      size: .init(width: 40, height: 8)
    ) {
      StressLL001Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      let frame = try harness.clickText("Toggle Fit")
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("primary \(generation)"))
        #expect(!frame.contains("fallback \(generation)"))
      } else {
        #expect(frame.contains("fallback \(generation)"))
        #expect(!frame.contains("primary \(generation)"))
      }
      #expect(harness.lifecycleRegistrationCount <= 2)
    }
  }
}

@MainActor
private struct StressLL001Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Fit") { generation += 1 }
      ViewThatFits(in: .horizontal) {
        Text("primary \(generation)")
          .frame(width: generation.isMultiple(of: 2) ? 18 : 60)
        Text("fallback \(generation)")
          .frame(width: 18)
      }
      .frame(width: 24, height: 2, alignment: .topLeading)
    }
  }
}
