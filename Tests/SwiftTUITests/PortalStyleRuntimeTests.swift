import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct PortalStyleRuntimeTests {
  @Test(
    "custom portal styles preserve actions, focus, dismissal, and lifetime",
    arguments: PortalTestFamily.allCases, 0..<4)
  func interaction(family: PortalTestFamily, mode: Int) throws {
    let itemBased = mode & 1 != 0
    let selective = mode & 2 != 0
    let probe = PortalJourneyProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 60, height: 24),
      selectiveEvaluation: selective
    ) { PortalStyleJourney(family: family, itemBased: itemBased, probe: probe) }
    defer { harness.shutdown() }
    for cycle in 1...2 {
      _ = try harness.clickText("Open portal")
      #expect(harness.frame.contains("Presented body"))
      #expect(
        !harness.runLoop.focusTracker.focusRegions.contains { $0.identity == portalLauncherID })
      #expect(harness.runLoop.focusTracker.focusRegions.contains { $0.identity == portalRunID })
      _ = try harness.clickText("Run action")
      #expect(probe.activations == cycle)
      _ = try harness.pressKey(KeyPress(.escape))
      #expect(!harness.frame.contains("Presented body"))
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == portalLauncherID)
      #expect(!harness.runLoop.localActionRegistry.hasHandler(identity: portalRunID))
      #expect(probe.dismissals == cycle)
      #expect(probe.appearances == cycle)
      #expect(probe.disappearances == cycle)
    }
  }

  @Test(
    "invalid portal presentations report and use the automatic baseline",
    arguments: [PortalTestFamily.alert, .confirmation, .sheet, .cover, .popover])
  func invalidPresentations(family: PortalTestFamily) {
    let baseline = portalStyleFrame(family: family, invalid: false)
    let invalid = portalStyleFrame(family: family, invalid: true)
    let equal = baseline.rasterSurface == invalid.rasterSurface
    #expect(equal)
    let issues = invalid.diagnostics.runtime.issues.filter {
      $0.code == "style.invalidPresentation"
    }
    #expect(issues.count == 1)
  }
}

enum PortalTestFamily: CaseIterable { case alert, confirmation, sheet, dropdown, cover, popover }

private let portalLauncherID = testIdentity("PortalLauncher")
private let portalRunID = testIdentity("PortalRun")

@MainActor
private final class PortalJourneyProbe {
  var activations = 0
  var dismissals = 0
  var appearances = 0
  var disappearances = 0
}

private struct PortalStyleJourney: View {
  let family: PortalTestFamily
  let itemBased: Bool
  let probe: PortalJourneyProbe
  @State private var presented = false
  @State private var item: Item?
  struct Item: Identifiable, Sendable { let id = 1 }

  var body: some View {
    declaration
      .promptStyle(ConsumerPromptStyle())
      .fullScreenCoverStyle(ConsumerFullScreenCoverStyle())
      .popoverStyle(ConsumerPopoverStyle())
      .sheetStyle(ConsumerPortalSheetStyle(dropdown: family == .dropdown))
  }

  private var launcher: some View {
    Button("Open portal") {
      if itemBased { item = Item() } else { presented = true }
    }.id(portalLauncherID)
  }

  private func dismiss() { probe.dismissals += 1 }
  private func message() -> some View {
    Text("Presented body")
      .onAppear { probe.appearances += 1 }
      .onDisappear { probe.disappearances += 1 }
  }
  private func action() -> some View {
    Button("Run action") { probe.activations += 1 }.id(portalRunID)
  }
  private func content() -> some View {
    VStack(alignment: .leading, spacing: 0) {
      message()
      action()
    }
  }

  @ViewBuilder private var declaration: some View {
    switch family {
    case .alert:
      if itemBased {
        launcher.alert(
          "Title", item: $item, onDismiss: dismiss, actions: { _ in action() },
          message: { _ in message() })
      } else {
        launcher.alert(
          "Title", isPresented: $presented, onDismiss: dismiss, actions: action, message: message)
      }
    case .confirmation:
      if itemBased {
        launcher.confirmationDialog(
          "Title", item: $item, onDismiss: dismiss, actions: { _ in action() },
          message: { _ in message() })
      } else {
        launcher.confirmationDialog(
          "Title", isPresented: $presented, onDismiss: dismiss, actions: action, message: message)
      }
    case .sheet, .dropdown:
      if itemBased {
        launcher.sheet("Title", item: $item, onDismiss: dismiss, content: { _ in content() })
      } else {
        launcher.sheet("Title", isPresented: $presented, onDismiss: dismiss, content: content)
      }
    case .cover:
      if itemBased {
        launcher.fullScreenCover(item: $item, onDismiss: dismiss, content: { _ in content() })
      } else {
        launcher.fullScreenCover(isPresented: $presented, onDismiss: dismiss, content: content)
      }
    case .popover:
      if itemBased {
        launcher.popover(item: $item, onDismiss: dismiss, content: { _ in content() })
      } else {
        launcher.popover(isPresented: $presented, onDismiss: dismiss, content: content)
      }
    }
  }
}

@MainActor
private func portalStyleFrame(family: PortalTestFamily, invalid: Bool) -> RenderSnapshot {
  DefaultRenderer().render(
    InvalidPortalStyleFixture(family: family, invalid: invalid),
    context: .init(identity: testIdentity("Root")), proposal: .init(width: 50, height: 20))
}

private struct InvalidPortalStyleFixture: View {
  let family: PortalTestFamily
  let invalid: Bool
  @ViewBuilder var body: some View {
    switch family {
    case .alert:
      Text("Base").alert("Title", isPresented: .constant(true))
        .promptStyle(InvalidPortalStyle(invalid: invalid))
    case .confirmation:
      Text("Base").confirmationDialog("Title", isPresented: .constant(true))
        .promptStyle(InvalidPortalStyle(invalid: invalid))
    case .sheet, .dropdown:
      Text("Base").sheet("Title", isPresented: .constant(true)) { Text("Body") }
        .sheetStyle(InvalidPortalStyle(invalid: invalid))
    case .cover:
      Text("Base").fullScreenCover(isPresented: .constant(true)) { Text("Body") }
        .fullScreenCoverStyle(InvalidPortalStyle(invalid: invalid))
    case .popover:
      Text("Base").popover(isPresented: .constant(true)) { Text("Body") }
        .popoverStyle(InvalidPortalStyle(invalid: invalid))
    }
  }
}

private struct InvalidPortalStyle: PromptStyle, SheetStyle, FullScreenCoverStyle, PopoverStyle {
  let invalid: Bool
  var snapshotLabel: String { "invalid-fixture" }
  func resolvePresentation(for configuration: PromptStyleConfiguration)
    -> PromptSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    if invalid { presentation.backdropOpacity = .infinity }
    return presentation
  }
  func resolvePresentation(for configuration: SheetStyleConfiguration)
    -> SheetSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    if invalid { presentation.scrollIdealHeight = -1 }
    return presentation
  }
  func resolvePresentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    if invalid { presentation.contentInsets.leading = -1 }
    return presentation
  }
  func resolvePresentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    if invalid { presentation.maximumWidth = -1 }
    return presentation
  }
}
