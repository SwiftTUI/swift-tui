import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The toolbar strip is reconciled in the late-preference stage from the
/// content's `.toolbarItem` contributions, so it re-resolves FRESH whenever the
/// item set changes — outside any dirty plan. When the change is driven by a
/// state read below the scope (a frontier-scoped `.subtrees` publication whose
/// roots never cover `…/toolbar-strip`), the host's graph node kept applying
/// last frame's strip: the departed item's nodes stayed live, its action
/// registration stayed in the live registry — the scoped reset never reached
/// the strip, a full rebuild from node records no longer carried it, and the
/// registration-publication oracle tripped on every later sampled frame
/// (`action|…/toolbar-strip/base/content/Layout[0]/Layout[1] live=1 rebuilt=0`,
/// the gallery's task-progress "Restart demo" item after leaving that tab) —
/// and the presented strip lagged until some later root frame. The reconcile
/// now schedules a follow-up frame rooted at the host, which re-applies the
/// strip through the normal plan.
@MainActor
@Suite(.serialized)
struct ToolbarStripPublicationTests {
  @Test("a toolbar item that departs under a frontier-scoped publication leaves the live registry")
  func departedToolbarItemLeavesLiveRegistry() throws {
    let size = CellSize(width: 48, height: 12)
    let rootIdentity = testIdentity("ToolbarStripShrinkRoot")
    var environment = EnvironmentValues()
    environment.terminalSize = size

    // Throwaway render: locate the toggle button and the strip item identities.
    let initial = DefaultRenderer().render(
      ToolbarStripShrinkRoot(),
      context: .init(identity: rootIdentity, environmentValues: environment),
      proposal: .init(width: size.width, height: size.height)
    )
    let toggleButton = try #require(
      initial.semanticSnapshot.accessibilityNodes.first { node in
        node.role == .button && !node.identity.path.contains("toolbar-strip")
      },
      "could not find the content toggle button in the initial render"
    )
    let extraItem = try #require(
      initial.semanticSnapshot.accessibilityNodes.first { node in
        node.role == .button && node.label == "Extra"
      },
      "expected the Extra toolbar item in the initial render"
    )
    let stableItem = try #require(
      initial.semanticSnapshot.accessibilityNodes.first { node in
        node.role == .button && node.label == "Stable"
      }
    )

    let host = ToolbarStripRecordingHost(size: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: ToolbarStripScriptedInput(),
      signalReader: ToolbarStripEmptySignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in ToolbarStripShrinkRoot() }
    )
    focusTracker.invalidator = scheduler

    func render() throws {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    try render()
    #expect(runLoop.localActionRegistry.hasHandler(identity: stableItem.identity))
    #expect(runLoop.localActionRegistry.hasHandler(identity: extraItem.identity))
    // The interactive run loop turns selective evaluation on after its first
    // full frame; the synchronous harness must opt in the same way, or every
    // later frame publishes `.all` and the scoped-restore path under test is
    // never taken.
    runLoop.renderer.enableSelectiveEvaluation()
    // Let default focus settle (the first focusable takes focus one frame
    // after the initial render); a focus change on the shrink frame itself
    // would force root evaluation and hide the scoped-publication path.
    for _ in 0..<2 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }

    // The toggle's `@State` write lives BELOW the root, so the shrink frame
    // publishes with a frontier-scoped plan that does not cover the strip.
    // Dispatch the action directly rather than clicking: a pointer click also
    // moves focus, and a focus change forces root evaluation — a full
    // publication that would cover the strip and mask the defect. Likewise,
    // do not request a root invalidation here.
    #expect(runLoop.localActionRegistry.dispatch(identity: toggleButton.identity))
    let violationsBefore = SoundnessProbeConfiguration.registrationPublicationViolationCount
    try render()
    try render()

    let surface = try #require(host.lastPresentedSurface).lines.joined(separator: "\n")
    #expect(surface.contains("Stable"), "strip surface:\n\(surface)")
    #expect(!surface.contains("Extra"), "the Extra item should have departed:\n\(surface)")
    #expect(runLoop.localActionRegistry.hasHandler(identity: stableItem.identity))
    #expect(
      !runLoop.localActionRegistry.hasHandler(identity: extraItem.identity),
      "the departed toolbar item's action is still published in the live registry"
    )
    let violationDetail =
      SoundnessProbeConfiguration.lastViolationDetailByKind["registration-publication"] ?? ""
    #expect(
      SoundnessProbeConfiguration.registrationPublicationViolationCount == violationsBefore,
      "registration-publication oracle tripped: \(violationDetail)"
    )
  }
}

private struct ToolbarStripShrinkRoot: View {
  var body: some View {
    // A stable root above the state-owning host: the toggle's write
    // invalidates the host subtree, not the root, so the shrink frame's
    // publication is frontier-scoped rather than a flat `.all` rebuild.
    VStack(spacing: 0) {
      Text("root")
      ToolbarStripShrinkHost()
    }
  }
}

private struct ToolbarStripShrinkHost: View {
  // Owned ABOVE the toolbar scope but never read here: the host body only
  // projects the binding. The gallery's `TabView(selection:)` has the same
  // shape — `GalleryView` owns the selection, the TabView below the
  // `.toolbar()` scope reads it — so the dirty frontier is the reader
  // (a sibling of `…/toolbar-strip` under the scope), never the scope itself.
  @State private var showsExtra = true

  var body: some View {
    Panel(id: "toolbar-strip-shrink-host") {
      ToolbarStripShrinkContent(showsExtra: $showsExtra)
    }
    .toolbar().toolbarStyle(DefaultTopToolbarStyle())
  }
}

private struct ToolbarStripShrinkContent: View {
  let showsExtra: Binding<Bool>

  var body: some View {
    VStack(spacing: 0) {
      Button("toggle") { showsExtra.wrappedValue.toggle() }
      Text("stable content")
        .toolbarItem(
          .init(title: "Stable", icon: nil, position: .top, isEnabled: true, action: {})
        )
      if showsExtra.wrappedValue {
        Text("extra content")
          .toolbarItem(
            .init(title: "Extra", icon: nil, position: .top, isEnabled: true, action: {})
          )
      }
    }
  }
}

private final class ToolbarStripScriptedInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

private final class ToolbarStripEmptySignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

private final class ToolbarStripRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var lastPresentedSurface: RasterSurface?

  init(size: CellSize) { surfaceSize = size }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastPresentedSurface = surface
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}
