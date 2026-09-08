@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct NestedPresentationOrderingTests {
  @Test(
    "nested menus paint and receive input above their presenter", arguments: ParentKind.allCases)
  func nestedMenu(kind: ParentKind) throws {
    let probe = NestedPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedPresentation", kind.rawValue),
      size: .init(width: 70, height: 24)
    ) {
      NestedPresentationFixture(kind: kind, probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Parent")
    let trigger = try harness.focusIdentity(forText: "Nested Menu")
    _ = try harness.clickText("Nested Menu")
    #expect(harness.frame.contains("Nested Action"), "\(harness.frame)")
    #expect(entryKinds(harness).suffix(2) == [kind.entryKind, "MenuPresentation"])

    _ = try harness.pressKey(KeyPress(.escape))
    #expect(entryKinds(harness) == [kind.entryKind])
    #expect(!harness.frame.contains("Nested Action"))
    #expect(harness.frame.contains("Nested Menu"))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == trigger)

    _ = try harness.clickText("Nested Menu")
    _ = try harness.clickText("Nested Action")
    #expect(probe.actions == 1)
    #expect(probe.parentActions == 0)
  }

  @Test(
    "a modal opened from a nested menu owns input and restores the menu", arguments: [false, true])
  func modalAboveMenu(selective: Bool) throws {
    let probe = NestedPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedModal"), size: .init(width: 70, height: 24),
      selectiveEvaluation: selective
    ) {
      NestedPresentationFixture(kind: .popover, probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Parent")
    _ = try harness.clickText("Nested Menu")
    let trigger = try harness.focusIdentity(forText: "Present Sheet")
    _ = try harness.clickText("Present Sheet")
    #expect(probe.sheetRequests == 1)
    #expect(harness.frame.contains("Close New Sheet"))
    #expect(
      entryKinds(harness) == ["PopoverPresentation", "MenuPresentation", "SheetPresentation"])
    let close = try harness.focusIdentity(forText: "Close New Sheet")
    let closeRegion = try #require(
      harness.runLoop.focusTracker.focusRegions.first { $0.identity == close })
    #expect(
      harness.runLoop.focusTracker.focusRegions.allSatisfy {
        $0.modalFocusScopePath == closeRegion.modalFocusScopePath
      })
    #expect(!harness.runLoop.focusTracker.focusRegions.contains { $0.identity == trigger })

    _ = try harness.pressKey(KeyPress(.escape))
    #expect(!harness.frame.contains("Close New Sheet"))
    #expect(harness.frame.contains("Nested Action"))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == trigger)
    #expect(probe.dismissals == ["sheet"])
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(!harness.frame.contains("Nested Action"))
    #expect(harness.frame.contains("Nested Menu"))
  }

  @Test("dismissing a modal returns focus to its own trigger", arguments: ParentKind.modalCases)
  func restoresPresenterFocus(kind: ParentKind) throws {
    let probe = NestedPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PresentationFocusReturn", kind.rawValue),
      size: .init(width: 70, height: 24)
    ) {
      NestedPresentationFixture(kind: kind, probe: probe)
    }
    defer { harness.shutdown() }
    let trigger = try harness.focusIdentity(forText: "Open Parent")
    _ = try harness.clickText("Open Parent")
    _ = try harness.clickText("Parent Action")
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(entryKinds(harness).isEmpty)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == trigger)
    #expect(harness.focusModalRestorationStackCount == 0)
  }

  @Test(
    "removing a presenter tears down its nested menu and sheet",
    arguments: [.sheet, .popover] as [ParentKind])
  func removesDescendants(kind: ParentKind) throws {
    let probe = NestedPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PresentationAncestorRemoval", kind.rawValue),
      size: .init(width: 70, height: 24)
    ) {
      NestedPresentationFixture(kind: kind, probe: probe)
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("Open Parent")
    _ = try harness.clickText("Nested Menu")
    _ = try harness.clickText("Present Sheet")
    #expect(entryKinds(harness).count == 3)
    #expect(harness.activeTaskCount == 1)
    let dismissParent = try #require(probe.dismissParent)
    dismissParent()
    _ = try harness.render()
    #expect(entryKinds(harness).isEmpty)
    #expect(!harness.frame.contains("Nested Action"))
    #expect(!harness.frame.contains("Close New Sheet"))
    #expect(harness.activeTaskCount == 0)
    #expect(probe.dismissals == ["sheet"])
    _ = try harness.clickText("Open Parent")
    #expect(entryKinds(harness) == [kind.entryKind])
    #expect(!harness.frame.contains("Nested Action"))
  }

  private func entryKinds<Content: View>(_ harness: StressRuntimeHarness<Content>) -> [String] {
    harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
      .map(\.kindName)
  }
}

enum ParentKind: String, CaseIterable, Sendable {
  case sheet, popover, cover, menu, alert, confirmation

  static let modalCases: [Self] = [.sheet, .popover, .cover, .alert, .confirmation]

  var entryKind: String {
    switch self {
    case .sheet, .cover: "SheetPresentation"
    case .popover: "PopoverPresentation"
    case .menu: "MenuPresentation"
    case .alert: "AlertPresentation"
    case .confirmation: "ConfirmationDialogPresentation"
    }
  }
}

@MainActor
private final class NestedPresentationProbe {
  var actions = 0
  var sheetRequests = 0
  var parentActions = 0
  var dismissals: [String] = []
  var dismissParent: (@MainActor () -> Void)?
}

@MainActor
private struct NestedPresentationFixture: View {
  let kind: ParentKind
  let probe: NestedPresentationProbe
  @State private var showsParent = false

  var body: some View {
    switch kind {
    case .sheet:
      trigger.sheet("Parent Sheet", isPresented: $showsParent) { parentContent }
    case .popover:
      trigger.popover(isPresented: $showsParent) { parentContent }
    case .cover:
      trigger.fullScreenCover(isPresented: $showsParent) { parentContent }
    case .menu:
      Menu("Open Parent") { parentContent }
    case .alert:
      trigger.alert(
        "Parent Alert", isPresented: $showsParent, actions: { parentContent }, message: {})
    case .confirmation:
      trigger.confirmationDialog(
        "Parent Confirmation", isPresented: $showsParent, actions: { parentContent }, message: {})
    }
  }

  private var trigger: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Unrelated") { probe.parentActions += 1 }
      Button("Open Parent") { showsParent = true }
    }
    .onAppear { probe.dismissParent = { showsParent = false } }
  }

  private var parentContent: some View {
    NestedPresentationBody(probe: probe)
  }
}

@MainActor
private struct NestedPresentationBody: View {
  let probe: NestedPresentationProbe
  @State private var showsSheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Parent body")
      Button("Parent Action") { probe.parentActions += 1 }
      Menu("Nested Menu") {
        Button("Nested Action") { probe.actions += 1 }
        Button("Present Sheet") {
          probe.sheetRequests += 1
          showsSheet = true
        }
      }
    }
    .sheet(
      "Newest Sheet", isPresented: $showsSheet,
      onDismiss: { probe.dismissals.append("sheet") }
    ) {
      Button("Close New Sheet") { showsSheet = false }
    }
    .task(id: "nested-presentation-body") { await suspendUntilCancelled() }
  }
}
