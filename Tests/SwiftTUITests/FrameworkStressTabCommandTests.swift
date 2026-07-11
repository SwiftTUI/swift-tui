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

// MARK: - Attempt 011: removed toolbar prefix ownership

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 011 removed toolbar prefix retargets trailing actions")
  func stressTabCommand011RemovedToolbarPrefixRetargetsTrailingActions() throws {
    // Hypothesis: removing the first preference contribution may leave C's
    // surviving button identity bound to its former ordinal's B action.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC011", "Root"),
      size: .init(width: 64, height: 10)
    ) {
      StressTC011Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Remove first tool")
    _ = try harness.clickText("C tool")

    #expect(probe.events == ["c"])
    #expect(!harness.frame.contains("Prefix tool"))
  }
}

@MainActor
private struct StressTC011Fixture: View {
  let probe: TabCommandStressProbe
  @State private var hasPrefix = true

  var body: some View {
    Panel(id: "stress-tc-011-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Remove first tool") {
          hasPrefix = false
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

// MARK: - Attempt 012: toolbar contribution migrates to ancestor

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 012 removed inner toolbar migrates its item exactly once")
  func stressTabCommand012RemovedInnerToolbarMigratesItemExactlyOnce() throws {
    // Hypothesis: nested late-preference hosts may leave the inner strip alive
    // while also allowing its contribution to bubble into the outer strip.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC012", "Root"),
      size: .init(width: 72, height: 13)
    ) {
      StressTC012Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    let frame = try harness.clickText("Remove inner host")
    let firstTitle = try #require(frame.firstRange(of: "Migrating tool"))
    #expect(!frame[firstTitle.upperBound...].contains("Migrating tool"))

    _ = try harness.clickText("Migrating tool")
    #expect(probe.events == ["migrated"])
  }
}

@MainActor
private struct StressTC012Fixture: View {
  let probe: TabCommandStressProbe
  @State private var innerHosted = true

  var body: some View {
    Panel(id: "stress-tc-012-outer") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Remove inner host") {
          innerHosted = false
        }
        innerPanel
        Text("Outer source")
          .toolbarItem(.init(title: "Outer tool") {})
      }
    }
    .toolbar(style: DefaultTopToolbarStyle())
    .frame(width: 70, height: 11, alignment: .topLeading)
  }

  @ViewBuilder
  private var innerPanel: some View {
    if innerHosted {
      Panel(id: "stress-tc-012-inner") {
        migratingSource
      }
      .toolbar(style: DefaultBottomToolbarStyle())
    } else {
      Panel(id: "stress-tc-012-inner") {
        migratingSource
      }
    }
  }

  private var migratingSource: some View {
    Text("Inner source")
      .toolbarItem(
        .init(title: "Migrating tool") {
          probe.events.append("migrated")
        }
      )
  }
}

// MARK: - Attempt 013: toolbar contribution retracts into descendant

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 013 added inner toolbar retracts its item exactly once")
  func stressTabCommand013AddedInnerToolbarRetractsItemExactlyOnce() throws {
    // Hypothesis: installing a nearer late-preference consumer may render the
    // new inner strip without removing the old contribution from the ancestor.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC013", "Root"),
      size: .init(width: 72, height: 13)
    ) {
      StressTC013Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    let frame = try harness.clickText("Add inner host")
    let firstTitle = try #require(frame.firstRange(of: "Retracting tool"))
    #expect(!frame[firstTitle.upperBound...].contains("Retracting tool"))

    _ = try harness.clickText("Retracting tool")
    #expect(probe.events == ["retracted"])
  }
}

@MainActor
private struct StressTC013Fixture: View {
  let probe: TabCommandStressProbe
  @State private var innerHosted = false

  var body: some View {
    Panel(id: "stress-tc-013-outer") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Add inner host") {
          innerHosted = true
        }
        innerPanel
        Text("Outer source")
          .toolbarItem(.init(title: "Outer tool") {})
      }
    }
    .toolbar(style: DefaultTopToolbarStyle())
    .frame(width: 70, height: 11, alignment: .topLeading)
  }

  @ViewBuilder
  private var innerPanel: some View {
    if innerHosted {
      Panel(id: "stress-tc-013-inner") {
        retractingSource
      }
      .toolbar(style: DefaultBottomToolbarStyle())
    } else {
      Panel(id: "stress-tc-013-inner") {
        retractingSource
      }
    }
  }

  private var retractingSource: some View {
    Text("Inner source")
      .toolbarItem(
        .init(title: "Retracting tool") {
          probe.events.append("retracted")
        }
      )
  }
}

// MARK: - Attempt 014: layout-realized toolbar replacement

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 014 geometry toolbar adopts the latest proposal action")
  func stressTabCommand014GeometryToolbarAdoptsLatestProposalAction() throws {
    // Hypothesis: a layout-realized contribution may repaint its new measured
    // title while the cached strip retains the action captured at the old width.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC014", "Root"),
      size: .init(width: 72, height: 11)
    ) {
      StressTC014Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    let frame = try harness.clickText("Grow host")
    #expect(frame.contains("Width 50"))
    #expect(!frame.contains("Width 30"))

    _ = try harness.clickText("Width 50")
    #expect(probe.events == ["50"])
  }
}

@MainActor
private struct StressTC014Fixture: View {
  let probe: TabCommandStressProbe
  @State private var wide = false

  var body: some View {
    Panel(id: "stress-tc-014-panel") {
      GeometryReader { proxy in
        Button("Grow host") {
          wide = true
        }
        .toolbarItem(
          .init(title: "Width \(proxy.size.width)") {
            probe.events.append("\(proxy.size.width)")
          }
        )
      }
    }
    .toolbar(style: DefaultTopToolbarStyle())
    .frame(width: wide ? 50 : 30, height: 8, alignment: .topLeading)
  }
}

// MARK: - Attempt 015: toolbar signature cycle action freshness

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 015 reenabled toolbar cache uses replacement action")
  func stressTabCommand015ReenabledToolbarCacheUsesReplacementAction() throws {
    // Hypothesis: cycling enabled -> disabled -> enabled revisits the first
    // strip signature and may restore its generation-zero action from cache.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC015", "Root"),
      size: .init(width: 66, height: 10)
    ) {
      StressTC015Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Disable tool")
    _ = try harness.clickText("Enable replacement")
    _ = try harness.clickText("Mutable tool")

    #expect(probe.events == ["generation-2"])
  }
}

@MainActor
private struct StressTC015Fixture: View {
  let probe: TabCommandStressProbe
  @State private var enabled = true
  @State private var generation = 0

  var body: some View {
    Panel(id: "stress-tc-015-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Disable tool") {
          generation = 1
          enabled = false
        }
        Button("Enable replacement") {
          generation = 2
          enabled = true
        }
        Text("generation \(generation)")
          .toolbarItem(
            .init(title: "Mutable tool", isEnabled: enabled) {
              probe.events.append("generation-\(generation)")
            }
          )
      }
    }
    .toolbar(style: DefaultTopToolbarStyle())
    .frame(width: 64, height: 8, alignment: .topLeading)
  }
}

// MARK: - Attempt 016: open-palette command insertion

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 016 open palette inserts commands without retargeting survivors")
  func stressTabCommand016OpenPaletteInsertsCommandsWithoutRetargetingSurvivors() throws {
    // Hypothesis: inserting a command ahead of an open sheet's captured list
    // may redraw C at a new ordinal while keeping the prior button action.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC016", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressTC016Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open insert palette")
    _ = try harness.clickText("Insert palette prefix")
    _ = try harness.clickText("C palette command")

    #expect(probe.events == ["c"])
  }
}

@MainActor
private struct StressTC016Fixture: View {
  let probe: TabCommandStressProbe
  @State private var hasPrefix = false
  @State private var showsPalette = false

  var body: some View {
    Panel(id: "stress-tc-016-source") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Open insert palette") {
          showsPalette = true
        }
        if hasPrefix {
          commandSource("Prefix palette command", marker: "prefix")
        }
        commandSource("B palette command", marker: "b")
        commandSource("C palette command", marker: "c")
      }
    }
    .panel(id: "stress-tc-016-host")
    .paletteSheet("Insert palette", isPresented: $showsPalette) { commands in
      VStack(alignment: .leading, spacing: 0) {
        Button("Insert palette prefix") {
          hasPrefix = true
        }
        ForEach(Array(commands.enumerated()), id: \.offset) { entry in
          Button(entry.element.name) {
            entry.element.action()
          }
          .disabled(!entry.element.isEnabled)
        }
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }

  private func commandSource(_ name: String, marker: String) -> some View {
    Panel(id: "source-\(marker)") { Text("source \(marker)") }
      .paletteCommand(name: name) {
        probe.events.append(marker)
      }
  }
}

// MARK: - Attempt 017: open-palette command removal

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 017 open palette removes departed command and action")
  func stressTabCommand017OpenPaletteRemovesDepartedCommandAndAction() throws {
    // Hypothesis: an open palette may keep a departed command in its absorbed
    // snapshot or shift the next command onto the departed action closure.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC017", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressTC017Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open removal palette")
    let frame = try harness.clickText("Remove B command")
    #expect(!frame.contains("B removable command"))

    _ = try harness.clickText("C surviving command")
    #expect(probe.events == ["c"])
  }
}

@MainActor
private struct StressTC017Fixture: View {
  let probe: TabCommandStressProbe
  @State private var includesB = true
  @State private var showsPalette = false

  var body: some View {
    Panel(id: "stress-tc-017-source") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Open removal palette") {
          showsPalette = true
        }
        if includesB {
          commandSource("B removable command", marker: "b")
        }
        commandSource("C surviving command", marker: "c")
      }
    }
    .panel(id: "stress-tc-017-host")
    .paletteSheet("Removal palette", isPresented: $showsPalette) { commands in
      VStack(alignment: .leading, spacing: 0) {
        Button("Remove B command") {
          includesB = false
        }
        ForEach(Array(commands.enumerated()), id: \.offset) { entry in
          Button(entry.element.name) {
            entry.element.action()
          }
          .disabled(!entry.element.isEnabled)
        }
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }

  private func commandSource(_ name: String, marker: String) -> some View {
    Panel(id: "source-\(marker)") { Text("source \(marker)") }
      .paletteCommand(name: name) {
        probe.events.append(marker)
      }
  }
}

// MARK: - Attempt 018: duplicate-name palette reorder

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 018 duplicate palette names follow current owners")
  func stressTabCommand018DuplicatePaletteNamesFollowCurrentOwners() throws {
    // Hypothesis: identical command metadata may allow an open sheet to reuse
    // the first row while preserving the action from its previous source owner.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC018", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressTC018Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open duplicate palette")
    _ = try harness.clickText("Reverse palette owners")
    _ = try harness.clickText("Duplicate palette action")

    #expect(probe.events == ["b"])
  }
}

@MainActor
private struct StressTC018Fixture: View {
  let probe: TabCommandStressProbe
  @State private var reversed = false
  @State private var showsPalette = false

  var body: some View {
    Panel(id: "stress-tc-018-source") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Open duplicate palette") {
          showsPalette = true
        }
        if reversed {
          commandSource(owner: "B", marker: "b")
          commandSource(owner: "A", marker: "a")
        } else {
          commandSource(owner: "A", marker: "a")
          commandSource(owner: "B", marker: "b")
        }
      }
    }
    .panel(id: "stress-tc-018-host")
    .paletteSheet("Duplicate palette", isPresented: $showsPalette) { commands in
      VStack(alignment: .leading, spacing: 0) {
        Button("Reverse palette owners") {
          reversed = true
        }
        ForEach(Array(commands.enumerated()), id: \.offset) { entry in
          Button(entry.element.name) {
            entry.element.action()
          }
        }
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }

  private func commandSource(owner: String, marker: String) -> some View {
    Panel(id: "palette-owner-\(marker)") { Text("owner \(owner)") }
      .paletteCommand(name: "Duplicate palette action") {
        probe.events.append(marker)
      }
  }
}

// MARK: - Attempt 019: palette enablement replacement

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 019 reenabled palette row uses replacement action")
  func stressTabCommand019ReenabledPaletteRowUsesReplacementAction() throws {
    // Hypothesis: an open sheet may update a command's enabled chrome but keep
    // the disabled generation's action payload when the row is reenabled.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC019", "Root"),
      size: .init(width: 72, height: 15)
    ) {
      StressTC019Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open enablement palette")
    _ = try harness.clickText("Enable palette command")
    _ = try harness.clickText("Mutable palette action")

    withKnownIssue("Reenabled palette row dispatches the disabled generation-zero action") {
      #expect(probe.events == ["generation-1"])
    }
  }
}

@MainActor
private struct StressTC019Fixture: View {
  let probe: TabCommandStressProbe
  @State private var enabled = false
  @State private var generation = 0
  @State private var showsPalette = false

  var body: some View {
    Panel(id: "stress-tc-019-source") {
      Button("Open enablement palette") {
        showsPalette = true
      }
    }
    .paletteCommand(name: "Mutable palette action", isEnabled: enabled) {
      probe.events.append("generation-\(generation)")
    }
    .panel(id: "stress-tc-019-host")
    .paletteSheet("Enablement palette", isPresented: $showsPalette) { commands in
      VStack(alignment: .leading, spacing: 0) {
        Button("Enable palette command") {
          generation = 1
          enabled = true
        }
        ForEach(Array(commands.enumerated()), id: \.offset) { entry in
          Button(entry.element.name) {
            entry.element.action()
          }
          .disabled(!entry.element.isEnabled)
        }
      }
    }
    .frame(width: 70, height: 13, alignment: .topLeading)
  }
}

// MARK: - Attempt 020: palette source-scope replacement

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 020 open palette follows replacement source scope")
  func stressTabCommand020OpenPaletteFollowsReplacementSourceScope() throws {
    // Hypothesis: replacing the contributing Panel identity under an open
    // palette may leave the stable command row bound to the departed graph scope.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC020", "Root"),
      size: .init(width: 72, height: 15)
    ) {
      StressTC020Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open scoped palette")
    _ = try harness.clickText("Replace palette scope")
    _ = try harness.clickText("Scoped palette action")

    #expect(probe.events == ["scope-1"])
  }
}

@MainActor
private struct StressTC020Fixture: View {
  let probe: TabCommandStressProbe
  @State private var generation = 0
  @State private var showsPalette = false

  var body: some View {
    Panel(id: "stress-tc-020-source-\(generation)") {
      Button("Open scoped palette") {
        showsPalette = true
      }
    }
    .paletteCommand(name: "Scoped palette action") {
      probe.events.append("scope-\(generation)")
    }
    .panel(id: "stress-tc-020-host")
    .paletteSheet("Scoped palette", isPresented: $showsPalette) { commands in
      VStack(alignment: .leading, spacing: 0) {
        Button("Replace palette scope") {
          generation += 1
        }
        ForEach(Array(commands.enumerated()), id: \.offset) { entry in
          Button(entry.element.name) {
            entry.element.action()
          }
        }
      }
    }
    .frame(width: 70, height: 13, alignment: .topLeading)
  }
}

// MARK: - Attempt 021: key binding replacement

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 021 key binding replacement removes the old chord")
  func stressTabCommand021KeyBindingReplacementRemovesOldChord() throws {
    // Hypothesis: command-table restoration may add the replacement binding
    // without pruning the old chord registered at the same stable scope.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC021", "Root"),
      size: .init(width: 58, height: 10)
    ) {
      StressTC021Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Replace key chord")
    _ = try harness.pressKey(KeyPress(.character("a"), modifiers: .ctrl))
    _ = try harness.pressKey(KeyPress(.character("b"), modifiers: .ctrl))

    #expect(probe.events == ["b-1"])
    #expect(harness.keyCommandRegistrationCount == 1)
  }
}

@MainActor
private struct StressTC021Fixture: View {
  let probe: TabCommandStressProbe
  @State private var replacement = false

  var body: some View {
    Panel(id: "stress-tc-021-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Replace key chord") {
          replacement = true
        }
        Text("Command focus")
          .focusable()
      }
    }
    .keyCommand(
      "Mutable chord",
      key: .character(replacement ? "b" : "a"),
      modifiers: .ctrl
    ) {
      probe.events.append(replacement ? "b-1" : "a-0")
    }
    .frame(width: 56, height: 8, alignment: .topLeading)
  }
}

// MARK: - Attempt 022: key modifier replacement

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 022 modifier replacement removes the old binding tuple")
  func stressTabCommand022ModifierReplacementRemovesOldBindingTuple() throws {
    // Hypothesis: replacing only EventModifiers may leave both hash keys in the
    // command table even though the modifier is one field of the binding tuple.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC022", "Root"),
      size: .init(width: 58, height: 10)
    ) {
      StressTC022Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Replace modifiers")
    _ = try harness.pressKey(KeyPress(.character("k"), modifiers: .ctrl))
    _ = try harness.pressKey(KeyPress(.character("k"), modifiers: .alt))

    #expect(probe.events == ["alt-1"])
    #expect(harness.keyCommandRegistrationCount == 1)
  }
}

@MainActor
private struct StressTC022Fixture: View {
  let probe: TabCommandStressProbe
  @State private var usesAlt = false

  var body: some View {
    Panel(id: "stress-tc-022-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Replace modifiers") {
          usesAlt = true
        }
        Text("Modifier focus")
          .focusable()
      }
    }
    .keyCommand(
      "Mutable modifiers",
      key: .character("k"),
      modifiers: usesAlt ? .alt : .ctrl
    ) {
      probe.events.append(usesAlt ? "alt-1" : "ctrl-0")
    }
    .frame(width: 56, height: 8, alignment: .topLeading)
  }
}

// MARK: - Attempt 023: sibling command-scope reorder

extension FrameworkStressTabCommandTests {
  @Test("stress tab command 023 sibling panel reorder preserves focused command owner")
  func stressTabCommand023SiblingPanelReorderPreservesFocusedCommandOwner() throws {
    // Hypothesis: scope-path publication may follow sibling ordinal after a
    // reorder, routing the right leaf through the left Panel's same-key command.
    let probe = TabCommandStressProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressTC023", "Root"),
      size: .init(width: 66, height: 12)
    ) {
      StressTC023Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Left command focus")
    _ = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))
    _ = try harness.clickText("Reverse command panels")
    _ = try harness.focusText("Right command focus")
    _ = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))

    #expect(probe.events == ["left", "right"])
    #expect(harness.keyCommandRegistrationCount == 2)
  }
}

@MainActor
private struct StressTC023Fixture: View {
  let probe: TabCommandStressProbe
  @State private var reversed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse command panels") {
        reversed = true
      }
      if reversed {
        commandPanel("Right", marker: "right")
        commandPanel("Left", marker: "left")
      } else {
        commandPanel("Left", marker: "left")
        commandPanel("Right", marker: "right")
      }
    }
    .frame(width: 64, height: 10, alignment: .topLeading)
  }

  private func commandPanel(_ label: String, marker: String) -> some View {
    Panel(id: "stress-tc-023-\(marker)") {
      Text("\(label) command focus")
        .focusable()
    }
    .keyCommand("Save \(label)", key: .character("s"), modifiers: .ctrl) {
      probe.events.append(marker)
    }
  }
}
