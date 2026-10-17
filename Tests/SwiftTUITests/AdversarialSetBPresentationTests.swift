@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 2: presentation ordering and gating (131–140).
//
// Presentations are ordered by an activation ordinal minted when a declaration
// first becomes active, prompts queue first-in first-out, and a modal surface
// disables the base beneath it. The register fixes the visible contract:
// Escape dismisses the most recently activated visible presentation, only the
// oldest active prompt is visible, same-ID item replacement refreshes in
// place. These probes interleave families so that the minting order and the
// visible order differ, disable the presenter beneath its own prompt, present
// from a dismissal, and anchor a popover outside its host.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: presentations", .serialized)
struct AdversarialSetBPresentationTests {
  private func harness<V: View>(
    _ name: String, width: Int = 48, height: Int = 14, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBPresentation", name),
      size: .init(width: width, height: height), content: content)
  }

  // A prompt that was queued behind an older prompt and surfaces after a
  // newer sheet is the most recently activated visible presentation: it is
  // shown above the sheet, is operable, and takes the next Escape.
  @Test func setB131QueuedAlertSurfacingAfterANewerSheetIsOnTop() throws {
    let probe = SetBEventProbe()
    let h = try harness("QueuedUnderSheet") { SetBQueuedUnderSheetFixture(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("Open alerts")
    try #require(h.frame.contains("Alert A"), "\(h.frame)")
    #expect(!h.frame.contains("Alert B"), "\(h.frame)")
    _ = try h.clickText("Open sheet")
    try #require(h.frame.contains("S body"), "\(h.frame)")
    if h.frame.contains("Alert A") {
      _ = try h.focusText("S body")
      _ = try h.pressKey(KeyPress(.character("d"), modifiers: .ctrl))
    }
    try #require(!h.frame.contains("Alert A"), "\(h.frame)")
    let surfaced = h.frame
    _ = try h.pressKey(KeyPress(.escape))
    let afterEscape = h.frame
    withKnownIssue(
      "the queued prompt never surfaces while the newer sheet is open; Escape reaches the sheet"
    ) {
      #expect(
        surfaced.contains("Alert B") && surfaced.contains("B body"),
        "B surfaces once A is gone: \(surfaced)")
      #expect(
        !afterEscape.contains("Alert B"), "Escape takes the newest visible prompt: \(afterEscape)")
      #expect(afterEscape.contains("S body"), "\(afterEscape)")
      #expect(probe.events == ["A dismissed", "B dismissed"], "\(probe.events)")
    }
    for _ in 0..<3 where h.frame.contains("S body") || h.frame.contains("Alert B") {
      _ = try h.pressKey(KeyPress(.escape))
    }
    #expect(!h.frame.contains("S body") && !h.frame.contains("Alert B"), "\(h.frame)")
  }

  // Disabling the presenter does not disable the prompt it presents: the
  // alert's own buttons stay operable.
  @Test func setB132DisabledPresenterKeepsItsAlertOperable() throws {
    let probe = SetBEventProbe()
    let h = try harness("LockedPresenter") { SetBLockedPresenterFixture(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("Lock and open")
    try #require(h.frame.contains("Alert L"), "\(h.frame)")
    let dismiss = try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.role == .button && $0.label == "Dismiss L"
      })
    _ = try h.clickText("Dismiss L")
    let afterClick = h.frame
    withKnownIssue(
      "prompt content resolves under the presenter's environment, so a disabled presenter disables its own alert (menu precedent: stress008)"
    ) {
      #expect(dismiss.isEnabled, "the alert button is enabled although its presenter is not")
      #expect(!afterClick.contains("Alert L"), "\(afterClick)")
      #expect(probe.events == ["L dismissed"], "\(probe.events)")
    }
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("Alert L"), "Escape still closes it: \(h.frame)")
  }

  // Presenting sheet B from sheet A's `onDismiss` works and runs each
  // dismissal exactly once.
  @Test func setB133PresentingFromADismissalOpensTheNextSheet() throws {
    let probe = SetBEventProbe()
    let h = try harness("ChainedSheets") { SetBChainedSheetsFixture(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("Open A")
    try #require(h.frame.contains("A body"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(h.frame.contains("B body"), "\(h.frame)")
    #expect(!h.frame.contains("A body"), "\(h.frame)")
    #expect(probe.events == ["A dismissed"], "\(probe.events)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("B body"), "\(h.frame)")
    #expect(probe.events == ["A dismissed", "B dismissed"], "\(probe.events)")
  }

  // The base is inert beneath a modal sheet but stays interactive beneath a
  // non-modal popover tip.
  @Test func setB134BaseIsInertUnderASheetAndLiveUnderATip() throws {
    let h = try harness("Gate") { SetBGateFixture() }
    defer { h.shutdown() }
    let counter = try #require(h.point(forText: "Count up"))
    _ = try h.click(counter)
    try #require(h.frame.contains("count 1"), "\(h.frame)")

    _ = try h.clickText("Open sheet")
    try #require(h.frame.contains("Sheet body"), "\(h.frame)")
    _ = try h.click(counter)
    _ = try h.pressKey(KeyPress(.escape))
    try #require(!h.frame.contains("Sheet body"), "\(h.frame)")
    #expect(h.frame.contains("count 1"), "a click beneath a modal sheet is inert: \(h.frame)")

    _ = try h.clickText("Open tip")
    try #require(h.frame.contains("Tip body"), "\(h.frame)")
    _ = try h.click(counter)
    _ = try h.pressKey(KeyPress(.escape))
    #expect(h.frame.contains("count 2"), "a click beneath a tip reaches the base: \(h.frame)")
  }

  // A confirmation dialog with no actions still has its close affordance,
  // dismisses on Escape, runs `onDismiss` once and restores focus.
  @Test func setB135ConfirmationDialogWithoutActionsIsStillDismissable() throws {
    let probe = SetBEventProbe()
    let h = try harness("EmptyDialog") { SetBEmptyDialogFixture(probe: probe) }
    defer { h.shutdown() }
    let opener = try h.focusIdentity(forText: "Ask")
    _ = try h.clickText("Ask")
    try #require(h.frame.contains("Sure?"), "\(h.frame)")
    #expect(h.frame.contains("×"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("Sure?"), "\(h.frame)")
    #expect(probe.events == ["asked"], "\(probe.events)")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == opener)
  }

  // Tab from an open menu's trigger moves into the menu, whose items float
  // directly below their source, not past them to the next base control.
  @Test func setB136TabFromAnOpenMenuEntersTheMenu() throws {
    let h = try harness("MenuTab") {
      HStack(spacing: 2) {
        Menu("Actions") {
          Button("Item one") {}
          Button("Item two") {}
        }
        Button("Next") {}
      }
    }
    defer { h.shutdown() }
    let next = try h.focusIdentity(forText: "Next")
    _ = try h.clickText("Actions")
    try #require(h.frame.contains("Item one"), "\(h.frame)")
    let itemOne = try h.focusIdentity(forText: "Item one")
    let itemTwo = try h.focusIdentity(forText: "Item two")
    _ = try h.pressKey(KeyPress(.tab))
    let focused = h.runLoop.focusTracker.currentFocusIdentity
    withKnownIssue(
      "overlay regions sit after every base region, so Tab from the trigger reaches the next base control first"
    ) {
      #expect(focused == itemOne || focused == itemTwo, "\(String(describing: focused))")
      #expect(focused != next, "Tab skipped the open menu: \(h.frame)")
    }
  }

  // Escape dismisses the most recently activated visible presentation across
  // families: a sheet opened from a popover closes before the popover.
  @Test func setB137EscapeTakesTheNewestVisiblePresentationAcrossFamilies() throws {
    let h = try harness("PopoverThenSheet") { SetBPopoverThenSheetFixture() }
    defer { h.shutdown() }
    _ = try h.clickText("Open pop")
    try #require(h.frame.contains("Open sheet"), "\(h.frame)")
    _ = try h.clickText("Open sheet")
    try #require(h.frame.contains("S body"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("S body"), "\(h.frame)")
    #expect(h.frame.contains("Open sheet"), "the popover is still open: \(h.frame)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("Open sheet"), "\(h.frame)")
  }

  // Replacing a presented item with an equal-ID value refreshes the mounted
  // content without losing its state; a new ID remounts it.
  @Test func setB138SameIDItemReplacementRefreshesWithoutLosingState() throws {
    let h = try harness("Retitle") { SetBRetitleFixture() }
    defer { h.shutdown() }
    _ = try h.clickText("Open item")
    _ = try h.clickText("I Increment")
    _ = try h.clickText("I Increment")
    try #require(h.frame.contains("I Count 2"), "\(h.frame)")
    _ = try h.clickText("Retitle")
    #expect(h.frame.contains("Item second"), "\(h.frame)")
    #expect(h.frame.contains("I Count 2"), "\(h.frame)")
    _ = try h.clickText("Reidentify")
    #expect(h.frame.contains("Item third"), "\(h.frame)")
    #expect(h.frame.contains("I Count 0"), "\(h.frame)")
  }

  // Two prompts activated in one action queue first-in first-out, and Escape
  // only ever reaches the visible one.
  @Test func setB139PromptsActivatedTogetherQueueInOrder() throws {
    let probe = SetBEventProbe()
    let h = try harness("TwoAlerts") { SetBTwoAlertsFixture(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("Open both")
    try #require(h.frame.contains("Alert A"), "\(h.frame)")
    #expect(!h.frame.contains("Alert B"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("Alert A"), "\(h.frame)")
    #expect(h.frame.contains("Alert B"), "\(h.frame)")
    #expect(probe.events == ["A dismissed"], "\(probe.events)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("Alert B"), "\(h.frame)")
    #expect(probe.events == ["A dismissed", "B dismissed"], "\(probe.events)")
  }

  // A popover anchored to a point outside its source clamps into the
  // viewport and stays readable and dismissable.
  @Test func setB140PopoverAnchoredOutsideItsSourceClampsIntoTheViewport() throws {
    let h = try harness("FarAnchor", width: 30, height: 8) { SetBFarAnchorFixture() }
    defer { h.shutdown() }
    _ = try h.clickText("Open far")
    #expect(h.frame.contains("Pop body"), "\(h.frame)")
    let lines = h.frame.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 8, "the recording host normalizes CRLF to LF")
    do {
      #expect(lines.allSatisfy { $0.count <= 30 }, "no row exceeds the viewport: \(h.frame)")
    }
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("Pop body"), "\(h.frame)")
  }
}

@MainActor
private final class SetBEventProbe {
  var events: [String] = []
}

private struct SetBTitledItem: Identifiable, Sendable {
  var id: String
  var title: String
}

private struct SetBCounterPane: View {
  let label: String
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) Count \(count)")
      Button("\(label) Increment") { count += 1 }
    }
  }
}

private struct SetBQueuedUnderSheetFixture: View {
  let probe: SetBEventProbe
  @State private var a = false
  @State private var b = false
  @State private var s = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open alerts") {
        a = true
        b = true
      }
    }
    .alert("Alert A", isPresented: $a, onDismiss: { probe.events.append("A dismissed") }) {
      Button("Open sheet") { s = true }
      Button("Dismiss A") { a = false }
    } message: {
      Text("A body")
    }
    .alert("Alert B", isPresented: $b, onDismiss: { probe.events.append("B dismissed") }) {
      Button("Dismiss B") { b = false }
    } message: {
      Text("B body")
    }
    .sheet("Sheet S", isPresented: $s) {
      Panel(id: "sheet") {
        Text("S body").focusable()
      }
      .keyCommand("Close A", key: .character("d"), modifiers: .ctrl) { a = false }
    }
  }
}

private struct SetBLockedPresenterFixture: View {
  let probe: SetBEventProbe
  @State private var locked = false
  @State private var open = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Lock and open") {
        locked = true
        open = true
      }
      .alert("Alert L", isPresented: $open, onDismiss: { probe.events.append("L dismissed") }) {
        Button("Dismiss L") { open = false }
      } message: {
        Text("L body")
      }
      .disabled(locked)
      Text("locked: \(locked)")
    }
  }
}

private struct SetBChainedSheetsFixture: View {
  let probe: SetBEventProbe
  @State private var a = false
  @State private var b = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open A") { a = true }
    }
    .sheet(
      "A", isPresented: $a,
      onDismiss: {
        probe.events.append("A dismissed")
        b = true
      }
    ) {
      Text("A body")
    }
    .sheet("B", isPresented: $b, onDismiss: { probe.events.append("B dismissed") }) {
      Text("B body")
    }
  }
}

private struct SetBGateTip: PopoverTip {
  var id: String { "gate-tip" }
  var title: Text { Text("Tip body") }
}

private struct SetBGateFixture: View {
  @State private var count = 0
  @State private var sheet = false
  @State private var tip = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Count up") { count += 1 }
      Text("count \(count)")
      Button("Open sheet") { sheet = true }
        .sheet("Sheet", isPresented: $sheet) { Text("Sheet body") }
      Button("Open tip") { tip = true }
        .popoverTip(SetBGateTip(), isPresented: $tip)
    }
  }
}

private struct SetBEmptyDialogFixture: View {
  let probe: SetBEventProbe
  @State private var asking = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Ask") { asking = true }
    }
    .confirmationDialog("Sure?", isPresented: $asking, onDismiss: { probe.events.append("asked") })
    {
      EmptyView()
    } message: {
      Text("No actions here")
    }
  }
}

private struct SetBPopoverThenSheetFixture: View {
  @State private var pop = false
  @State private var sheet = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open pop") { pop = true }
        .popover(isPresented: $pop) {
          Button("Open sheet") { sheet = true }
        }
        .sheet("S", isPresented: $sheet) { Text("S body") }
    }
  }
}

private struct SetBRetitleFixture: View {
  @State private var item: SetBTitledItem?

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open item") { item = SetBTitledItem(id: "1", title: "first") }
    }
    .sheet(item: $item) { presented in
      VStack(alignment: .leading) {
        Text("Item \(presented.title)")
        SetBCounterPane(label: "I")
        Button("Retitle") { item = SetBTitledItem(id: "1", title: "second") }
        Button("Reidentify") { item = SetBTitledItem(id: "2", title: "third") }
      }
    }
  }
}

private struct SetBTwoAlertsFixture: View {
  let probe: SetBEventProbe
  @State private var a = false
  @State private var b = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open both") {
        a = true
        b = true
      }
    }
    .alert("Alert A", isPresented: $a, onDismiss: { probe.events.append("A dismissed") })
    .alert("Alert B", isPresented: $b, onDismiss: { probe.events.append("B dismissed") })
  }
}

private struct SetBFarAnchorFixture: View {
  @State private var open = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open far") { open = true }
        .popover(isPresented: $open, attachmentAnchor: .point(UnitPoint(x: 3, y: 3))) {
          Text("Pop body")
        }
    }
  }
}
