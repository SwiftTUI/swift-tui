import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI presentation and semantics stress behavior", .serialized)
struct FrameworkStressPresentationSemanticsTests {}

@MainActor
private final class StressPresentationProbe {
  var markers: [String] = []
  var firstBool = false
  var secondBool = false
  var firstInt = 0
  var secondInt = 0
  var selection = "b"

  func firstBoolBinding() -> Binding<Bool> {
    Binding(get: { self.firstBool }, set: { self.firstBool = $0 })
  }

  func secondBoolBinding() -> Binding<Bool> {
    Binding(get: { self.secondBool }, set: { self.secondBool = $0 })
  }

  func firstIntBinding() -> Binding<Int> {
    Binding(get: { self.firstInt }, set: { self.firstInt = $0 })
  }

  func secondIntBinding() -> Binding<Int> {
    Binding(get: { self.secondInt }, set: { self.secondInt = $0 })
  }

  func selectionBinding() -> Binding<String> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }
}

@MainActor
private func stressPresentationEntryCount<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> Int {
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .count
}

@MainActor
private func stressAccessibilityNodes<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> [AccessibilityNode] {
  harness.runLoop.latestSemanticSnapshot.accessibilityNodes
}

// MARK: - Attempt 001: retained overlay host one-to-two transition

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 001 opening a sheet appends to an open menu overlay")
  func stress001OpeningSheetAppendsToOpenMenuOverlay() throws {
    // Hypothesis: retained overlay-host reuse may serve the committed one-entry
    // child list when opening a second menu only invalidates its trigger source.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS001", "Root"),
      size: .init(width: 72, height: 18)
    ) {
      StressPS001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Actions")
    let frame = try harness.clickText("Open sheet from menu")

    #expect(frame.contains("Sheet overlay body"))
    #expect(stressPresentationEntryCount(in: harness) == 2)
  }
}

// MARK: - Attempt 003: open menu source removal

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 003 removing an open menu source prunes its portal entry")
  func stress003RemovingOpenMenuSourcePrunesPortalEntry() throws {
    // Hypothesis: declarative presentation synchronization may preserve the
    // last active menu after its source identity leaves the resolved tree.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS003", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressPS003Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Transient menu")
    let frame = try harness.clickText("Remove menu source")

    #expect(!frame.contains("Transient overlay item"))
    #expect(stressPresentationEntryCount(in: harness) == 0)
  }
}

@MainActor
private struct StressPS003Fixture: View {
  @State private var showsMenu = true

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      if showsMenu {
        Menu("Transient menu") {
          Button("Transient overlay item") {}
        }
      } else {
        Text("Menu source absent")
      }
      Spacer().frame(width: 28)
      Button("Remove menu source") {
        showsMenu = false
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }
}

// MARK: - Attempt 004: menu source reinsertion

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 004 a reinserted menu source starts collapsed")
  func stress004ReinsertedMenuSourceStartsCollapsed() throws {
    // Hypothesis: a removed menu's State slot or presentation declaration may
    // be resurrected when the same structural source is inserted again.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS004", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressPS004Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Reinsertable menu")
    _ = try harness.clickText("Toggle menu source")
    let frame = try harness.clickText("Toggle menu source")

    #expect(frame.contains("Reinsertable menu"))
    #expect(!frame.contains("Reinserted overlay item"))
    #expect(stressPresentationEntryCount(in: harness) == 0)
  }
}

@MainActor
private struct StressPS004Fixture: View {
  @State private var showsMenu = true

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      if showsMenu {
        Menu("Reinsertable menu") {
          Button("Reinserted overlay item") {}
        }
      } else {
        Text("Menu source absent")
      }
      Spacer().frame(width: 25)
      Button("Toggle menu source") {
        showsMenu.toggle()
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }
}

// MARK: - Attempt 005: live menu payload refresh

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 005 an open menu renders its current payload")
  func stress005OpenMenuRendersCurrentPayload() throws {
    // Hypothesis: an active menu item may retain the content payload captured
    // when its portal entry first became active.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS005", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressPS005Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Payload menu")
    let frame = try harness.clickText("Advance payload")

    withKnownIssue("An open menu retains the payload captured when it was activated") {
      #expect(frame.contains("Payload generation 1"))
      #expect(!frame.contains("Payload generation 0"))
    }
    #expect(stressPresentationEntryCount(in: harness) == 1)
  }
}

@MainActor
private struct StressPS005Fixture: View {
  @State private var generation = 0

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Menu("Payload menu") {
        Text("Payload generation \(generation)")
      }
      Spacer().frame(width: 31)
      Button("Advance payload") {
        generation += 1
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }
}

// MARK: - Attempt 006: live menu action refresh

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 006 an open menu dispatches its current action closure")
  func stress006OpenMenuDispatchesCurrentActionClosure() throws {
    // Hypothesis: refreshing an open menu's rendered payload may leave its
    // action registration bound to the activation frame's closure.
    let probe = StressPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS006", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressPS006Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Action menu")
    _ = try harness.clickText("Advance action")
    _ = try harness.clickText("Run generation 0")

    #expect(probe.markers == ["generation-1"])
  }
}

@MainActor
private struct StressPS006Fixture: View {
  let probe: StressPresentationProbe
  @State private var generation = 0

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Menu("Action menu") {
        Button("Run generation \(generation)") {
          probe.markers.append("generation-\(generation)")
        }
      }
      Spacer().frame(width: 31)
      Button("Advance action") {
        generation += 1
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }
}

// MARK: - Attempt 007: open menu cardinality churn

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 007 menu cardinality churn preserves its stable item")
  func stress007MenuCardinalityChurnPreservesStableItem() throws {
    // Hypothesis: one-to-many overlay payload reconciliation may drop or stale
    // the stable first menu item when additional siblings arrive.
    let probe = StressPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS007", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressPS007Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Cardinality menu")
    let frame = try harness.clickText("Add menu items")
    _ = try harness.clickText("Stable item 0")

    withKnownIssue("An open menu retains its one-item activation payload and action") {
      #expect(frame.contains("Extra item A"))
      #expect(frame.contains("Extra item B"))
      #expect(probe.markers == ["stable-1"])
    }
  }
}

@MainActor
private struct StressPS007Fixture: View {
  let probe: StressPresentationProbe
  @State private var expandedPayload = false

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Menu("Cardinality menu") {
        Button("Stable item \(expandedPayload ? 1 : 0)") {
          probe.markers.append("stable-\(expandedPayload ? 1 : 0)")
        }
        if expandedPayload {
          Button("Extra item A") {}
          Button("Extra item B") {}
        }
      }
      Spacer().frame(width: 27)
      Button("Add menu items") {
        expandedPayload = true
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }
}

// MARK: - Attempt 008: disabling an active menu

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 008 disabling an open menu disables its overlay actions")
  func stress008DisablingOpenMenuDisablesOverlayActions() throws {
    // Hypothesis: portal content may retain the opening environment and keep
    // its buttons actionable after the source menu becomes disabled.
    let probe = StressPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS008", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressPS008Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Disable-aware menu")
    _ = try harness.clickText("Disable menu")
    _ = try harness.clickText("Disabled overlay action")

    withKnownIssue("Open menu content retains the enabled environment from activation") {
      #expect(probe.markers.isEmpty)
    }
  }
}

@MainActor
private struct StressPS008Fixture: View {
  let probe: StressPresentationProbe
  @State private var isDisabled = false

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Menu("Disable-aware menu") {
        Button("Disabled overlay action") {
          probe.markers.append("fired")
        }
      }
      .disabled(isDisabled)
      Spacer().frame(width: 24)
      Button("Disable menu") {
        isDisabled = true
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }
}

// MARK: - Attempt 009: open menu explicit-identity replacement

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 009 replacing an open menu identity drops its old entry")
  func stress009ReplacingOpenMenuIdentityDropsOldEntry() throws {
    // Hypothesis: the coordinator may merge the new declaration with the old
    // active item even though the menu's explicit identity lifetime changed.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS009", "Root"),
      size: .init(width: 72, height: 16)
    ) {
      StressPS009Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Identity menu 0")
    let frame = try harness.clickText("Remint menu")

    #expect(frame.contains("Identity menu 1"))
    #expect(!frame.contains("Old identity overlay"))
    #expect(stressPresentationEntryCount(in: harness) == 0)
  }
}

@MainActor
private struct StressPS009Fixture: View {
  @State private var generation = 0

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Menu("Identity menu \(generation)") {
        Button("Old identity overlay") {}
      }
      .id(generation)
      Spacer().frame(width: 28)
      Button("Remint menu") {
        generation += 1
      }
    }
    .frame(width: 70, height: 14, alignment: .topLeading)
  }
}

// MARK: - Attempt 010: mixed-family dismiss stack ordering

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 010 Escape unwinds sheet popover and menu newest first")
  func stress010EscapeUnwindsMixedPresentationsNewestFirst() throws {
    // Hypothesis: composing three independently coordinated presentation
    // families may leave the committed dismiss stack in family order instead
    // of activation order after each two-to-one transition.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS010", "Root"),
      size: .init(width: 72, height: 18)
    ) {
      StressPS010Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Layer menu")
    _ = try harness.clickText("Open popover layer")
    _ = try harness.clickText("Open sheet layer")
    #expect(stressPresentationEntryCount(in: harness) == 3)

    _ = try harness.pressKey(KeyPress(.escape))
    #expect(stressPresentationEntryCount(in: harness) == 2)
    withKnownIssue("A three-to-two overlay transition leaves the dismissed sheet visible") {
      #expect(!harness.frame.contains("Sheet layer body"))
    }

    _ = try harness.pressKey(KeyPress(.escape))
    #expect(stressPresentationEntryCount(in: harness) == 1)
    #expect(!harness.frame.contains("Open sheet layer"))

    _ = try harness.pressKey(KeyPress(.escape))
    #expect(stressPresentationEntryCount(in: harness) == 0)
    #expect(!harness.frame.contains("Open popover layer"))
  }
}

@MainActor
private struct StressPS010Fixture: View {
  @State private var showsPopover = false
  @State private var showsSheet = false

  var body: some View {
    Menu("Layer menu") {
      Button("Open popover layer") {
        showsPopover = true
      }
    }
    .popover(isPresented: $showsPopover) {
      Button("Open sheet layer") {
        showsSheet = true
      }
    }
    .sheet("Layer sheet", isPresented: $showsSheet) {
      Text("Sheet layer body")
    }
    .frame(width: 70, height: 16, alignment: .topLeading)
  }
}

// MARK: - Attempt 011: segmented picker entity reorder

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 011 a reordered picker follows the selected tag")
  func stress011ReorderedPickerFollowsSelectedTag() throws {
    // Hypothesis: a stable Picker may retain its first tag-to-index table when
    // option entities reorder without changing cardinality.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS011", "Root"),
      size: .init(width: 50, height: 10)
    ) {
      StressPS011Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Reverse options")
    _ = try harness.focusText("Mode")
    let frame = try harness.pressKey(KeyPress(.arrowRight))

    #expect(frame.contains("Selection a"))
  }
}

@MainActor
private struct StressPS011Fixture: View {
  @State private var reversed = false
  @State private var selection = "b"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse options") {
        reversed.toggle()
      }
      Picker("Mode", selection: $selection) {
        ForEach(reversed ? ["c", "b", "a"] : ["a", "b", "c"], id: \.self) { option in
          Text(option.uppercased()).tag(option)
        }
      }
      .pickerStyle(.segmented)
      Text("Selection \(selection)")
    }
  }
}

// MARK: - Attempt 012: active menu picker payload refresh

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 012 a focused menu picker refreshes every option label")
  func stress012FocusedMenuPickerRefreshesOptionLabels() throws {
    // Hypothesis: the active-navigation branch may retain its initially
    // collected labels while the stable Picker's authored payload changes.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS012", "Root"),
      size: .init(width: 50, height: 12)
    ) {
      StressPS012Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Alpha 0")
    let frame = try harness.pressKey(KeyPress(.arrowDown))

    #expect(frame.contains("Alpha 1"))
    #expect(frame.contains("Beta 1"))
    #expect(!frame.contains("Beta 0"))
  }
}

@MainActor
private struct StressPS012Fixture: View {
  @State private var generation = 0
  @State private var selection = "a"

  var body: some View {
    Picker(
      "Mode",
      selection: Binding(
        get: { selection },
        set: {
          selection = $0
          generation += 1
        }
      )
    ) {
      Text("Alpha \(generation)").tag("a")
      Text("Beta \(generation)").tag("b")
    }
    .pickerStyle(.menu)
  }
}

@MainActor
private struct StressPS001Fixture: View {
  @State private var showsSheet = false

  var body: some View {
    Menu("Actions") {
      Button("Open sheet from menu") {
        showsSheet = true
      }
    }
    .sheet("Stress sheet", isPresented: $showsSheet) {
      Text("Sheet overlay body")
    }
    .frame(width: 70, height: 16, alignment: .topLeading)
  }
}

// MARK: - Attempt 002: retained overlay host two-to-one transition

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 002 dismissing a sheet preserves its underlying menu")
  func stress002DismissingSheetPreservesUnderlyingMenu() throws {
    // Hypothesis: after a two-entry commit, retained overlay-host reuse may
    // leave the dismissed sheet child present or discard the surviving menu.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS002", "Root"),
      size: .init(width: 72, height: 18)
    ) {
      StressPS001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Actions")
    _ = try harness.clickText("Open sheet from menu")
    let frame = try harness.pressKey(KeyPress(.escape))

    #expect(frame.contains("Open sheet from menu"))
    #expect(!frame.contains("Sheet overlay body"))
    #expect(stressPresentationEntryCount(in: harness) == 1)
  }
}
