import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Runtime route-suppression coverage for the gallery "Presentation Lab overlays
/// are sometimes unclosable; in that state the background remains interactive"
/// failure (root `TODO.md`, reduced per
/// `docs/reports/2026-06-29-swifttui-gallery-coverage-deep-dive.md`).
///
/// These drive a real `RunLoop` and dispatch live pointer/Escape events. That is
/// the distinction the coverage report calls for: a *static* semantic-snapshot
/// check ("the base interaction region is absent") proves focus/route gating but
/// NOT that runtime pointer dispatch refuses the click — which is exactly the
/// reported symptom ("background remains interactive"). The earlier
/// `DefaultRenderer().render()` snapshot form also tripped the latent run-loop
/// memory-corruption crash (`SwiftTUI/swift-tui#12`) on TabView/presentation
/// trees; the synchronous run-loop path used here does not.
///
/// SCOPE NOTE — these use a minimal `@State`-driven fixture, not the gallery's
/// capture-host/portal/overflow shell. If the unclosable-overlay bug only
/// manifests behind that shell (as several prior gallery seam bugs did), these
/// pass as guards and the gallery integration test remains the red oracle. They
/// still earn their place: they fail loud if modal base-interaction suppression
/// or Escape dismissal regresses outright for these families.
@MainActor
@Suite
struct PresentationRouteSuppressionTests {
  @Test(
    "An open modal suppresses base pointer routes until it is dismissed",
    arguments: ModalRoutingKind.allCases
  )
  func modalPresentationsSuppressBaseClicksUntilDismissed(kind: ModalRoutingKind) throws {
    let harness = try ModalRoutingHarness(kind: kind)

    // Record where the base button is BEFORE opening the modal: once the modal
    // is up its `.disablesBaseInteraction` removes the base region from the
    // snapshot, so it can no longer be located by content.
    let basePoint = try #require(
      harness.point(forText: "Base Action"),
      "base button must be locatable before the modal opens"
    )

    let opened = try harness.clickText("Open Modal")
    #expect(
      opened.contains(kind.contentMarker),
      "expected the \(kind) modal to open; frame:\n\(opened)"
    )

    // Click the recorded base location while the modal is open. Correct
    // behavior: the modal disables base interaction, so dispatch finds no hit
    // target and the base action never fires. The "background remains
    // interactive" bug would advance the counter here.
    let afterBaseClick = try harness.click(basePoint)
    #expect(
      afterBaseClick.contains("Base fired: 0"),
      "base action must not fire while the modal is open; frame:\n\(afterBaseClick)"
    )
    #expect(
      afterBaseClick.contains(kind.contentMarker),
      "the modal must stay open after a suppressed base click"
    )

    // The overlay's own dismiss control must close it ("unclosable" guard).
    let dismissed = try harness.clickText(kind.dismissLabel, chooseLast: true)
    #expect(
      !dismissed.contains(kind.contentMarker),
      "the \(kind) modal must dismiss via its own control; frame:\n\(dismissed)"
    )

    // After dismissal the base route is live again.
    let afterReopen = try harness.click(basePoint)
    #expect(
      afterReopen.contains("Base fired: 1"),
      "base action must fire again after the modal is dismissed; frame:\n\(afterReopen)"
    )
  }

  @Test(
    "Escape dismisses an open modal and restores base routing",
    arguments: ModalRoutingKind.allCases
  )
  func escapeDismissesModalAndRestoresBaseRouting(kind: ModalRoutingKind) throws {
    let harness = try ModalRoutingHarness(kind: kind)
    let basePoint = try #require(harness.point(forText: "Base Action"))

    let opened = try harness.clickText("Open Modal")
    #expect(opened.contains(kind.contentMarker), "expected the \(kind) modal to open")

    harness.pressEscape()
    let afterEscape = try harness.render()
    #expect(
      !afterEscape.contains(kind.contentMarker),
      "Escape must dismiss the \(kind) modal; frame:\n\(afterEscape)"
    )

    let afterBase = try harness.click(basePoint)
    #expect(
      afterBase.contains("Base fired: 1"),
      "base routing must be restored after Escape dismissal; frame:\n\(afterBase)"
    )
  }

  /// The same suppression contract, but with the routing content hosted inside a
  /// `TabView(.literalTabs)` — the gallery "Presentation Lab" seam. This is the
  /// configuration that actually reproduced the root-`TODO.md` unclosable-overlay
  /// bug: behind the shell a suppressed background click was mis-routed into the
  /// overlay's own dismiss handler (pointer-activation reached *down* into the
  /// focused modal scope), so the overlay vanished from an outside click. The
  /// bare-fixture variant above passes even on the buggy build, which is why this
  /// shell variant is the durable framework guard the coverage report asked for.
  @Test(
    "An open modal behind the TabView shell suppresses base pointer routes until dismissed",
    arguments: ModalRoutingKind.allCases
  )
  func modalBehindTabShellSuppressesBaseClicksUntilDismissed(kind: ModalRoutingKind) throws {
    let harness = try ModalRoutingHarness(kind: kind, behindTabShell: true)

    let basePoint = try #require(
      harness.point(forText: "Base Action"),
      "base button must be locatable before the modal opens"
    )

    let opened = try harness.clickText("Open Modal")
    #expect(
      opened.contains(kind.contentMarker),
      "expected the \(kind) modal to open behind the tab shell; frame:\n\(opened)"
    )

    // Click the recorded base location while the modal is open. The buggy build
    // mis-routed this suppressed background click into the overlay's own handler
    // and dismissed the overlay; correct behavior leaves it up. A modal can fully
    // cover the base content, so "did the base fire" is checked after dismissal
    // (from state) rather than read from the covered frame.
    let afterBaseClick = try harness.click(basePoint)
    #expect(
      afterBaseClick.contains(kind.contentMarker),
      "the \(kind) modal must stay open after a suppressed background click; frame:\n\(afterBaseClick)"
    )

    // The overlay's own dismiss control still closes it ("unclosable" guard).
    let dismissed = try harness.clickText(kind.dismissLabel, chooseLast: true)
    #expect(
      !dismissed.contains(kind.contentMarker),
      "the \(kind) modal must dismiss via its own control behind the shell; frame:\n\(dismissed)"
    )
    // The suppressed background click must not have advanced the base counter —
    // now visible again with the overlay gone.
    #expect(
      dismissed.contains("Base fired: 0"),
      "base action must not fire while the \(kind) modal is open; frame:\n\(dismissed)"
    )

    let afterReopen = try harness.click(basePoint)
    #expect(
      afterReopen.contains("Base fired: 1"),
      "base routing must be restored after the \(kind) modal is dismissed; frame:\n\(afterReopen)"
    )
  }
}

enum ModalRoutingKind: CaseIterable, CustomStringConvertible, Sendable {
  case sheet
  case confirmationDialog
  case booleanPopover

  var description: String {
    switch self {
    case .sheet: "sheet"
    case .confirmationDialog: "confirmationDialog"
    case .booleanPopover: "booleanPopover"
    }
  }

  /// Text unique to the open overlay — its presence means the modal is visible.
  var contentMarker: String {
    switch self {
    case .sheet: "Close Sheet"
    case .confirmationDialog: "Close Confirm"
    case .booleanPopover: "Close Popover"
    }
  }

  var dismissLabel: String { contentMarker }
}

@MainActor
private struct ModalRoutingFixture: View {
  let kind: ModalRoutingKind
  /// When true, the routing content lives inside a `TabView(.literalTabs)` —
  /// the gallery "Presentation Lab" composition seam. A modal opened behind that
  /// shell leaves a broad active focus/interaction region under the backdrop;
  /// regressions in pointer-activation locality then mis-route a suppressed
  /// background click into the overlay's own handler (dismissing it from an
  /// outside click). The bare-base variant cannot reproduce that — its
  /// background hit-test returns no target at all.
  var behindTabShell = false
  @State private var baseFires = 0
  @State private var isPresented = false
  @State private var tabSelection = "routing"

  var body: some View {
    if behindTabShell {
      TabView(selection: $tabSelection) {
        Tab("Sibling", value: "sibling") {
          Text("Sibling tab content")
        }
        Tab("Routing", value: "routing") {
          routingContent
        }
      }
      .tabViewStyle(.literalTabs)
    } else {
      routingContent
    }
  }

  @ViewBuilder private var routingContent: some View {
    let base = VStack(alignment: .leading, spacing: 1) {
      Text("Base fired: \(baseFires)")
      Button("Base Action") { baseFires += 1 }
      Button("Open Modal") { isPresented = true }
      Spacer(minLength: 0)
    }
    .frame(width: 60, height: 16, alignment: .topLeading)

    switch kind {
    case .sheet:
      base.sheet("Routing Sheet", isPresented: $isPresented) {
        Button("Close Sheet") { isPresented = false }
      }
    case .confirmationDialog:
      base.confirmationDialog(
        "Routing Confirm",
        isPresented: $isPresented,
        actions: {
          Button("Close Confirm") { isPresented = false }
        },
        message: {
          Text("Confirm body")
        }
      )
    case .booleanPopover:
      base.popover(isPresented: $isPresented, arrowEdge: .trailing) {
        Button("Close Popover") { isPresented = false }
      }
    }
  }
}

@MainActor
private final class ModalRoutingHarness {
  let kind: ModalRoutingKind
  private let terminal: ModalRoutingRecordingHost
  private let runLoop: SwiftTUIRuntime.RunLoop<Int, ModalRoutingFixture>
  private let scheduler: FrameScheduler
  private var renderedFrames = 0

  init(kind: ModalRoutingKind, behindTabShell: Bool = false) throws {
    self.kind = kind
    let size = CellSize(width: 60, height: 16)
    let terminal = ModalRoutingRecordingHost(surfaceSize: size)
    let rootIdentity = testIdentity(
      "ModalRouting",
      kind.description,
      behindTabShell ? "tabShell" : "bare"
    )
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ModalRoutingEmptyKeyReader(),
      signalReader: ModalRoutingEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in ModalRoutingFixture(kind: kind, behindTabShell: behindTabShell) }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String { terminal.frames.last ?? "" }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return try #require(terminal.frames.last)
  }

  func point(forText text: String, chooseLast: Bool = false) -> Point? {
    terminal.centerOfText(text, chooseLast: chooseLast)
  }

  @discardableResult
  func click(_ point: Point) throws -> String {
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

  @discardableResult
  func clickText(_ label: String, chooseLast: Bool = false) throws -> String {
    let point = try #require(
      terminal.centerOfText(label, chooseLast: chooseLast),
      "could not find '\(label)' in frame:\n\(frame)"
    )
    return try click(point)
  }

  func pressEscape() {
    #expect(runLoop.handleKeyPress(KeyPress(.escape)) == nil)
  }
}

private final class ModalRoutingRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?
  let frameSignal = MainActorConditionSignal()

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
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    lastPresentedSurface = surface
    notifyFrameObservers()
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  func centerOfText(_ target: String, chooseLast: Bool = false) -> Point? {
    guard let surface = lastPresentedSurface else { return nil }

    if chooseLast {
      for row in surface.lines.indices.reversed() {
        let line = surface.lines[row]
        guard let range = line.range(of: target, options: .backwards) else { continue }
        let column = line.distance(from: line.startIndex, to: range.lowerBound)
        return Point(CellPoint(x: column + target.count / 2, y: row))
      }
      return nil
    }

    for (row, line) in surface.lines.enumerated() {
      guard let range = line.range(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }

  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

private final class ModalRoutingEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class ModalRoutingEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
