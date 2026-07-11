import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI environment and style stress behavior", .serialized)
struct FrameworkStressEnvironmentStyleTests {}

private enum EnvironmentStyleStringKey: EnvironmentKey {
  static let defaultValue = "default"
}

extension EnvironmentValues {
  fileprivate var environmentStyleString: String {
    get { self[EnvironmentStyleStringKey.self] }
    set { self[EnvironmentStyleStringKey.self] = newValue }
  }
}

// MARK: - Attempt 001: reminted nested override removal

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 001 reminted override removal restores live grandparent")
  func environmentStyle001RemintedOverrideRemovalRestoresLiveGrandparent() throws {
    // Hypothesis: removing a reminted nearest writer can leave its snapshot on a stable reader
    // instead of exposing the simultaneously updated grandparent value.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle001"),
      size: .init(width: 66, height: 7)
    ) {
      EnvironmentStyle001Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      var frame = try harness.clickText("Advance Outer 001")
      #expect(frame.contains("001 value inner-\(generation)"))

      frame = try harness.clickText("Toggle Override 001")
      #expect(frame.contains("001 value outer-\(generation)"))

      frame = try harness.clickText("Toggle Override 001")
      #expect(frame.contains("001 value inner-\(generation)"))
    }
  }
}

private struct EnvironmentStyle001Reader: View {
  @Environment(\.environmentStyleString) private var value

  var body: some View {
    Text("001 value \(value)")
  }
}

private struct EnvironmentStyle001Root: View {
  @State private var generation = 0
  @State private var hasOverride = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Outer 001") { generation += 1 }
      Button("Toggle Override 001") { hasOverride.toggle() }
      if hasOverride {
        EnvironmentStyle001Reader()
          .environment(\.environmentStyleString, "inner-\(generation)")
          .id("environment-style-001-inner-\(generation)")
      } else {
        EnvironmentStyle001Reader()
          .id("environment-style-001-reader")
      }
    }
    .environment(\.environmentStyleString, "outer-\(generation)")
  }
}
