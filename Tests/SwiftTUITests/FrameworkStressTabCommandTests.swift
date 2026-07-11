import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI tab and command stress behavior", .serialized)
struct FrameworkStressTabCommandTests {}

@MainActor
private final class TabCommandStressProbe {
  var events: [String] = []
}

// MARK: - Attempt 001: focused-tab identity through reorder

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 001 focused tab follows its tag through reorder")
  func stressTabCommand001FocusedTabFollowsTagThroughReorder() throws {
    // Hypothesis: stored strip focus may survive by ordinal instead of by tag,
    // activating a different tab after the declarations rotate in place.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC001", "Root"),
      size: .init(width: 56, height: 10)
    ) {
      StressTC001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressTC001Fixture.tabsIdentity)
    _ = try harness.pressKey(KeyPress(.arrowRight))
    _ = try harness.pressKey(KeyPress(.character("r"), modifiers: .ctrl))
    let frame = try harness.pressKey(KeyPress(.return))

    #expect(frame.contains("B body selected"))
    #expect(!frame.contains("C body selected"))
  }
}

@MainActor
private struct StressTC001Fixture: View {
  static let tabsIdentity = testIdentity("StressTC001", "Tabs")

  @State private var rotated = false
  @State private var selection = "a"

  var body: some View {
    Panel(id: "stress-tc-001-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Text("selection \(selection)")
        TabView(selection: $selection) {
          if rotated {
            tab("B", value: "b")
            tab("C", value: "c")
            tab("A", value: "a")
          } else {
            tab("A", value: "a")
            tab("B", value: "b")
            tab("C", value: "c")
          }
        }
        .id(Self.tabsIdentity)
      }
    }
    .keyCommand("Rotate tabs", key: .character("r"), modifiers: .ctrl) {
      rotated = true
    }
    .frame(width: 54, height: 8, alignment: .topLeading)
  }

  private func tab(_ title: String, value: String) -> some View {
    Tab(title, value: value) {
      Text("\(title) body selected")
    }
  }
}

// MARK: - Attempt 002: focused-tab removal fallback

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 002 removed focused tab falls forward at its old ordinal")
  func stressTabCommand002RemovedFocusedTabFallsForward() throws {
    // Hypothesis: when the tag carrying stored focus departs, stale tag lookup
    // may jump back to selection instead of retaining the departed tab's slot.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC002", "Root"),
      size: .init(width: 56, height: 10)
    ) {
      StressTC002Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressTC002Fixture.tabsIdentity)
    _ = try harness.pressKey(KeyPress(.arrowRight))
    _ = try harness.pressKey(KeyPress(.character("x"), modifiers: .ctrl))
    let frame = try harness.pressKey(KeyPress(.return))

    #expect(frame.contains("C body selected"))
    #expect(!frame.contains("A body selected"))
  }
}

@MainActor
private struct StressTC002Fixture: View {
  static let tabsIdentity = testIdentity("StressTC002", "Tabs")

  @State private var includesB = true
  @State private var selection = "a"

  var body: some View {
    Panel(id: "stress-tc-002-panel") {
      TabView(selection: $selection) {
        Tab("A", value: "a") { Text("A body selected") }
        if includesB {
          Tab("B", value: "b") { Text("B body selected") }
        }
        Tab("C", value: "c") { Text("C body selected") }
      }
      .id(Self.tabsIdentity)
    }
    .keyCommand("Remove B", key: .character("x"), modifiers: .ctrl) {
      includesB = false
    }
    .frame(width: 54, height: 8, alignment: .topLeading)
  }
}
