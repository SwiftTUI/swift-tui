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
  var secondSelection = "a"

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

  func secondSelectionBinding() -> Binding<String> {
    Binding(get: { self.secondSelection }, set: { self.secondSelection = $0 })
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

// MARK: - Attempt 013: picker binding retarget

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 013 a stable picker writes only its current binding")
  func stress013StablePickerWritesCurrentBinding() throws {
    // Hypothesis: the retained Picker key-handler registration may keep the
    // binding captured before the control was retargeted.
    let probe = StressPresentationProbe()
    probe.selection = "c"
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS013", "Root"),
      size: .init(width: 50, height: 10)
    ) {
      StressPS013Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Retarget picker")
    _ = try harness.focusText("Mode")
    _ = try harness.pressKey(KeyPress(.arrowRight))

    #expect(probe.selection == "c")
    #expect(probe.secondSelection == "b")
  }
}

@MainActor
private struct StressPS013Fixture: View {
  let probe: StressPresentationProbe
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget picker") {
        usesSecond = true
      }
      Picker(
        "Mode",
        selection: usesSecond ? probe.secondSelectionBinding() : probe.selectionBinding()
      ) {
        Text("A").tag("a")
        Text("B").tag("b")
        Text("C").tag("c")
      }
      .id("stable-picker")
      .pickerStyle(.segmented)
    }
  }
}

// MARK: - Attempt 014: selected picker tag removal

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 014 removing the selected tag clears the menu trigger")
  func stress014RemovingSelectedTagClearsMenuTrigger() throws {
    // Hypothesis: the Picker's collected-option cache may continue displaying
    // the departed selected label after its tag no longer exists.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS014", "Root"),
      size: .init(width: 42, height: 9)
    ) {
      StressPS014Fixture()
    }
    defer { harness.shutdown() }

    let frame = try harness.clickText("Remove selected tag")

    #expect(frame.contains("Select"))
    #expect(!frame.contains("Beta selected"))
  }
}

@MainActor
private struct StressPS014Fixture: View {
  @State private var includesSelected = true
  @State private var selection = "b"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove selected tag") {
        includesSelected = false
      }
      Picker("Mode", selection: $selection) {
        Text("Alpha option").tag("a")
        if includesSelected {
          Text("Beta selected").tag("b")
        }
      }
      .pickerStyle(.menu)
    }
  }
}

// MARK: - Attempt 015: duplicate picker labels

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 015 duplicate picker labels route by option occurrence")
  func stress015DuplicatePickerLabelsRouteByOccurrence() throws {
    // Hypothesis: pointer route IDs derived from a stable Picker may collapse
    // equal labels and dispatch both rows through the first tag.
    let probe = StressPresentationProbe()
    probe.selection = "a"
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS015", "Root"),
      size: .init(width: 42, height: 10)
    ) {
      StressPS015Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Duplicate option", chooseLast: true)

    #expect(probe.selection == "b")
  }
}

@MainActor
private struct StressPS015Fixture: View {
  let probe: StressPresentationProbe

  var body: some View {
    Picker("Duplicate mode", selection: probe.selectionBinding()) {
      Text("Duplicate option").tag("a")
      Text("Duplicate option").tag("b")
    }
    .pickerStyle(.radioGroup)
  }
}

// MARK: - Attempt 016: picker style replacement

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 016 changing picker style replaces its navigation contract")
  func stress016ChangingPickerStyleReplacesNavigationContract() throws {
    // Hypothesis: a stable explicit identity may retain the old style's key
    // handler after replacing horizontal segmented navigation with vertical radio navigation.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS016", "Root"),
      size: .init(width: 48, height: 11)
    ) {
      StressPS016Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Use radio style")
    _ = try harness.focusText("Mode")
    var frame = try harness.pressKey(KeyPress(.arrowRight))
    #expect(frame.contains("Selection a"))
    frame = try harness.pressKey(KeyPress(.arrowDown))
    #expect(frame.contains("Selection b"))
  }
}

@MainActor
private struct StressPS016Fixture: View {
  @State private var usesRadio = false
  @State private var selection = "a"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Use radio style") {
        usesRadio = true
      }
      if usesRadio {
        picker.pickerStyle(.radioGroup)
      } else {
        picker.pickerStyle(.segmented)
      }
      Text("Selection \(selection)")
    }
  }

  private var picker: some View {
    Picker("Mode", selection: $selection) {
      Text("A").tag("a")
      Text("B").tag("b")
    }
    .id("style-replaced-picker")
  }
}

// MARK: - Attempt 017: disabling active menu-style picker

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 017 disabling an active menu picker removes option routes")
  func stress017DisablingActiveMenuPickerRemovesOptionRoutes() throws {
    // Hypothesis: focused menu-style Picker expansion may outlive the
    // enablement transition and preserve its option handlers and rows.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS017", "Root"),
      size: .init(width: 46, height: 11)
    ) {
      StressPS017Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Alpha option")
    let frame = try harness.clickText("Disable picker")

    #expect(!frame.contains("Beta option"))
    #expect(harness.keyHandlerCount == 0)
  }
}

@MainActor
private struct StressPS017Fixture: View {
  @State private var isDisabled = false
  @State private var selection = "a"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Disable picker") {
        isDisabled = true
      }
      Picker("Mode", selection: $selection) {
        Text("Alpha option").tag("a")
        Text("Beta option").tag("b")
      }
      .pickerStyle(.menu)
      .disabled(isDisabled)
    }
  }
}

// MARK: - Attempt 018: toggle binding retarget

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 018 a stable toggle writes only its current binding")
  func stress018StableToggleWritesCurrentBinding() throws {
    // Hypothesis: retained Toggle action registration may keep the binding
    // captured before a same-identity control was retargeted.
    let probe = StressPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS018", "Root"),
      size: .init(width: 42, height: 8)
    ) {
      StressPS018Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Retarget toggle")
    _ = try harness.clickText("Stable toggle")

    #expect(probe.firstBool == false)
    #expect(probe.secondBool == true)
  }
}

@MainActor
private struct StressPS018Fixture: View {
  let probe: StressPresentationProbe
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget toggle") {
        usesSecond = true
      }
      Toggle(
        "Stable toggle",
        isOn: usesSecond ? probe.secondBoolBinding() : probe.firstBoolBinding()
      )
      .id("stable-toggle")
    }
  }
}

// MARK: - Attempt 019: expanded disclosure payload refresh

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 019 an expanded disclosure renders its current payload")
  func stress019ExpandedDisclosureRendersCurrentPayload() throws {
    // Hypothesis: the expanded conditional branch may be retained solely by
    // its stable disclosure identity and keep an earlier content payload.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS019", "Root"),
      size: .init(width: 44, height: 9)
    ) {
      StressPS019Fixture()
    }
    defer { harness.shutdown() }

    let frame = try harness.clickText("Advance disclosure payload")

    #expect(frame.contains("Disclosure content 1"))
    #expect(!frame.contains("Disclosure content 0"))
  }
}

@MainActor
private struct StressPS019Fixture: View {
  @State private var isExpanded = true
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance disclosure payload") {
        generation += 1
      }
      DisclosureGroup("Details", isExpanded: $isExpanded) {
        Text("Disclosure content \(generation)")
      }
    }
  }
}

// MARK: - Attempt 020: disclosure binding retarget

extension FrameworkStressPresentationSemanticsTests {
  @Test(
    "stress presentation semantics 020 a stable disclosure writes its current expansion binding")
  func stress020StableDisclosureWritesCurrentExpansionBinding() throws {
    // Hypothesis: DisclosureGroup's retained action registration may toggle
    // the expansion binding from before a same-identity retarget.
    let probe = StressPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS020", "Root"),
      size: .init(width: 44, height: 9)
    ) {
      StressPS020Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Retarget disclosure")
    let frame = try harness.clickText("Bound details")

    #expect(probe.firstBool == false)
    #expect(probe.secondBool == true)
    #expect(frame.contains("Current bound content"))
  }
}

@MainActor
private struct StressPS020Fixture: View {
  let probe: StressPresentationProbe
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget disclosure") {
        usesSecond = true
      }
      DisclosureGroup(
        "Bound details",
        isExpanded: usesSecond ? probe.secondBoolBinding() : probe.firstBoolBinding()
      ) {
        Text("Current bound content")
      }
      .id("stable-disclosure")
    }
  }
}

// MARK: - Attempt 021: disclosure identity replacement

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 021 a reminted disclosure installs one live action")
  func stress021RemintedDisclosureInstallsOneLiveAction() throws {
    // Hypothesis: replacing an expanded DisclosureGroup's explicit identity
    // may leave its departed action registration shadowing the new lifetime.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS021", "Root"),
      size: .init(width: 44, height: 9)
    ) {
      StressPS021Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Remint disclosure")
    let frame = try harness.clickText("Reminted details 1")

    #expect(!frame.contains("Reminted content"))
    #expect(harness.actionRegistrationCount == 2)
  }
}

@MainActor
private struct StressPS021Fixture: View {
  @State private var isExpanded = true
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remint disclosure") {
        generation += 1
      }
      DisclosureGroup("Reminted details \(generation)", isExpanded: $isExpanded) {
        Text("Reminted content")
      }
      .id(generation)
    }
  }
}

// MARK: - Attempt 022: slider binding retarget

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 022 a stable slider writes only its current binding")
  func stress022StableSliderWritesCurrentBinding() throws {
    // Hypothesis: the Slider's retained key and pointer registrations may keep
    // the binding captured before a same-identity retarget.
    let probe = StressPresentationProbe()
    probe.firstInt = 8
    probe.secondInt = 1
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS022", "Root"),
      size: .init(width: 54, height: 9)
    ) {
      StressPS022Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Retarget slider")
    _ = try harness.focusText("Stable slider")
    _ = try harness.pressKey(KeyPress(.arrowRight))

    #expect(probe.firstInt == 8)
    #expect(probe.secondInt == 2)
  }
}

@MainActor
private struct StressPS022Fixture: View {
  let probe: StressPresentationProbe
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget slider") {
        usesSecond = true
      }
      Slider(
        "Stable slider",
        value: usesSecond ? probe.secondIntBinding() : probe.firstIntBinding(),
        in: 0...10
      )
      .id("stable-slider")
    }
  }
}

// MARK: - Attempt 023: slider range and step churn

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 023 a slider uses its current narrowed range and step")
  func stress023SliderUsesCurrentNarrowedRangeAndStep() throws {
    // Hypothesis: retained Slider handlers may keep the original bounds and
    // step even while rendering a newly narrowed control contract.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS023", "Root"),
      size: .init(width: 54, height: 10)
    ) {
      StressPS023Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Narrow slider")
    _ = try harness.focusText("Range slider")
    let frame = try harness.pressKey(KeyPress(.arrowLeft))

    #expect(frame.contains("Bound value 4"))
  }
}

@MainActor
private struct StressPS023Fixture: View {
  @State private var isNarrow = false
  @State private var value = 8

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Narrow slider") {
        isNarrow = true
      }
      Slider(
        "Range slider",
        value: $value,
        in: isNarrow ? 0...4 : 0...10,
        step: isNarrow ? 2 : 1
      )
      .id("range-slider")
      Text("Bound value \(value)")
    }
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
