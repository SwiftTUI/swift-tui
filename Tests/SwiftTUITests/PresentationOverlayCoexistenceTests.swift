import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Coexisting presentation-portal overlay entries (gallery presentation-lab
// report, 2026-07-04): retained-subtree reuse is value-blind, so a portal
// reconcile that changed the overlay-entry SET while another entry stayed
// visible was served the stale committed `PortalHost/overlays` children —
// a second presentation never appeared, and a dismissed one never left the
// screen (its stale strand then shadowed the reopened entry's routes: the
// "undismissable sheet", plus teardown-coherence census orphans). The
// 0↔1 transitions restructure the wrapper and were never affected; only
// 1→2 / 2→1 transitions hit the reuse hole. Fixed in
// `composeOverlayStackTree` by marking the overlays subtree churned when
// the composed entry list differs from the committed children.
//
// Self-contained (own harness copy) so it can be dropped into other
// commits during bisects.
@MainActor
@Suite("Presentation overlay coexistence", .serialized)
struct PresentationOverlayCoexistenceTests {
  @Test("popoverTip action button dismisses the tip")
  func popoverTipActionButtonDismissesTheTip() throws {
    let harness = try CoexistenceHarness(
      rootIdentity: testIdentity("TipDismissRegressionRoot"),
      size: .init(width: 72, height: 24)
    ) {
      TipDismissFixture()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Show Tip")
    #expect(frame.contains("Demo tip"), "tip must open; frame:\n\(frame)")

    frame = try harness.clickText("Got it", chooseLast: true)
    #expect(frame.contains("tip Got it"), "tip action must fire; frame:\n\(frame)")
    #expect(
      frame.contains("tipPresented false"),
      "tip dismiss write must land in the live state box; frame:\n\(frame)"
    )
    #expect(
      !frame.contains("Demo tip"),
      "tip must close on its action button; frame:\n\(frame)"
    )
  }

  @Test("alert opens while a toast is visible")
  func alertOpensWhileToastVisible() throws {
    let harness = try CoexistenceHarness(
      rootIdentity: testIdentity("AlertBehindToastRoot"),
      size: .init(width: 60, height: 16)
    ) {
      AlertBehindToastFixture()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Open Toast")
    #expect(frame.contains("Toast body"), "toast must open; frame:\n\(frame)")

    frame = try harness.clickText("Open Alert")
    #expect(
      frame.contains("Alert title"),
      "alert must open while the toast is visible; frame:\n\(frame)"
    )
  }

  // The gallery-shaped mirror sweep is split into three tests so no single
  // synchronous @MainActor test blocks the actor long enough to starve the
  // awaited-input harnesses that run concurrently in this target
  // (PortalForceQueueAwaitedInputReader steps time out under a multi-second
  // continuous main-actor block).

  @Test("lab mirror modal prompts round-trip without orphans")
  func labMirrorModalPromptsRoundTripWithoutOrphans() throws {
    let baseline = SoundnessProbeConfiguration.teardownCoherenceViolationCount
    let harness = try CoexistenceHarness(
      rootIdentity: testIdentity("LabMirrorPromptsRoot"),
      size: .init(width: 84, height: 42)
    ) {
      LabMirrorFixture()
    }
    defer { harness.shutdown() }
    let expectNoViolations = makeViolationCheck(baseline: baseline)

    // Alert open/accept.
    var frame = try harness.clickText("Alert")
    #expect(frame.contains("Build gate updated"), "alert must open; frame:\n\(frame)")
    frame = try harness.clickText("OK", chooseLast: true)
    #expect(!frame.contains("Build gate updated"))
    expectNoViolations("alert", #_sourceLocation)

    // Confirmation open/reset.
    frame = try harness.clickText("Confirm")
    #expect(frame.contains("Reset presentation state?"))
    frame = try harness.clickText("Reset", chooseLast: true)
    #expect(!frame.contains("Reset presentation state?"))
    expectNoViolations("confirmation", #_sourceLocation)

    // Sheet open/close via its button, then open/Escape.
    frame = try harness.clickText("Sheet")
    #expect(frame.contains("Sheet content"))
    frame = try harness.clickText("Close", chooseLast: true)
    #expect(!frame.contains("Sheet content"))
    expectNoViolations("sheet close", #_sourceLocation)
    frame = try harness.clickText("Sheet")
    #expect(frame.contains("Sheet content"))
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(!frame.contains("Sheet content"))
    expectNoViolations("sheet escape", #_sourceLocation)
  }

  @Test("lab mirror coexisting entries stay live under a toast")
  func labMirrorCoexistingEntriesStayLiveUnderAToast() throws {
    let baseline = SoundnessProbeConfiguration.teardownCoherenceViolationCount
    let harness = try CoexistenceHarness(
      rootIdentity: testIdentity("LabMirrorCoexistRoot"),
      size: .init(width: 84, height: 42)
    ) {
      LabMirrorFixture()
    }
    defer { harness.shutdown() }
    let expectNoViolations = makeViolationCheck(baseline: baseline)

    // Toast opens (timed dismissal not awaited) and stays up for the rest of
    // the test, so every following transition is a 1→2 / 2→1 entry-set change.
    var frame = try harness.clickText("Toast")
    expectNoViolations("toast open", #_sourceLocation)

    // With the (non-modal) toast up, other surfaces must stay interactive.
    frame = try harness.clickText("Alert")
    #expect(
      frame.contains("Build gate updated"),
      "alert must open with a toast visible; frame:\n\(frame)"
    )
    frame = try harness.clickText("OK", chooseLast: true)
    #expect(!frame.contains("Build gate updated"))
    expectNoViolations("alert behind toast", #_sourceLocation)

    // Anchored popover open/Escape.
    frame = try harness.clickText("Popover")
    #expect(frame.contains("Popover content"))
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(!frame.contains("Popover content"))
    expectNoViolations("anchored popover", #_sourceLocation)

    // Anchored tip: action closure closes it (user-side write).
    frame = try harness.clickText(" Tip ")
    #expect(frame.contains("Popover tip"))
    frame = try harness.clickText("Got it", chooseLast: true)
    #expect(!frame.contains("Popover tip"))
    #expect(frame.contains("tip acknowledged"))
    expectNoViolations("anchored tip", #_sourceLocation)

    // Boolean popover open/close.
    frame = try harness.clickText("Show Details")
    #expect(frame.contains("Details popover"))
    frame = try harness.clickText("Close Details", chooseLast: true)
    #expect(!frame.contains("Details popover"))
    expectNoViolations("boolean popover", #_sourceLocation)

    // Item popover open/done for both tools.
    frame = try harness.clickText("Filters")
    #expect(frame.contains("Tune the visible rows."))
    frame = try harness.clickText("Done", chooseLast: true)
    #expect(!frame.contains("Tune the visible rows."))
    expectNoViolations("item popover filters", #_sourceLocation)
    frame = try harness.clickText("Export")
    #expect(frame.contains("Review destination and format."))
    frame = try harness.clickText("Done", chooseLast: true)
    #expect(!frame.contains("Review destination and format."))
    expectNoViolations("item popover export", #_sourceLocation)
  }

  @Test("lab mirror demo tip, palette, and tab churn keep the sheet dismissable")
  func labMirrorDemoTipPaletteAndTabChurnKeepTheSheetDismissable() throws {
    let baseline = SoundnessProbeConfiguration.teardownCoherenceViolationCount
    let harness = try CoexistenceHarness(
      rootIdentity: testIdentity("LabMirrorChurnRoot"),
      size: .init(width: 84, height: 42)
    ) {
      LabMirrorFixture()
    }
    defer { harness.shutdown() }
    let expectNoViolations = makeViolationCheck(baseline: baseline)

    // Keep a toast up so the tip/palette transitions churn a coexisting set.
    var frame = try harness.clickText("Toast")
    expectNoViolations("toast open", #_sourceLocation)

    // Demo tip: framework dismiss via its action button.
    frame = try harness.clickText("Show Tip")
    #expect(frame.contains("Try item popovers"))
    frame = try harness.clickText("Got it", chooseLast: true)
    #expect(frame.contains("demo acknowledged"))
    #expect(
      !frame.contains("Try item popovers"),
      "demo tip must close on its action; frame:\n\(frame)"
    )
    expectNoViolations("demo tip", #_sourceLocation)

    // Palette: open, fire the sample action, reopen, dismiss.
    frame = try harness.clickText("Palette")
    #expect(frame.contains("Presentation Lab Sample Action"))
    frame = try harness.clickText("Presentation Lab Sample Action", chooseLast: true)
    #expect(frame.contains("palette command fired"))
    expectNoViolations("palette action", #_sourceLocation)
    frame = try harness.clickText("Palette")
    frame = try harness.clickText("Dismiss Palette", chooseLast: true)
    expectNoViolations("palette dismiss", #_sourceLocation)

    // Tab churn after all of the presentation churn.
    frame = try harness.clickText("Next Tab")
    #expect(frame.contains("Other body"))
    frame = try harness.clickText("Next Tab")
    #expect(frame.contains("Presentation Lab"))
    expectNoViolations("tab churn", #_sourceLocation)

    // Sheet must reopen and stay dismissable at the end.
    frame = try harness.clickText("Sheet")
    #expect(frame.contains("Sheet content"))
    frame = try harness.clickText("Close", chooseLast: true)
    #expect(
      !frame.contains("Sheet content"),
      "sheet became undismissable after the sweep; frame:\n\(frame)"
    )
    expectNoViolations("final sheet", #_sourceLocation)
  }

  private func makeViolationCheck(
    baseline: Int
  ) -> @MainActor (Comment, SourceLocation) -> Void {
    { step, sourceLocation in
      let violations =
        SoundnessProbeConfiguration.teardownCoherenceViolationCount - baseline
      #expect(
        violations == 0,
        "\(step): \(violations) violation(s): \(SoundnessProbeConfiguration.lastViolationDetail ?? "no detail recorded")",
        sourceLocation: sourceLocation
      )
    }
  }

  @Test("tab churn under an open presentation prunes cleanly")
  func tabChurnUnderOpenPresentationPrunesCleanly() throws {
    let baseline = SoundnessProbeConfiguration.teardownCoherenceViolationCount
    let harness = try CoexistenceHarness(
      rootIdentity: testIdentity("TipDismissModalChurnRoot"),
      size: .init(width: 72, height: 24)
    ) {
      TipDismissTabFixture()
    }
    defer { harness.shutdown() }

    func violations() -> Int {
      SoundnessProbeConfiguration.teardownCoherenceViolationCount - baseline
    }

    // A modal sheet absorbs root-scope key commands: ctrl+t must not switch
    // the tab underneath it, and Escape must still unwind the sheet.
    var frame = try harness.clickText("Open Sheet")
    #expect(frame.contains("Sheet content"), "sheet must open; frame:\n\(frame)")
    frame = try harness.pressKey(KeyPress(.character("t"), modifiers: .ctrl))
    #expect(frame.contains("tab=lab"), "modal sheet must absorb the tab command; frame:\n\(frame)")
    #expect(frame.contains("Sheet content"), "sheet must stay up; frame:\n\(frame)")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(!frame.contains("Sheet content"))
    #expect(violations() == 0, "modal absorb: \(SoundnessProbeConfiguration.lastViolationDetail ?? "-")")

    // The modal tip likewise: open it, verify absorption, then churn the tab
    // underneath after Escape and confirm the presentation surface recovers.
    frame = try harness.clickText("Show Tip")
    #expect(frame.contains("Demo tip"), "tip must open; frame:\n\(frame)")
    frame = try harness.pressKey(KeyPress(.character("t"), modifiers: .ctrl))
    #expect(frame.contains("tab=lab"), "modal tip must absorb the tab command; frame:\n\(frame)")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(!frame.contains("Demo tip"), "escape must dismiss the tip; frame:\n\(frame)")
    #expect(violations() == 0, "tip absorb: \(SoundnessProbeConfiguration.lastViolationDetail ?? "-")")

    frame = try harness.pressKey(KeyPress(.character("t"), modifiers: .ctrl))
    #expect(frame.contains("Other body"), "tab must switch once no modal is up; frame:\n\(frame)")
    frame = try harness.pressKey(KeyPress(.character("t"), modifiers: .ctrl))
    #expect(frame.contains("Lab body"), "tab must switch back; frame:\n\(frame)")
    #expect(violations() == 0, "tab churn: \(SoundnessProbeConfiguration.lastViolationDetail ?? "-")")

    // The sheet must reopen and stay dismissable after all of the churn.
    frame = try harness.clickText("Open Sheet")
    #expect(frame.contains("Sheet content"), "sheet must reopen; frame:\n\(frame)")
    frame = try harness.clickText("Close Sheet", chooseLast: true)
    #expect(
      !frame.contains("Sheet content"),
      "sheet must stay dismissable after churn; frame:\n\(frame)"
    )
    #expect(violations() == 0, "final: \(SoundnessProbeConfiguration.lastViolationDetail ?? "-")")
  }

  @Test("popoverTip action button dismisses the tip after sheet churn")
  func popoverTipActionButtonDismissesTheTipAfterSheetChurn() throws {
    let harness = try CoexistenceHarness(
      rootIdentity: testIdentity("TipDismissRegressionChurnRoot"),
      size: .init(width: 72, height: 24)
    ) {
      TipDismissTabFixture()
    }
    defer { harness.shutdown() }

    // Preamble: one sheet open/close cycle via the sheet's own button, then
    // one dismissed with Escape (the framework dismiss closure).
    var frame = try harness.clickText("Open Sheet")
    #expect(frame.contains("Sheet content"), "sheet must open; frame:\n\(frame)")
    frame = try harness.clickText("Close Sheet", chooseLast: true)
    #expect(!frame.contains("Sheet content"), "sheet must close; frame:\n\(frame)")

    frame = try harness.clickText("Open Sheet")
    #expect(frame.contains("Sheet content"), "sheet must reopen; frame:\n\(frame)")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(!frame.contains("Sheet content"), "escape must close the sheet; frame:\n\(frame)")

    frame = try harness.clickText("Show Tip")
    #expect(frame.contains("Demo tip"), "tip must open; frame:\n\(frame)")

    frame = try harness.clickText("Got it", chooseLast: true)
    #expect(frame.contains("tip Got it"), "tip action must fire; frame:\n\(frame)")
    #expect(
      frame.contains("tipPresented false"),
      "tip dismiss write must land in the live state box; frame:\n\(frame)"
    )
    #expect(
      !frame.contains("Demo tip"),
      "tip must close on its action button; frame:\n\(frame)"
    )
  }
}

private struct AlertBehindToastFixture: View {
  @State private var showAlert = false
  @State private var showToast = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Fixture body")
      Button("Open Toast") { showToast = true }
      Button("Open Alert") { showAlert = true }
    }
    .alert(
      "Alert title",
      isPresented: $showAlert,
      actions: {
        Button("OK") { showAlert = false }
      },
      message: {
        Text("Alert message")
      }
    )
    .toast("Toast body", isPresented: $showToast, duration: 2.0)
    .frame(width: 60, height: 16, alignment: .topLeading)
  }
}

// 1:1 shape mirror of the gallery's PresentationLabTab (same modifier stack,
// same section structure), hosted in a tab like the gallery hosts it.
private struct LabMirrorFixture: View {
  @State private var selectedTab = "lab"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Next Tab") {
        selectedTab = selectedTab == "lab" ? "other" : "lab"
      }

      TabView(selection: $selectedTab) {
        Tab("Lab", value: "lab") {
          LabMirrorTab()
        }

        Tab("Other", value: "other") {
          Text("Other body")
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 84, height: 42, alignment: .topLeading)
  }
}

private struct LabMirrorTab: View {
  @State private var showAlert = false
  @State private var showConfirmation = false
  @State private var showSheet = false
  @State private var showToast = false
  @State private var showPopover = false
  @State private var showTip = false
  @State private var showPalette = false
  @State private var showPopoverDetails = false
  @State private var selectedPopoverTool: LabMirrorPopoverTool?
  @State private var showPopoverDemoTip = false
  @State private var popoverTipResult = "no tip action yet"
  @State private var lastEvent = "no presentation opened yet"
  @State private var probe = 0

  private let popoverTools: [LabMirrorPopoverTool] = [
    .init(id: "filters", name: "Filters", detail: "Tune the visible rows."),
    .init(id: "export", name: "Export", detail: "Review destination and format."),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Presentation Lab probe=\(probe) alert=\(showAlert)")
      // Rendered up top (the gallery keeps it at the bottom) so the
      // never-expiring toast in this harness cannot paint over it — a covered
      // "…on: Got it" residue otherwise hijacks chooseLast text locators.
      Text("Last event: \(lastEvent)")
      Divider()
      ControlGroup("Modals") {
        Button("Alert") {
          probe += 1
          showAlert = true
        }
        Button("Confirm") { showConfirmation = true }
        Button("Sheet") { showSheet = true }
      }
      .focusSection()
      ControlGroup("Anchored") {
        Button("Toast") { showToast = true }
        Button("Popover") { showPopover = true }
          .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
              Text("Popover content").bold()
              Text("Attached to the Popover button.")
            }
            .padding(1)
          }
        Button("Tip") { showTip = true }
          .popoverTip(
            LabMirrorTip(),
            isPresented: $showTip,
            arrowEdge: .top
          ) { action in
            lastEvent = "tip acknowledged"
            showTip = false
          }
      }
      .focusSection()
      ControlGroup("Command surface") {
        Button("Palette") { showPalette = true }
      }
      Divider()
      booleanPopoverSection
        .focusSection()
      Divider()
      itemPopoverSection
        .focusSection()
      Divider()
      tipPopoverSection
        .focusSection()
      Spacer(minLength: 0)
    }
    .padding(2)
    .panel(id: "presentation-lab")
    .paletteCommand(
      name: "Presentation Lab Sample Action",
      action: {
        lastEvent = "palette command fired"
      }
    )
    .paletteSheet("Presentation commands", isPresented: $showPalette) { commands in
      VStack(alignment: .leading, spacing: 0) {
        ForEach(commands, id: \.name) { command in
          Button(command.name) {
            command.action()
            showPalette = false
          }
        }
        Button("Dismiss Palette") { showPalette = false }
      }
    }
    .alert(
      "Build gate updated",
      isPresented: $showAlert,
      actions: {
        Button("OK") {
          lastEvent = "alert accepted"
          showAlert = false
        }
      },
      message: {
        Text("The example build lane now covers this surface.")
      }
    )
    .confirmationDialog(
      "Reset presentation state?",
      isPresented: $showConfirmation,
      actions: {
        Button("Reset", role: .destructive) {
          lastEvent = "confirmation reset"
          showConfirmation = false
        }
        Button("Cancel") {
          showConfirmation = false
        }
      },
      message: {
        Text("Confirmation dialogs sit near the invoking surface.")
      }
    )
    .sheet("Presentation Sheet", isPresented: $showSheet) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Sheet content").bold()
        Text("Sheets can host arbitrary SwiftTUI views.")
        Button("Close") {
          lastEvent = "sheet closed"
          showSheet = false
        }
      }
      .padding(1)
    }
    .toast("Presentation toast", isPresented: $showToast, duration: 2.0)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var booleanPopoverSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Boolean binding")
      Button(showPopoverDetails ? "Hide Details" : "Show Details") {
        showPopoverDetails.toggle()
      }
      .popover(
        isPresented: $showPopoverDetails,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .trailing
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Details popover")
            .bold()
          Text("Anchored to the trigger.")
          Button("Close Details") {
            showPopoverDetails = false
          }
          .padding(.top, 1)
        }
      }
    }
  }

  private var itemPopoverSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Optional item binding")
      HStack(spacing: 1) {
        ForEach(popoverTools) { tool in
          Button(tool.name) {
            selectedPopoverTool = tool
          }
        }
      }
      .popover(
        item: $selectedPopoverTool,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .bottom
      ) { tool in
        VStack(alignment: .leading, spacing: 0) {
          Text(tool.name)
            .bold()
          Text(tool.detail)
          Button("Done") {
            selectedPopoverTool = nil
          }
          .padding(.top, 1)
        }
      }
    }
  }

  private var tipPopoverSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("TipKit-inspired tip")
      HStack(spacing: 1) {
        Button("Show Tip") {
          showPopoverDemoTip = true
        }
        Text(popoverTipResult)
      }
      .popoverTip(
        LabMirrorDemoTip(),
        isPresented: $showPopoverDemoTip,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .bottom
      ) { action in
        popoverTipResult = "demo acknowledged"
      }
    }
  }
}

private struct LabMirrorPopoverTool: Identifiable, Sendable {
  var id: String
  var name: String
  var detail: String
}

private struct LabMirrorTip: PopoverTip {
  let id = "presentation-lab-tip"

  var title: Text {
    Text("Popover tip")
  }

  var message: Text? {
    Text("Tips use the same source attachment model as popovers.")
  }

  var icon: Text? {
    Text("?")
  }

  var actions: [PopoverTipAction] {
    [
      .init(id: "got-it", title: "Got it")
    ]
  }
}

private struct LabMirrorDemoTip: PopoverTip {
  var id: String { "presentation-lab-demo-tip" }

  var title: Text {
    Text("Try item popovers")
  }

  var message: Text? {
    Text("Open a tool chip to render a popover from an Identifiable binding.")
  }

  var actions: [PopoverTipAction] {
    [
      PopoverTipAction(id: "got-it", title: "Got it")
    ]
  }
}

private struct TipDismissTabFixture: View {
  @State private var selectedTab = "lab"
  @State private var showSheet = false
  @State private var showDemoTip = false
  @State private var tipResult = "no tip action"
  @State private var lastEvent = "none"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Button("Next Tab") {
          selectedTab = selectedTab == "lab" ? "other" : "lab"
        }
        Text("tab=\(selectedTab) sheet=\(showSheet)")
      }

      TabView(selection: $selectedTab) {
        Tab("Lab", value: "lab") {
          labTab
        }

        Tab("Other", value: "other") {
          Text("Other body")
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .panel(id: "tip-dismiss-tab-fixture")
    .keyCommand(
      "Toggle Tab",
      key: .character("t"),
      modifiers: .ctrl,
      action: {
        selectedTab = selectedTab == "lab" ? "other" : "lab"
      }
    )
    .frame(width: 72, height: 24, alignment: .topLeading)
  }

  private var labTab: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Lab body")
      Text("tipPresented \(showDemoTip)")
      Button("Open Sheet") { showSheet = true }
      HStack(spacing: 1) {
        Button("Show Tip") { showDemoTip = true }
        Text(tipResult)
      }
      .popoverTip(
        TipDismissDemoTip(),
        isPresented: $showDemoTip,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .bottom
      ) { action in
        tipResult = "tip \(action.title)"
      }
      Text("Last event: \(lastEvent)")
    }
    .sheet("Lab Sheet", isPresented: $showSheet) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Sheet content")
        Text("Sheets can host arbitrary views.")
        Button("Close Sheet") {
          lastEvent = "sheet closed"
          showSheet = false
        }
      }
      .padding(1)
    }
  }
}

private struct TipDismissFixture: View {
  @State private var showDemoTip = false
  @State private var tipResult = "no tip action"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Lab body")
      Text("tipPresented \(showDemoTip)")
      HStack(spacing: 1) {
        Button("Show Tip") { showDemoTip = true }
        Text(tipResult)
      }
      .popoverTip(
        TipDismissDemoTip(),
        isPresented: $showDemoTip,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .bottom
      ) { action in
        tipResult = "tip \(action.title)"
      }
    }
    .frame(width: 72, height: 24, alignment: .topLeading)
  }
}

private struct TipDismissDemoTip: PopoverTip {
  var id: String { "tip-dismiss-regression-demo-tip" }

  var title: Text {
    Text("Demo tip")
  }

  var message: Text? {
    Text("Mirrors the gallery's presentation-lab demo tip.")
  }

  var actions: [PopoverTipAction] {
    [
      PopoverTipAction(id: "got-it", title: "Got it")
    ]
  }
}

@MainActor
private final class CoexistenceHarness<Content: View> {
  private let terminal: CoexistenceRecordingHost
  let runLoop: SwiftTUIRuntime.RunLoop<Int, Content>
  private var renderedFrames = 0
  private var didShutdown = false

  init(
    rootIdentity: Identity,
    size: CellSize,
    @ViewBuilder content: @escaping () -> Content
  ) throws {
    let terminal = CoexistenceRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: CoexistenceEmptyKeyReader(),
      signalReader: CoexistenceEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in content() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String {
    terminal.frames.last ?? ""
  }

  func shutdown() {
    guard !didShutdown else {
      return
    }
    didShutdown = true
    runLoop.lifecycleCoordinator.shutdown()
  }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return try #require(terminal.frames.last)
  }

  @discardableResult
  func pressKey(_ keyPress: KeyPress) throws -> String {
    #expect(runLoop.handleKeyPress(keyPress) == nil)
    return try render()
  }

  @discardableResult
  func clickText(_ label: String, chooseLast: Bool = false) throws -> String {
    let point = try #require(
      terminal.centerOfText(label, chooseLast: chooseLast),
      "could not find '\(label)' in frame:\n\(frame)"
    )
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil
    )
    return try render()
  }
}

private final class CoexistenceRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(String(rendered.filter { $0 != "\r" }))
    lastPresentedSurface = surface
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(String(output.filter { $0 != "\r" }))
  }

  func centerOfText(_ target: String, chooseLast: Bool = false) -> Point? {
    guard let surface = lastPresentedSurface else {
      return nil
    }

    let rows = chooseLast ? Array(surface.lines.indices.reversed()) : Array(surface.lines.indices)
    for row in rows {
      let line = surface.lines[row]
      let options: String.CompareOptions = chooseLast ? .backwards : []
      guard let range = line.range(of: target, options: options) else {
        continue
      }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

private final class CoexistenceEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class CoexistenceEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
