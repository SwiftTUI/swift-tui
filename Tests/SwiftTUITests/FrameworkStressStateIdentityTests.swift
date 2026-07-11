import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct FrameworkStressStateIdentityTests {}

// MARK: - Attempt 001: Graph-scoped state seed isolation

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 001 fresh graph ignores a prior graph mutation")
  func stateIdentity001FreshGraphSeedIsolation() throws {
    // Hypothesis: graph-backed writes also update StateBox.seedValue, so mounting the exact
    // same view value in a later graph may inherit the retired graph's final mutation.
    let shared = StateIdentitySharedCounter(label: "001")
    let first = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity001", "first"),
      size: .init(width: 42, height: 8)
    ) {
      shared
    }
    for expected in 1...4 {
      let frame = try first.clickText("001 Increment")
      #expect(frame.contains("001 Count \(expected)"))
    }
    first.shutdown()

    let second = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity001", "second"),
      size: .init(width: 42, height: 8)
    ) {
      shared
    }
    defer { second.shutdown() }

    withKnownIssue(
      "A reused stateful view value seeds a fresh graph from the retired graph's mutation"
    ) {
      #expect(second.frame.contains("001 Count 0"))
    }
  }
}

private struct StateIdentitySharedCounter: View {
  let label: String
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) Count \(count)")
      Button("\(label) Increment") { count += 1 }
    }
  }
}
