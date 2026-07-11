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

// MARK: - Attempt 003: inserted-prefix pointer routes

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 003 inserted prefix retargets every tab pointer route")
  func stressTabCommand003InsertedPrefixRetargetsPointerRoutes() throws {
    // Hypothesis: pointer descriptors keyed by strip ordinal may retain the
    // pre-insertion tag and activate B when the visible C route shifts right.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC003", "Root"),
      size: .init(width: 62, height: 11)
    ) {
      StressTC003Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Insert prefix")
    let frame = try harness.clickText("C")

    withKnownIssue("Inserting a leading tab leaves the visible C route bound to B") {
      #expect(frame.contains("C current content"))
      #expect(!frame.contains("B current content"))
    }
  }
}

@MainActor
private struct StressTC003Fixture: View {
  @State private var hasPrefix = false
  @State private var selection = "a"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Insert prefix") {
        hasPrefix = true
      }
      TabView(selection: $selection) {
        if hasPrefix {
          Tab("Prefix", value: "prefix") { Text("Prefix current content") }
        }
        Tab("A", value: "a") { Text("A current content") }
        Tab("B", value: "b") { Text("B current content") }
        Tab("C", value: "c") { Text("C current content") }
      }
      .id(testIdentity("StressTC003", "Tabs"))
    }
    .frame(width: 60, height: 9, alignment: .topLeading)
  }
}

// MARK: - Attempt 004: removed-prefix pointer routes

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 004 removed prefix retargets every tab pointer route")
  func stressTabCommand004RemovedPrefixRetargetsPointerRoutes() throws {
    // Hypothesis: removing the leading declaration may leave a trailing route
    // keyed to its old index, selecting no tab or the wrong surviving tag.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC004", "Root"),
      size: .init(width: 62, height: 11)
    ) {
      StressTC004Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Remove prefix")
    let frame = try harness.clickText("C")

    withKnownIssue("Removing a leading tab leaves the visible C route inert") {
      #expect(frame.contains("C current content"))
    }
    #expect(!frame.contains("B current content"))
  }
}

@MainActor
private struct StressTC004Fixture: View {
  @State private var hasPrefix = true
  @State private var selection = "a"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove prefix") {
        hasPrefix = false
      }
      TabView(selection: $selection) {
        if hasPrefix {
          Tab("Prefix", value: "prefix") { Text("Prefix current content") }
        }
        Tab("A", value: "a") { Text("A current content") }
        Tab("B", value: "b") { Text("B current content") }
        Tab("C", value: "c") { Text("C current content") }
      }
      .id(testIdentity("StressTC004", "Tabs"))
    }
    .frame(width: 60, height: 9, alignment: .topLeading)
  }
}

// MARK: - Attempt 005: style replacement with stored focus

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 005 style replacement preserves focused activation")
  func stressTabCommand005StyleReplacementPreservesFocusedActivation() throws {
    // Hypothesis: replacing the complete style body while strip focus is
    // parked on B may discard the stored tag or restore an obsolete action.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC005", "Root"),
      size: .init(width: 60, height: 11)
    ) {
      StressTC005Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressTC005Fixture.tabsIdentity)
    _ = try harness.pressKey(KeyPress(.arrowRight))
    _ = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))
    let frame = try harness.pressKey(KeyPress(.return))

    #expect(frame.contains("B content after style replacement"))
    #expect(!frame.contains("A content after style replacement"))
  }
}

@MainActor
private struct StressTC005Fixture: View {
  static let tabsIdentity = testIdentity("StressTC005", "Tabs")

  @State private var usesPowerline = false
  @State private var selection = "a"

  var body: some View {
    Panel(id: "stress-tc-005-panel") {
      TabView(selection: $selection) {
        Tab("A", value: "a") { Text("A content after style replacement") }
        Tab("B", value: "b") { Text("B content after style replacement") }
        Tab("C", value: "c") { Text("C content after style replacement") }
      }
      .tabViewStyle(usesPowerline ? .powerline : .literalTabs)
      .id(Self.tabsIdentity)
    }
    .keyCommand("Replace style", key: .character("s"), modifiers: .ctrl) {
      usesPowerline = true
    }
    .frame(width: 58, height: 9, alignment: .topLeading)
  }
}

// MARK: - Attempt 006: departed overflow surface state

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 006 departed overflow surface does not resurrect expanded")
  func stressTabCommand006DepartedOverflowDoesNotResurrectExpanded() throws {
    // Hypothesis: expansion lives in a private state slot and may survive a
    // style with no overflow surface, reopening when literal tabs return.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC006", "Root"),
      size: .init(width: 24, height: 10)
    ) {
      StressTC006Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressTC006Fixture.tabsIdentity)
    _ = try harness.pressKey(KeyPress(.arrowRight))
    _ = try harness.pressKey(KeyPress(.arrowRight))
    let expanded = try harness.pressKey(KeyPress(.return))
    #expect(expanded.contains("Three"))
    #expect(expanded.contains("Four"))

    _ = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))
    let restored = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))

    #expect(!restored.contains("Three"))
    #expect(!restored.contains("Four"))
    #expect(restored.contains("One content"))
  }
}

@MainActor
private struct StressTC006Fixture: View {
  static let tabsIdentity = testIdentity("StressTC006", "Tabs")

  @State private var usesLiteral = true
  @State private var selection = "one"

  var body: some View {
    Panel(id: "stress-tc-006-panel") {
      TabView(selection: $selection) {
        Tab("One", value: "one") { Text("One content") }
        Tab("Two", value: "two") { Text("Two content") }
        Tab("Three", value: "three") { Text("Three content") }
        Tab("Four", value: "four") { Text("Four content") }
      }
      .tabViewStyle(usesLiteral ? .literalTabs : .underline)
      .id(Self.tabsIdentity)
    }
    .keyCommand("Toggle style", key: .character("s"), modifiers: .ctrl) {
      usesLiteral.toggle()
    }
    .frame(width: 24, height: 10, alignment: .topLeading)
  }
}

// MARK: - Attempt 007: expanded overflow reorder

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 007 expanded overflow routes follow hidden reorder")
  func stressTabCommand007ExpandedOverflowRoutesFollowHiddenReorder() throws {
    // Hypothesis: expanded-menu pointer routes may retain their pre-reorder
    // option closures while the menu labels redraw in the new hidden order.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC007", "Root"),
      size: .init(width: 24, height: 11)
    ) {
      StressTC007Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("▾")
    _ = try harness.pressKey(KeyPress(.character("r"), modifiers: .ctrl))
    let frame = try harness.clickText("Four")

    withKnownIssue("Reordered overflow label Four remains bound to the old Three route") {
      #expect(frame.contains("Four active content"))
      #expect(!frame.contains("Three active content"))
    }
  }
}

@MainActor
private struct StressTC007Fixture: View {
  @State private var reversed = false
  @State private var selection = "one"

  var body: some View {
    Panel(id: "stress-tc-007-panel") {
      TabView(selection: $selection) {
        Tab("One", value: "one") { Text("One active content") }
        Tab("Two", value: "two") { Text("Two active content") }
        if reversed {
          Tab("Four", value: "four") { Text("Four active content") }
          Tab("Three", value: "three") { Text("Three active content") }
        } else {
          Tab("Three", value: "three") { Text("Three active content") }
          Tab("Four", value: "four") { Text("Four active content") }
        }
      }
      .tabViewStyle(.literalTabs)
      .id(testIdentity("StressTC007", "Tabs"))
    }
    .keyCommand("Reverse hidden tabs", key: .character("r"), modifiers: .ctrl) {
      reversed = true
    }
    .frame(width: 24, height: 11, alignment: .topLeading)
  }
}

// MARK: - Attempt 008: selected-tab departure fallback

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 008 selected tab departure resolves the first live payload")
  func stressTabCommand008SelectedTabDepartureResolvesFirstLivePayload() throws {
    // Hypothesis: when the selected tag disappears, lazy payload indexing may
    // keep the departed content or choose the first declaration before filtering.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC008", "Root"),
      size: .init(width: 58, height: 10)
    ) {
      StressTC008Fixture()
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("B live payload"))
    let frame = try harness.pressKey(KeyPress(.character("x"), modifiers: .ctrl))

    #expect(frame.contains("includes B false"))
    withKnownIssue("A departed selected tab keeps its stale declaration and active payload") {
      #expect(frame.contains("A live payload"))
      #expect(!frame.contains("B live payload"))
    }
    #expect(!frame.contains("C live payload"))
  }
}

@MainActor
private struct StressTC008Fixture: View {
  @State private var includesB = true
  @State private var selection = "b"

  var body: some View {
    Panel(id: "stress-tc-008-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Text("includes B \(includesB)")
        TabView(selection: $selection) {
          Tab("A", value: "a") { Text("A live payload") }
          if includesB {
            Tab("B", value: "b") { Text("B live payload") }
          }
          Tab("C", value: "c") { Text("C live payload") }
        }
        .id(testIdentity("StressTC008", "Tabs"))
      }
    }
    .keyCommand("Remove selected", key: .character("x"), modifiers: .ctrl) {
      includesB = false
    }
    .frame(width: 56, height: 8, alignment: .topLeading)
  }
}

// MARK: - Attempt 009: toolbar placement and action replacement

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 009 toolbar placement swap refreshes its action")
  func stressTabCommand009ToolbarPlacementSwapRefreshesAction() throws {
    // Hypothesis: late host reconciliation may move cached chrome but retain
    // the action authored for the previous placement generation.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC009", "Root"),
      size: .init(width: 58, height: 10)
    ) {
      StressTC009Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Move toolbar")
    let bodyPoint = try #require(harness.point(forText: "Body anchor"))
    let toolPoint = try #require(harness.point(forText: "Bottom tool"))
    #expect(bodyPoint.y < toolPoint.y)

    _ = try harness.clickText("Bottom tool")
    #expect(probe.events == ["bottom"])
  }
}

private struct StressTC009ToolbarStyle: ToolbarStyle {
  let placement: ToolbarPlacement

  var itemLayout: HStackLayout {
    HStackLayout(alignment: .center, spacing: 1)
  }
}

@MainActor
private struct StressTC009Fixture: View {
  let probe: TabCommandStressProbe
  @State private var atBottom = false

  var body: some View {
    Panel(id: "stress-tc-009-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Text("Body anchor")
        Button("Move toolbar") {
          atBottom = true
        }
        .toolbarItem(
          .init(title: atBottom ? "Bottom tool" : "Top tool") {
            probe.events.append(atBottom ? "bottom" : "top")
          }
        )
      }
    }
    .toolbar(style: StressTC009ToolbarStyle(placement: atBottom ? .bottom : .top))
    .frame(width: 56, height: 8, alignment: .topLeading)
  }
}

// MARK: - Attempt 010: inserted toolbar prefix ownership

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 010 inserted toolbar prefix retargets trailing actions")
  func stressTabCommand010InsertedToolbarPrefixRetargetsTrailingActions() throws {
    // Hypothesis: cached toolbar buttons are refreshed by ordinal and may keep
    // C's visual title paired with B's action after a new first contribution.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC010", "Root"),
      size: .init(width: 64, height: 10)
    ) {
      StressTC010Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Insert first tool")
    _ = try harness.clickText("C tool")

    #expect(probe.events == ["c"])
  }
}

@MainActor
private struct StressTC010Fixture: View {
  let probe: TabCommandStressProbe
  @State private var hasPrefix = false

  var body: some View {
    Panel(id: "stress-tc-010-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Insert first tool") {
          hasPrefix = true
        }
        if hasPrefix {
          source("Prefix", marker: "prefix")
        }
        source("B", marker: "b")
        source("C", marker: "c")
      }
    }
    .toolbar(style: DefaultTopToolbarStyle())
    .frame(width: 62, height: 8, alignment: .topLeading)
  }

  private func source(_ name: String, marker: String) -> some View {
    Text("\(name) source")
      .toolbarItem(
        .init(title: "\(name) tool") {
          probe.events.append(marker)
        }
      )
  }
}
