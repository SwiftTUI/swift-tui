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

private enum EnvironmentStyleOptionalKey: EnvironmentKey {
  static let defaultValue: String? = nil
}

extension EnvironmentValues {
  fileprivate var environmentStyleOptional: String? {
    get { self[EnvironmentStyleOptionalKey.self] }
    set { self[EnvironmentStyleOptionalKey.self] = newValue }
  }
}

private func environmentStyleText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
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

// MARK: - Attempt 002: keyed writer reorder

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 002 keyed writer reorder preserves entity snapshots")
  func environmentStyle002KeyedWriterReorderPreservesEntitySnapshots() throws {
    // Hypothesis: environment snapshots can follow structural indices when keyed children move,
    // making a row inherit the override previously authored at its new position.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle002"),
      size: .init(width: 68, height: 8)
    ) {
      EnvironmentStyle002Root()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      _ = try harness.clickText("Reorder Writers 002")
      let frame = try harness.clickText("Advance Writers 002")
      #expect(frame.contains("002 row A value A-\(generation)"))
      #expect(frame.contains("002 row B value B-\(generation)"))
      #expect(frame.contains("002 row C value C-\(generation)"))
    }
  }
}

private struct EnvironmentStyle002Item: Identifiable {
  let id: String
}

private struct EnvironmentStyle002Reader: View {
  let id: String
  @Environment(\.environmentStyleString) private var value

  var body: some View {
    Text("002 row \(id) value \(value)")
  }
}

private struct EnvironmentStyle002Root: View {
  @State private var generation = 0
  @State private var reversed = false

  private var items: [EnvironmentStyle002Item] {
    let source = ["A", "B", "C"].map(EnvironmentStyle002Item.init(id:))
    return reversed ? Array(source.reversed()) : source
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder Writers 002") { reversed.toggle() }
      Button("Advance Writers 002") { generation += 1 }
      ForEach(items) { item in
        EnvironmentStyle002Reader(id: item.id)
          .environment(\.environmentStyleString, "\(item.id)-\(generation)")
      }
    }
  }
}

// MARK: - Attempt 003: optional writer absence versus explicit nil

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 003 removing explicit nil reveals optional outer value")
  func environmentStyle003RemovingExplicitNilRevealsOptionalOuterValue() {
    // Hypothesis: snapshot equality can collapse an absent Optional writer with an explicit nil
    // writer, preventing removal from exposing the live outer Optional value.
    struct Reader: View {
      @Environment(\.environmentStyleOptional) private var value

      var body: some View {
        Text("003 value \(value ?? "nil")")
      }
    }

    struct Root: View {
      let generation: Int
      let masksOuter: Bool

      var body: some View {
        Group {
          if masksOuter {
            Reader().environment(\.environmentStyleOptional, nil)
          } else {
            Reader()
          }
        }
        .environment(\.environmentStyleOptional, "outer-\(generation)")
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("EnvironmentStyle003")
    for generation in 0..<18 {
      let masksOuter = generation.isMultiple(of: 2)
      let frame = renderer.render(
        Root(generation: generation, masksOuter: masksOuter),
        context: .init(identity: identity, invalidatedIdentities: [identity])
      )
      #expect(
        environmentStyleText(frame).contains(
          masksOuter ? "003 value nil" : "003 value outer-\(generation)"
        )
      )
    }
  }
}
