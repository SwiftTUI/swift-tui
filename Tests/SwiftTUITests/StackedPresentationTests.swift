import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Stacked presentation", .serialized)
struct StackedPresentationTests {
  @Test("sheet coordinator emits every active item in activation order")
  func sheetCoordinatorEmitsEveryActiveItem() throws {
    let registry = PresentationCoordinatorRegistry()
    registry.sheet.present(
      stackedPromptItem(id: "sheet-a", descriptor: sheetPromptPresentationSpec().descriptor)
    )
    registry.sheet.present(
      stackedPromptItem(
        id: "cover-b",
        descriptor: fullScreenCoverPromptPresentationSpec().descriptor
      )
    )

    let entries = registry.overlayEntries().filter { $0.kindName == "SheetPresentation" }
    let edges = entries.compactMap {
      $0.declarationOwnerEdge(placementRoot: StructuralPath(identity: testIdentity("Portal")))
    }
    let first = try #require(entries.first)
    let last = try #require(entries.last)

    #expect(entries.map { $0.portalEntryID?.token } == ["sheet-a", "cover-b"])
    #expect(first.ordering.activationOrdinal < last.ordering.activationOrdinal)
    #expect(edges.map(\.token) == ["sheet-a", "cover-b"])
  }

  @Test("popover coordinator emits every active item")
  func popoverCoordinatorEmitsEveryActiveItem() {
    let registry = PresentationCoordinatorRegistry()
    registry.popover.present(stackedPopoverItem(id: "popover-a"))
    registry.popover.present(stackedPopoverItem(id: "popover-b"))

    let entries = registry.overlayEntries().filter { $0.kindName == "PopoverPresentation" }

    #expect(entries.map { $0.portalEntryID?.token } == ["popover-a", "popover-b"])
  }

  @Test("menu coordinator emits every active item")
  func menuCoordinatorEmitsEveryActiveItem() {
    let registry = PresentationCoordinatorRegistry()
    registry.menu.present(
      stackedPromptItem(id: "menu-a", descriptor: menuPromptPresentationSpec().descriptor)
    )
    registry.menu.present(
      stackedPromptItem(id: "menu-b", descriptor: menuPromptPresentationSpec().descriptor)
    )

    let entries = registry.overlayEntries().filter { $0.kindName == "MenuPresentation" }

    #expect(entries.map { $0.portalEntryID?.token } == ["menu-a", "menu-b"])
  }

  @Test("alert coordinator exposes the oldest active item as a FIFO queue head")
  func alertCoordinatorExposesOldestActiveItem() {
    let registry = PresentationCoordinatorRegistry()
    registry.alert.present(
      stackedPromptItem(id: "alert-a", descriptor: alertPromptPresentationSpec().descriptor)
    )
    registry.alert.present(
      stackedPromptItem(id: "alert-b", descriptor: alertPromptPresentationSpec().descriptor)
    )

    let entries = registry.overlayEntries().filter { $0.kindName == "AlertPresentation" }

    #expect(entries.map { $0.portalEntryID?.token } == ["alert-a"])
  }

  @Test("confirmation coordinator exposes the oldest active item as a FIFO queue head")
  func confirmationCoordinatorExposesOldestActiveItem() {
    let registry = PresentationCoordinatorRegistry()
    registry.confirmationDialog.present(
      stackedPromptItem(
        id: "confirmation-a",
        descriptor: confirmationDialogPromptPresentationSpec().descriptor
      )
    )
    registry.confirmationDialog.present(
      stackedPromptItem(
        id: "confirmation-b",
        descriptor: confirmationDialogPromptPresentationSpec().descriptor
      )
    )

    let entries = registry.overlayEntries().filter {
      $0.kindName == "ConfirmationDialogPresentation"
    }

    #expect(entries.map { $0.portalEntryID?.token } == ["confirmation-a"])
  }

  @Test("toast coordinator keeps one aggregate overlay entry")
  func toastCoordinatorKeepsOneAggregateEntry() {
    let registry = PresentationCoordinatorRegistry()
    registry.toast.present(stackedToastItem(id: "toast-a"))
    registry.toast.present(stackedToastItem(id: "toast-b"))

    let entries = registry.overlayEntries().filter { $0.kindName == "ToastPresentation" }

    #expect(entries.count == 1)
  }

  @Test("Escape uses recency among visible entries and ignores a queued alert")
  func escapeUsesVisibleEntryRecency() {
    let registry = PresentationCoordinatorRegistry()
    var dismissals: [String] = []
    registry.alert.present(
      stackedPromptItem(
        id: "alert-a",
        descriptor: alertPromptPresentationSpec().descriptor,
        dismiss: { dismissals.append("alert-a") }
      )
    )
    registry.sheet.present(
      stackedPromptItem(
        id: "sheet-b",
        descriptor: sheetPromptPresentationSpec().descriptor,
        dismiss: { dismissals.append("sheet-b") }
      )
    )
    registry.alert.present(
      stackedPromptItem(
        id: "alert-c",
        descriptor: alertPromptPresentationSpec().descriptor,
        dismiss: { dismissals.append("alert-c") }
      )
    )

    registry.dismissStack().topmostEscapeDismissAction()?()

    #expect(dismissals == ["sheet-b"])
  }

  @Test("covered sheet state and task ownership survive a newer sheet")
  func coveredSheetStateAndTaskSurviveNewerSheet() throws {
    let probe = StackedPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StackedSheetContinuity"),
      size: .init(width: 54, height: 14)
    ) {
      StackedSheetContinuityFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Sheet A")
    _ = try harness.clickText("Increment Sheet A")
    _ = try harness.clickText("Open Sheet B")

    #expect(stackedPresentationEntryCount(in: harness, kind: "SheetPresentation") == 2)
    #expect(harness.activeTaskCount == 1)
    #expect(probe.events.isEmpty)

    let revealed = try harness.pressKey(KeyPress(.escape))

    #expect(revealed.contains("sheet A local 1"))
    #expect(harness.activeTaskCount == 1)
    #expect(probe.events == ["sheet B dismissed"])
  }

  @Test("removing a covered sheet tears down only that entry")
  func removingCoveredSheetTearsDownOnlyThatEntry() throws {
    let probe = StackedPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StackedSheetRemoval"),
      size: .init(width: 54, height: 14)
    ) {
      StackedSheetRemovalFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Sheet A")
    _ = try harness.clickText("Open Sheet B")

    #expect(probe.events.isEmpty)

    let frame = try harness.clickText("Remove Sheet A")

    #expect(frame.contains("sheet B body"))
    #expect(stackedPresentationEntryCount(in: harness, kind: "SheetPresentation") == 1)
    #expect(probe.events == ["sheet A dismissed"])

    _ = try harness.pressKey(KeyPress(.escape))
    #expect(probe.events == ["sheet A dismissed", "sheet B dismissed"])
  }

  @Test("alerts queue without mutating the waiting binding or firing its callback")
  func alertsQueueWithIndependentBindingsAndCallbacks() throws {
    let probe = StackedPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StackedAlertQueue"),
      size: .init(width: 56, height: 16)
    ) {
      StackedAlertQueueFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Alert A")
    let queued = try harness.clickText("Queue Alert B", chooseLast: true)

    #expect(queued.contains("Alert A"))
    #expect(queued.contains("first queued alert"))
    #expect(!queued.contains("second queued alert"))
    #expect(probe.events.isEmpty)

    let revealed = try harness.clickText("Dismiss Alert A", chooseLast: true)

    #expect(revealed.contains("Alert B"))
    #expect(probe.events == ["alert A dismissed"])

    let closed = try harness.clickText("Dismiss Alert B", chooseLast: true)

    #expect(closed.contains("alerts false false"))
    #expect(probe.events == ["alert A dismissed", "alert B dismissed"])
  }
}

@MainActor
private final class StackedPresentationProbe {
  var events: [String] = []
}

@MainActor
private struct StackedSheetContinuityFixture: View {
  let probe: StackedPresentationProbe
  @State private var showsSheetA = false
  @State private var showsSheetB = false

  var body: some View {
    Button("Open Sheet A") { showsSheetA = true }
      .sheet(
        "Sheet A",
        isPresented: $showsSheetA,
        onDismiss: { probe.events.append("sheet A dismissed") }
      ) {
        StackedFirstSheetBody(showsSheetB: $showsSheetB)
      }
      .sheet(
        "Sheet B",
        isPresented: $showsSheetB,
        onDismiss: { probe.events.append("sheet B dismissed") }
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("sheet B body")
          Button("Close Sheet B") { showsSheetB = false }
        }
      }
  }
}

@MainActor
private struct StackedFirstSheetBody: View {
  var showsSheetB: Binding<Bool>
  @State private var localCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("sheet A local \(localCount)")
      Button("Increment Sheet A") { localCount += 1 }
      Button("Open Sheet B") { showsSheetB.wrappedValue = true }
    }
    .task(id: "stacked-sheet-a-task") {
      while !Task.isCancelled {
        await Task.yield()
      }
    }
  }
}

@MainActor
private struct StackedSheetRemovalFixture: View {
  let probe: StackedPresentationProbe
  @State private var showsSheetA = false
  @State private var showsSheetB = false

  var body: some View {
    Button("Open Sheet A") { showsSheetA = true }
      .sheet(
        "Sheet A",
        isPresented: $showsSheetA,
        onDismiss: { probe.events.append("sheet A dismissed") }
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("sheet A body")
          Button("Open Sheet B") { showsSheetB = true }
        }
      }
      .sheet(
        "Sheet B",
        isPresented: $showsSheetB,
        onDismiss: { probe.events.append("sheet B dismissed") }
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("sheet B body")
          Button("Remove Sheet A") { showsSheetA = false }
        }
      }
  }
}

@MainActor
private struct StackedAlertQueueFixture: View {
  let probe: StackedPresentationProbe
  @State private var showsAlertA = false
  @State private var showsAlertB = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Open Alert A") { showsAlertA = true }
      Text("alerts \(showsAlertA) \(showsAlertB)")
    }
    .alert(
      "Alert A",
      isPresented: $showsAlertA,
      onDismiss: { probe.events.append("alert A dismissed") },
      actions: {
        Button("Queue Alert B") { showsAlertB = true }
        Button("Dismiss Alert A") { showsAlertA = false }
      },
      message: {
        Text("first queued alert")
      }
    )
    .alert(
      "Alert B",
      isPresented: $showsAlertB,
      onDismiss: { probe.events.append("alert B dismissed") },
      actions: {
        Button("Dismiss Alert B") { showsAlertB = false }
      },
      message: {
        Text("second queued alert")
      }
    )
  }
}

@MainActor
private func stackedPromptItem(
  id: String,
  descriptor: PromptPresentationDescriptor,
  dismiss: @escaping @MainActor @Sendable () -> Void = {}
) -> PromptPresentationItem {
  PromptPresentationItem(
    id: id,
    title: id,
    descriptor: descriptor,
    actionPayloads: [],
    messagePayloads: [],
    contentPayloads: [],
    dismiss: dismiss
  )
}

@MainActor
private func stackedPopoverItem(
  id: String
) -> PopoverPresentationItem {
  let surfaceItem = stackedPromptItem(
    id: id,
    descriptor: sheetPromptPresentationSpec().descriptor
  )
  return PopoverPresentationItem(
    id: id,
    sourceIdentity: testIdentity("StackedPopover", id),
    attachmentAnchor: .rect(.bounds),
    arrowEdge: .top,
    modalPolicy: .disablesBaseInteraction,
    surfaceItem: surfaceItem
  )
}

@MainActor
private func stackedToastItem(
  id: String
) -> ToastPresentationItem {
  ToastPresentationItem(
    id: id,
    contentPayloads: [],
    presentation: InfoToastStyle().resolvePresentation(for: ToastStyleConfiguration()),
    duration: nil,
    dismiss: {}
  )
}

@MainActor
private func stackedPresentationEntryCount<Content: View>(
  in harness: StressRuntimeHarness<Content>,
  kind: String
) -> Int {
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .filter { $0.kindName == kind }
    .count
}
