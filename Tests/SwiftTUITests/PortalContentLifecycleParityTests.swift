import SwiftTUICore
import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

/// `onChange` inside portal-presented content (sheet, palette, popover) is the
/// one lifecycle family whose registration is *conditional*: the modifier
/// registers only on the pass that decides to trigger. `beginRegistrationCapture`
/// resets a node's recorded handlers on every resolve and relies on that resolve
/// to re-record them, so a second pass over presented content erases the
/// triggering pass's registration and records nothing in its place. The
/// committed change entry — folded into the lifecycle carry-forward by the
/// focus-sync convergence loop — then dispatches into an empty registry.
///
/// The retained handler store is the designed remedy (see
/// `LifecycleCoordinator.absorbPublishedRegistrations`), and the async driver
/// has always fed it per pass. The synchronous driver did not, so the two
/// drivers disagreed about what survives a re-render: a portal `onChange` fired
/// in production and skipped under every synchronous test harness.
///
/// Both assertions here are non-vacuity assertions by construction — they
/// require the handler to have *run*, so a fixture that never reaches the
/// scenario fails rather than reporting a clean zero.
@MainActor
@Suite
struct PortalContentLifecycleParityTests {
  @Test("A sheet opened by a click fires its content's onChange (sync driver)")
  func portalOnChangeFiresUnderSyncDriver() throws {
    let probe = PortalLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PortalChangeSync", "Root"),
      size: .init(width: 40, height: 12)
    ) {
      PortalOnChangeFixture(probe: probe)
    }
    defer { harness.shutdown() }

    let opened = try harness.clickText("Open sheet")
    #expect(opened.contains("presented"), "the sheet never presented:\n\(opened)")
    #expect(
      probe.changeCount >= 1,
      "the presented content's onChange never fired under the sync driver")
    #expect(probe.appearCount >= 1, "the presented content's onAppear never fired")
  }

  @Test("A sheet opened by a click fires its content's onChange (async driver)")
  func portalOnChangeFiresUnderAsyncDriver() async throws {
    let probe = PortalLifecycleProbe()
    let root = testIdentity("PortalChangeAsync", "Root")
    let terminal = PortalParityHost()
    let runLoop = RunLoop<Int, PortalOnChangeFixture>(
      rootIdentity: root,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      proposal: .init(width: .finite(40), height: .finite(12)),
      viewBuilder: { _, _ in PortalOnChangeFixture(probe: probe) }
    )
    runLoop.focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [root])
    defer { runLoop.lifecycleCoordinator.shutdown() }
    var frames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &frames)

    // The button occupies the first row; press and release over it so the
    // sheet opens through the same focus-changing path the sync arm uses.
    let target = Point(x: 2, y: 0)
    _ = runLoop.handle(
      RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: target))))
    try await runLoop.renderPendingFramesAsync(renderedFrames: &frames)
    _ = runLoop.handle(
      RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: target))))
    try await runLoop.renderPendingFramesAsync(renderedFrames: &frames)

    #expect(probe.didPresent, "the sheet never presented under the async driver")
    #expect(
      probe.changeCount >= 1,
      "the presented content's onChange never fired under the async driver")
    #expect(probe.appearCount >= 1, "the presented content's onAppear never fired")
  }
}

/// Minimal raster-only presentation surface for driving the async frame-driver
/// entry point.
private final class PortalParityHost: PresentationSurface {
  let surfaceSize = CellSize(width: 40, height: 12)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.lines.count,
      cellsChanged: 0
    )
  }
}

@MainActor
private final class PortalLifecycleProbe {
  var changeCount = 0
  var appearCount = 0
  var didPresent = false
  var lastTransition: (Int, Int)?
}

/// Mirrors the shape the framework's own palette body uses: a `Group`-wrapped
/// stateful child (so the body is a *declared* child with its own view node
/// under the portal path) carrying an `onChange(of:initial: true)`.
///
/// The sheet is opened by a **click**, not presented from the first frame:
/// opening it moves focus into the modal, which drives the focus-sync
/// convergence re-render — the second resolve pass that resets the presented
/// content's recorded handlers. A fixture that presents immediately never
/// reaches that state and passes with or without the fix.
@MainActor
private struct PortalOnChangeFixture: View {
  let probe: PortalLifecycleProbe
  @State private var isPresented = false

  var body: some View {
    Button("Open sheet") {
      isPresented = true
    }
    .sheet(isPresented: $isPresented) {
      Group {
        PortalOnChangeBody(probe: probe)
      }
    }
    .frame(width: 40, height: 12, alignment: .topLeading)
  }
}

@MainActor
private struct PortalOnChangeBody: View {
  let probe: PortalLifecycleProbe
  @State private var token = 1

  var body: some View {
    Text("presented \(token)")
      .onChange(of: token, initial: true) { oldValue, newValue in
        probe.changeCount += 1
        probe.lastTransition = (oldValue, newValue)
      }
      .onAppear {
        probe.appearCount += 1
        probe.didPresent = true
      }
  }
}
