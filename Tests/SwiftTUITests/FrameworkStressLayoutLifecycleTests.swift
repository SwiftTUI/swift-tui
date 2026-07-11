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

// MARK: - Attempt 002: retained scrolling after content resize

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 002 retained scroll placement follows resized content")
  func stress002RetainedScrollPlacementFollowsResizedContent() throws {
    // Hypothesis: viewport-translation reuse may retain the target's old
    // placement when its height changes before a scroll-to command.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL002", "Root"),
      size: .init(width: 42, height: 10)
    ) {
      StressLL002Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Resize Target")
      let frame = try harness.clickText("Reveal Target")
      let height = generation.isMultiple(of: 2) ? 1 : 3
      #expect(frame.contains("target \(generation) height \(height)"))
      #expect(harness.scrollPositionRegistrationCount == 1)
    }
  }
}

@MainActor
private struct StressLL002Fixture: View {
  @State private var generation = 0

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("Resize Target") { generation += 1 }
          Button("Reveal Target") { _ = proxy.scrollTo("target", anchor: .center) }
        }
        ScrollView(.vertical, showsIndicators: true) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<7, id: \.self) { row in
              Text("prefix \(row)")
            }
            Text(
              "target \(generation) height \(generation.isMultiple(of: 2) ? 1 : 3)"
            )
            .frame(height: generation.isMultiple(of: 2) ? 1 : 3, alignment: .topLeading)
            .id("target")
            ForEach(7..<12, id: \.self) { row in
              Text("suffix \(row)")
            }
          }
        }
        .frame(width: 40, height: 6, alignment: .topLeading)
      }
    }
  }
}
