import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI navigation and presentation stress behavior", .serialized)
struct FrameworkStressNavigationPresentationTests {}

// MARK: - Attempt 001: live Boolean destination payload refresh

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 001 Boolean destination refreshes live payload")
  func stress001BooleanDestinationRefreshesLivePayload() throws {
    // Hypothesis: a Boolean destination's stable activation can retain its
    // opening payload when source state changes, or remint its local state.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP001", "Root"),
      size: .init(width: 52, height: 10)
    ) {
      StressNP001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Boolean Destination")
    for generation in 1...8 {
      _ = try harness.clickText("Increment Destination Local")
      let frame = try harness.clickText("Refresh Boolean Payload")
      #expect(frame.contains("Boolean payload \(generation) local \(generation)"))
      #expect(harness.actionRegistrationCount <= 3)
    }
  }
}

@MainActor
private struct StressNP001Fixture: View {
  @State private var isPresented = false
  @State private var generation = 0

  var body: some View {
    NavigationStack(id: "stress-np-001-stack") {
      Button("Open Boolean Destination") { isPresented = true }
        .navigationDestination(isPresented: $isPresented) {
          StressNP001Destination(
            generation: generation,
            generationBinding: $generation
          )
        }
    }
  }
}

@MainActor
private struct StressNP001Destination: View {
  let generation: Int
  @Binding var generationBinding: Int
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Boolean payload \(generation) local \(local)")
      Button("Increment Destination Local") { local += 1 }
      Button("Refresh Boolean Payload") { generationBinding += 1 }
    }
  }
}
