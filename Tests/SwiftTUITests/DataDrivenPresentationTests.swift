@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Data-driven presentation", .serialized)
struct DataDrivenPresentationTests {
  @Test("approved Stage 1 presentation signatures compile")
  func approvedStage1PresentationSignaturesCompile() {
    let presented = Binding<Bool>.constant(false)
    let item = Binding<DataDrivenPresentationItem?>.constant(nil)
    let tip = DataDrivenPresentationTip(id: "shortcut", title: "Shortcut")

    _ = Text("Root").sheet(isPresented: presented, onDismiss: {}) {
      Text("Sheet")
    }
    _ = Text("Root").sheet("Inspector", isPresented: presented, onDismiss: {}) {
      Text("Sheet")
    }
    _ = Text("Root").sheet(item: item, onDismiss: {}) { current in
      Text(current.title)
    }
    _ = Text("Root").sheet("Inspector", item: item, onDismiss: {}) { current in
      Text(current.title)
    }

    _ = Text("Root").alert("Alert", isPresented: presented, onDismiss: {})
    _ = Text("Root").alert(
      "Alert",
      isPresented: presented,
      onDismiss: {},
      actions: { Text("Action") },
      message: { Text("Message") }
    )
    _ = Text("Root").alert("Alert", item: item, onDismiss: {})
    _ = Text("Root").alert(
      "Alert",
      item: item,
      onDismiss: {},
      actions: { current in Text("Action \(current.title)") },
      message: { current in Text("Message \(current.title)") }
    )

    _ = Text("Root").confirmationDialog(
      "Confirm",
      isPresented: presented,
      onDismiss: {}
    )
    _ = Text("Root").confirmationDialog(
      "Confirm",
      isPresented: presented,
      onDismiss: {},
      actions: { Text("Action") },
      message: { Text("Message") }
    )
    _ = Text("Root").confirmationDialog("Confirm", item: item, onDismiss: {})
    _ = Text("Root").confirmationDialog(
      "Confirm",
      item: item,
      onDismiss: {},
      actions: { current in Text("Action \(current.title)") },
      message: { current in Text("Message \(current.title)") }
    )

    _ = Text("Root").fullScreenCover(isPresented: presented, onDismiss: {}) {
      Text("Cover")
    }
    _ = Text("Root").fullScreenCover(item: item, onDismiss: {}) { current in
      Text(current.title)
    }
    _ = Text("Root").popover(isPresented: presented, onDismiss: {}) {
      Text("Popover")
    }
    _ = Text("Root").popover(item: item, onDismiss: {}) { current in
      Text(current.title)
    }
    _ = Text("Root").popoverTip(tip, isPresented: presented, onDismiss: {})
    _ = Text("Root").toast(
      "Toast",
      isPresented: presented,
      duration: nil,
      onDismiss: {}
    )
    _ = Text("Root").toast(
      isPresented: presented,
      duration: nil,
      onDismiss: {}
    ) {
      Text("Toast")
    }
    _ = Panel(id: "data-driven-palette") { Text("Root") }
      .paletteSheet("Palette", isPresented: presented, onDismiss: {}) { _ in
        Text("Palette")
      }
  }

  @Test("sheet item content receives the current bound value")
  func sheetItemContentReceivesCurrentValue() {
    let current = DataDrivenPresentationItem(id: "settings", title: "Settings")
    let artifacts = DefaultRenderer().render(
      Text("Root")
        .sheet(item: .constant(current)) { item in
          Text("Sheet \(item.title)")
        }
        .frame(width: 42, height: 10, alignment: .topLeading),
      context: .init(identity: testIdentity("DataDrivenSheetItem")),
      proposal: .init(width: 42, height: 10)
    )

    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Sheet Settings"))
  }

  @Test("alert and dialog item builders receive the current bound value")
  func promptItemBuildersReceiveCurrentValue() {
    let current = DataDrivenPresentationItem(id: "archive", title: "Archive")
    let alert = DefaultRenderer().render(
      Text("Root")
        .alert(
          "Alert",
          item: .constant(current),
          actions: { item in Text("Run \(item.title)") },
          message: { item in Text("About \(item.title)") }
        )
        .frame(width: 42, height: 10, alignment: .topLeading),
      context: .init(identity: testIdentity("DataDrivenAlertItem")),
      proposal: .init(width: 42, height: 10)
    )
    let dialog = DefaultRenderer().render(
      Text("Root")
        .confirmationDialog(
          "Dialog",
          item: .constant(current),
          actions: { item in Text("Run \(item.title)") },
          message: { item in Text("About \(item.title)") }
        )
        .frame(width: 42, height: 10, alignment: .topLeading),
      context: .init(identity: testIdentity("DataDrivenDialogItem")),
      proposal: .init(width: 42, height: 10)
    )

    let alertSurface = alert.rasterSurface.lines.joined(separator: "\n")
    let dialogSurface = dialog.rasterSurface.lines.joined(separator: "\n")
    #expect(alertSurface.contains("Run Archive"))
    #expect(alertSurface.contains("About Archive"))
    #expect(dialogSurface.contains("Run Archive"))
    #expect(dialogSurface.contains("About Archive"))
  }

  @Test("inactive presentation does not call onDismiss")
  func inactivePresentationDoesNotCallOnDismiss() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenInactiveDismiss"),
      size: .init(width: 44, height: 10)
    ) {
      DataDrivenInactiveFixture(probe: probe)
    }
    defer { harness.shutdown() }

    #expect(probe.events.isEmpty)
    #expect(!harness.frame.contains("Inactive sheet"))
  }

  @Test("Escape clears an item source and calls onDismiss once after teardown")
  func escapeClearsItemAndCallsOnDismissOnce() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenItemEscape"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenItemEscapeFixture(probe: probe)
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Present Settings")
    #expect(frame.contains("Current item Settings"))
    #expect(probe.events.isEmpty)

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("item nil"))
    #expect(!frame.contains("Current item Settings"))
    #expect(probe.events == ["item dismissed"])
  }

  @Test("direct Boolean mutation calls onDismiss once after teardown")
  func directBooleanMutationCallsOnDismissOnce() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenDirectMutation"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenDirectMutationFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present Boolean Sheet")
    let frame = try harness.clickText("Clear Boolean Source")

    #expect(!frame.contains("Clear Boolean Source"))
    #expect(probe.events == ["boolean dismissed"])
  }

  @Test("same item ID refreshes content and state without dismissal")
  func sameItemIDRefreshesWithoutDismissal() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenSameID"),
      size: .init(width: 52, height: 14)
    ) {
      DataDrivenItemReplacementFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present First Item")
    _ = try harness.clickText("Increment Local Count")
    let frame = try harness.clickText("Refresh Same Item")

    #expect(frame.contains("value refreshed"))
    #expect(frame.contains("local count 1"))
    #expect(probe.events.isEmpty)
  }

  @Test("new item ID tears down once and mounts a fresh activation")
  func newItemIDTearsDownAndMountsFreshActivation() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenNewID"),
      size: .init(width: 52, height: 14)
    ) {
      DataDrivenItemReplacementFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present First Item")
    _ = try harness.clickText("Increment Local Count")
    let replaced = try harness.clickText("Replace Item ID")

    #expect(replaced.contains("value second"))
    #expect(replaced.contains("local count 0"))
    #expect(probe.events == ["item activation dismissed"])

    _ = try harness.pressKey(KeyPress(.escape))
    #expect(probe.events == ["item activation dismissed", "item activation dismissed"])
  }

  @Test("removing the presenting subtree calls onDismiss once")
  func removingPresentingSubtreeCallsOnDismissOnce() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenSourceRemoval"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenSourceRemovalFixture(probe: probe)
    }
    defer { harness.shutdown() }

    let frame = try harness.clickText("Remove Presenter")

    #expect(frame.contains("presenter removed"))
    #expect(probe.events == ["source removed"])
  }

  @Test("onDismiss mutates the original presenter state owner")
  func onDismissMutatesOriginalPresenterStateOwner() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenDismissOwner"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenDismissOwnerFixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present Owner Sheet")
    let frame = try harness.pressKey(KeyPress(.escape))

    #expect(frame.contains("dismiss count 1"))
  }

  @Test("full-screen cover fills the viewport without sheet chrome")
  func fullScreenCoverFillsViewportWithoutSheetChrome() {
    let baseIdentity = testIdentity("DataDrivenCoverBase")
    let coverIdentity = testIdentity("DataDrivenCoverContent")
    let artifacts = DefaultRenderer().render(
      Button("Base") {}
        .id(baseIdentity)
        .fullScreenCover(isPresented: .constant(true)) {
          Button("Full-screen body") {}
            .id(coverIdentity)
        },
      context: .init(identity: testIdentity("DataDrivenCover")),
      proposal: .init(width: 40, height: 10)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let focusPaths = artifacts.semanticSnapshot.focusRegions.map { $0.identity.path }
    #expect(surface.contains("Full-screen body"))
    #expect(!surface.contains("×"))
    #expect(!surface.contains("┌"))
    #expect(!focusPaths.contains(baseIdentity.path))
    #expect(focusPaths.contains(coverIdentity.path))
    #expect(dataDrivenViewKindNames(in: artifacts.resolvedTree).contains("SheetPresentation"))
  }

  @Test("popover teardown uses the shared onDismiss contract")
  func popoverTeardownUsesSharedContract() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenPopoverDismiss"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenPopoverFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present Popover")
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(probe.events == ["popover dismissed"])
  }

  @Test("palette sheet teardown uses the shared onDismiss contract")
  func paletteSheetTeardownUsesSharedContract() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenPaletteDismiss"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenPaletteFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present Palette")
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(probe.events == ["palette dismissed"])
  }

  @Test("default alert dismissal clears the item source and calls onDismiss once")
  func defaultAlertDismissalClearsItemSource() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenAlertDefaultDismiss"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenDefaultAlertFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present Item Alert")
    let frame = try harness.clickText("Dismiss")

    #expect(frame.contains("alert item nil"))
    #expect(probe.events == ["alert dismissed"])
  }

  @Test("full-screen cover dismisses through Escape and observes teardown")
  func fullScreenCoverDismissesThroughEscape() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenCoverEscape"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenFullScreenFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present Full Screen")
    let frame = try harness.pressKey(KeyPress(.escape))

    #expect(frame.contains("cover hidden"))
    #expect(probe.events == ["cover dismissed"])
  }

  @Test("popover tip teardown uses the shared onDismiss contract")
  func popoverTipTeardownUsesSharedContract() throws {
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenTipDismiss"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenTipFixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Present Tip")
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(probe.events == ["tip dismissed"])
  }

  @Test("toast auto-expiration observes committed teardown once")
  func toastAutoExpirationObservesCommittedTeardown() async throws {
    let presented = DataDrivenBooleanSource(true)
    let probe = DataDrivenPresentationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DataDrivenToastDismiss"),
      size: .init(width: 48, height: 12)
    ) {
      DataDrivenToastFixture(presented: presented, probe: probe)
    }
    defer { harness.shutdown() }

    await presented.changes.wait {
      !presented.value
    }
    _ = try harness.render()

    #expect(!harness.frame.contains("Auto toast"))
    #expect(probe.events == ["toast dismissed"])
  }
}

private struct DataDrivenPresentationItem: Identifiable, Sendable {
  var id: String
  var title: String
}

private struct DataDrivenPresentationTip: PopoverTip {
  var id: String
  var title: Text

  @MainActor
  init(id: String, title: String) {
    self.id = id
    self.title = Text(title)
  }
}

@MainActor
private final class DataDrivenPresentationProbe {
  var events: [String] = []
}

@MainActor
private final class DataDrivenBooleanSource {
  var value: Bool
  let changes = MainActorConditionSignal()

  init(_ value: Bool) {
    self.value = value
  }

  func binding() -> Binding<Bool> {
    Binding(
      get: { self.value },
      set: { value in
        self.value = value
        self.changes.notify()
      }
    )
  }
}

@MainActor
private struct DataDrivenInactiveFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var presented = false

  var body: some View {
    Text("Inactive root")
      .sheet(isPresented: $presented, onDismiss: { probe.events.append("unexpected") }) {
        Text("Inactive sheet")
      }
  }
}

@MainActor
private struct DataDrivenItemEscapeFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var item: DataDrivenPresentationItem?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Present Settings") {
        item = DataDrivenPresentationItem(id: "settings", title: "Settings")
      }
      Text(item == nil ? "item nil" : "item active")
    }
    .sheet(item: $item, onDismiss: { probe.events.append("item dismissed") }) { current in
      Text("Current item \(current.title)")
    }
  }
}

@MainActor
private struct DataDrivenDirectMutationFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var presented = false

  var body: some View {
    Button("Present Boolean Sheet") { presented = true }
      .sheet(
        isPresented: $presented,
        onDismiss: { probe.events.append("boolean dismissed") }
      ) {
        Button("Clear Boolean Source") { presented = false }
      }
  }
}

@MainActor
private struct DataDrivenItemReplacementFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var item: DataDrivenPresentationItem?

  var body: some View {
    Button("Present First Item") {
      item = DataDrivenPresentationItem(id: "first", title: "first")
    }
    .sheet(
      item: $item,
      onDismiss: { probe.events.append("item activation dismissed") }
    ) { current in
      DataDrivenItemReplacementContent(current: current, item: $item)
    }
  }
}

@MainActor
private struct DataDrivenItemReplacementContent: View {
  var current: DataDrivenPresentationItem
  var item: Binding<DataDrivenPresentationItem?>
  @State private var localCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("value \(current.title)")
      Text("local count \(localCount)")
      Button("Increment Local Count") { localCount += 1 }
      Button("Refresh Same Item") {
        item.wrappedValue = DataDrivenPresentationItem(id: "first", title: "refreshed")
      }
      Button("Replace Item ID") {
        item.wrappedValue = DataDrivenPresentationItem(id: "second", title: "second")
      }
    }
  }
}

@MainActor
private struct DataDrivenSourceRemovalFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var showsPresenter = true

  var body: some View {
    if showsPresenter {
      Text("Presenter")
        .sheet(isPresented: .constant(true), onDismiss: { probe.events.append("source removed") }) {
          Button("Remove Presenter") { showsPresenter = false }
        }
    } else {
      Text("presenter removed")
    }
  }
}

@MainActor
private struct DataDrivenDismissOwnerFixture: View {
  @State private var presented = false
  @State private var dismissCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Present Owner Sheet") { presented = true }
      Text("dismiss count \(dismissCount)")
    }
    .sheet(isPresented: $presented, onDismiss: { dismissCount += 1 }) {
      Text("Owner sheet")
    }
  }
}

@MainActor
private struct DataDrivenPopoverFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var presented = false

  var body: some View {
    Button("Present Popover") { presented = true }
      .popover(isPresented: $presented, onDismiss: { probe.events.append("popover dismissed") }) {
        Text("Popover body")
      }
  }
}

@MainActor
private struct DataDrivenPaletteFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var presented = false

  var body: some View {
    Button("Present Palette") { presented = true }
      .panel(id: "data-driven-palette-fixture")
      .paletteSheet(
        "Palette",
        isPresented: $presented,
        onDismiss: { probe.events.append("palette dismissed") }
      ) { _ in
        Text("Palette body")
      }
  }
}

@MainActor
private struct DataDrivenDefaultAlertFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var item: DataDrivenPresentationItem?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Present Item Alert") {
        item = DataDrivenPresentationItem(id: "alert", title: "Alert")
      }
      Text(item == nil ? "alert item nil" : "alert item active")
    }
    .alert("Item Alert", item: $item, onDismiss: { probe.events.append("alert dismissed") })
  }
}

@MainActor
private struct DataDrivenFullScreenFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var presented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Present Full Screen") { presented = true }
      Text(presented ? "cover active" : "cover hidden")
    }
    .fullScreenCover(
      isPresented: $presented,
      onDismiss: { probe.events.append("cover dismissed") }
    ) {
      Text("Cover body")
    }
  }
}

@MainActor
private struct DataDrivenTipFixture: View {
  let probe: DataDrivenPresentationProbe
  @State private var presented = false

  var body: some View {
    Button("Present Tip") { presented = true }
      .popoverTip(
        DataDrivenPresentationTip(id: "tip", title: "Tip body"),
        isPresented: $presented,
        onDismiss: { probe.events.append("tip dismissed") }
      )
  }
}

@MainActor
private struct DataDrivenToastFixture: View {
  let presented: DataDrivenBooleanSource
  let probe: DataDrivenPresentationProbe

  var body: some View {
    Text("Toast root")
      .toast(
        "Auto toast",
        isPresented: presented.binding(),
        duration: 0.02,
        onDismiss: { probe.events.append("toast dismissed") }
      )
  }
}

private func dataDrivenViewKindNames(
  in node: ResolvedNode
) -> [String] {
  let current: [String]
  if case .view(let name) = node.kind {
    current = [name]
  } else {
    current = []
  }
  return current + node.children.flatMap { dataDrivenViewKindNames(in: $0) }
}
