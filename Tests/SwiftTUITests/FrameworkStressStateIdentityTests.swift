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

// MARK: - Attempt 002: Reused StateBox across explicit identity replacement

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 002 explicit id replacement resets a reused view value")
  func stateIdentity002ExplicitIDReplacementResetsReusedValue() throws {
    // Hypothesis: a newly routed entity can be seeded from a StateBox mutated by the entity
    // it replaced when the authored view value itself is deliberately reused.
    let shared = StateIdentitySharedCounter(label: "002")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity002"),
      size: .init(width: 48, height: 9)
    ) {
      StateIdentity002Root(shared: shared)
    }
    defer { harness.shutdown() }

    var replacementFrames: [String] = []
    for generation in 0..<4 {
      _ = try harness.clickText("002 Increment")
      let frame = try harness.clickText("Replace 002")
      #expect(frame.contains("002 Owner \(generation + 1)"))
      replacementFrames.append(frame)
    }

    withKnownIssue("A reused StateBox carries its mutation across explicit-ID replacement") {
      #expect(replacementFrames.allSatisfy { $0.contains("002 Count 0") })
    }
  }

  private struct StateIdentity002Root: View {
    let shared: StateIdentitySharedCounter
    @State private var generation = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("002 Owner \(generation)")
        Button("Replace 002") { generation += 1 }
        shared.id("state-identity-002-\(generation)")
      }
    }
  }
}

// MARK: - Attempt 003: Reinserted reused value starts a fresh lifetime

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 003 removal and reinsertion do not resurrect state")
  func stateIdentity003RemovalReinsertionDoesNotResurrectState() throws {
    // Hypothesis: retained owner values on a long-lived StateBox can outlive graph-node teardown
    // and silently seed the next lifetime when the exact authored value is reinserted.
    let shared = StateIdentitySharedCounter(label: "003")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity003"),
      size: .init(width: 48, height: 9)
    ) {
      StateIdentity003Root(shared: shared)
    }
    defer { harness.shutdown() }

    var reinsertionFrames: [String] = []
    for _ in 0..<4 {
      _ = try harness.clickText("003 Increment")
      var frame = try harness.clickText("Remove 003")
      #expect(!frame.contains("003 Count"))
      frame = try harness.clickText("Insert 003")
      reinsertionFrames.append(frame)
    }

    withKnownIssue("A reused StateBox resurrects its mutation after committed removal") {
      #expect(reinsertionFrames.allSatisfy { $0.contains("003 Count 0") })
    }
  }

  private struct StateIdentity003Root: View {
    let shared: StateIdentitySharedCounter
    @State private var isVisible = true

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button(isVisible ? "Remove 003" : "Insert 003") { isVisible.toggle() }
        if isVisible {
          shared
        }
      }
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
