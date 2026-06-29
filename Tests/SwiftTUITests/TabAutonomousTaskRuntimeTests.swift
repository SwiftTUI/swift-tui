import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Runtime lifecycle coverage for the gallery "transitioning off of the Logo
/// Breaker tab takes forever" failure (root `TODO.md`, reduced per
/// `docs/reports/2026-06-29-swifttui-gallery-coverage-deep-dive.md`).
///
/// The reported symptom is a surviving autonomous task: Logo Breaker runs a
/// ~25 Hz geometry-driven `.task(id:)` loop, and if that task is not cancelled
/// when its lazily-activated `TabView` body leaves, it keeps writing state and
/// requesting frames after the user has switched away — which feels like the
/// transition is stuck.
///
/// This drives a real `RunLoop` on the synchronous frame path and asserts the
/// observable runtime fact: `lifecycleCoordinator.activeTaskCount` returns to
/// zero after the active geometry-backed tab leaves. That is the distinction
/// the coverage report calls for — the earlier `DefaultRenderer().render()`
/// snapshot form could only inspect a `.taskCancel` *plan entry* (the snapshot
/// renderer never starts or cancels real tasks), and it tripped the latent
/// run-loop memory-corruption crash (`SwiftTUI/swift-tui#12`) on TabView trees.
///
/// SCOPE NOTE — like `TabTaskActivationRuntimeTests`, this uses a minimal
/// `TabView` shape that keeps the tab body children-reachable. If the slow-leave
/// bug only manifests behind the gallery's capture-host/portal/overflow seam (as
/// several prior gallery task-lifecycle bugs did), this passes as a guard and the
/// gallery integration test remains the red oracle. It still fails loud if
/// active-tab task cancellation regresses outright.
@MainActor
@Suite
struct TabAutonomousTaskRuntimeTests {
  @Test("Leaving an active geometry-backed tab cancels its autonomous task")
  func leavingActiveGeometryTabCancelsItsAutonomousTask() throws {
    let harness = try GeometryTaskHarness()

    // The Logo-like tab is active on first render, so its geometry-driven
    // `.task` must be registered as a live task. `activeTaskCount` is driven by
    // the task registry (start inserts, cancel removes — both synchronous within
    // the commit), so a synchronous render gives a deterministic count.
    #expect(
      harness.frame.contains("logo-active"),
      "the Logo-like tab body must be visible on first render; frame:\n\(harness.frame)"
    )
    #expect(
      harness.activeTaskCount == 1,
      "the active geometry-backed tab's autonomous task must be running; count=\(harness.activeTaskCount)"
    )

    // Switch to the static tab.
    let afterSwitch = try harness.clickText("switch")
    #expect(
      afterSwitch.contains("static tab"),
      "switching must activate the static tab; frame:\n\(afterSwitch)"
    )

    // The departed tab's autonomous task must be cancelled — otherwise it keeps
    // writing state and requesting frames (the "takes forever to leave" symptom).
    #expect(
      harness.activeTaskCount == 0,
      "leaving the geometry-backed tab must cancel its task; count=\(harness.activeTaskCount)"
    )
  }
}

private struct GeometryBoundsID: Equatable, Sendable {
  var width: Int
  var height: Int
}

@MainActor
private struct GeometryTaskProbe: View {
  @State private var selection = "logo"

  var body: some View {
    VStack(spacing: 0) {
      Button("switch") { selection = "static" }
      TabView(selection: $selection) {
        Tab("Logo", value: "logo") {
          GeometryReader { proxy in
            Text("logo-active")
              .task(
                id: GeometryBoundsID(width: proxy.size.width, height: proxy.size.height)
              ) {
                // Stay alive while the tab is active; exit only on cancellation.
                // (In a synchronous test the body never runs — the count is
                // driven by the task registry, not by body completion.)
                while !Task.isCancelled {
                  await Task.yield()
                }
              }
          }
        }
        Tab("Static", value: "static") {
          Text("static tab")
        }
      }
      .tabViewStyle(.literalTabs)
    }
  }
}

@MainActor
private final class GeometryTaskHarness {
  private let terminal: AutonomousTaskRecordingHost
  private let runLoop: SwiftTUIRuntime.RunLoop<Int, GeometryTaskProbe>
  private let scheduler: FrameScheduler
  private var renderedFrames = 0

  init() throws {
    let size = CellSize(width: 48, height: 12)
    let terminal = AutonomousTaskRecordingHost(surfaceSize: size)
    let rootIdentity = testIdentity("GeometryTaskRoot")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: AutonomousTaskEmptyKeyReader(),
      signalReader: AutonomousTaskEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in GeometryTaskProbe() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String { terminal.frames.last ?? "" }

  var activeTaskCount: Int { runLoop.lifecycleCoordinator.activeTaskCount }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return try #require(terminal.frames.last)
  }

  @discardableResult
  func clickText(_ label: String) throws -> String {
    let point = try #require(
      terminal.centerOfText(label),
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

private final class AutonomousTaskRecordingHost: PresentationSurface {
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
    let rows = chooseLast ? Array(surface.lines.indices.reversed()) : Array(surface.lines.indices)
    for row in rows {
      let line = surface.lines[row]
      let options: String.CompareOptions = chooseLast ? .backwards : []
      guard let range = line.range(of: target, options: options) else { continue }
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

private final class AutonomousTaskEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class AutonomousTaskEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
