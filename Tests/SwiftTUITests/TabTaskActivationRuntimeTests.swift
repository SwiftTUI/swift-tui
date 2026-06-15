import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Live-runtime smoke coverage for selection-driven tab activation: clicking a
/// control that flips a `TabView`'s selection must activate the new tab AND run
/// the autonomous `.task` that its body declares. The click's `@State` write is
/// a *mapped* invalidation, so the activating frame publishes runtime
/// registrations with a frontier-scoped (`.subtrees`) plan — the path that must
/// still deliver the newly resolved body's task-start to the live registry.
///
/// SCOPE NOTE — this is an integration smoke test, **not** a fix-isolating
/// regression for the "frozen Physics tab" bug. That bug (a `.task` on a
/// lazily-activated tab body never starts) only manifests when the body sits
/// behind a *capture-host island seam* the scoped children-walk cannot cross.
/// Reproducing that seam takes the gallery's overflow-menu portal structure:
/// every minimal shape tried here (plain `TabView`, intermediate-`@State`,
/// toolbar-wrapped) keeps the body children-reachable, so the scoped restore
/// finds the task and the test passes with or without the framework fix
/// (`ViewGraph.republishAllEffectRegistrations`). The fix-isolating regression
/// home is the examples repo's gallery gravity-loop tests, which reproduce the
/// seam and now pass with the fix; the fix mechanism itself was confirmed in the
/// gallery under instrumentation. This test still earns its place: it fails if
/// live tab activation or autonomous-task execution regresses outright.
@MainActor
@Suite
struct TabTaskActivationRuntimeTests {
  @Test("selection-driven tab activation runs the activated tab's task")
  func activatingLazyTabStartsItsTask() async throws {
    let size = CellSize(width: 50, height: 18)
    let rootIdentity = testIdentity("TabTaskActivationRoot")

    // Render once (fresh graph, throwaway) only to locate the "switch"
    // button's bounds so the live run can click it.
    var env = EnvironmentValues()
    env.terminalSize = size
    let initial = DefaultRenderer().render(
      TabTaskActivationRoot(),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: size.width, height: size.height)
    )
    let switchNode = try #require(
      initial.placedTree.tabTaskFlattenedDescendants.first { node in
        if case .text("switch") = node.drawPayload { return true }
        return false
      },
      "could not find the switch button in the initial render"
    )
    let clickPoint = Point(switchNode.bounds.origin)

    let terminal = TabTaskRecordingHost(surfaceSize: size)

    // Clicking the button fires its action — a `@State` write that flips the
    // TabView selection to "work". That is a *mapped* invalidation, so the
    // activating frame publishes runtime registrations with a frontier-scoped
    // (`.subtrees`) plan rather than a full `.all` rebuild. The scoped restore
    // is the path that dropped the behind-the-seam tab body's `.task`. The
    // scripted input ends after the click; `run()` then drains to scheduler
    // quiescence — which, with the fix, includes the task running and the
    // re-render it triggers — before exiting on `inputEnded`.
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: TabTaskFixedMouseReader(events: [
        .mouse(.init(kind: .down(.primary), location: clickPoint)),
        .mouse(.init(kind: .up(.primary), location: clickPoint)),
      ]),
      signalReader: TabTaskEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: env,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in
        TabTaskActivationRoot()
      }
    )

    let result = try await runLoop.run()

    #expect(result.exitReason == .inputEnded)
    // The Work tab body renders whether or not its task ran, so this holds in
    // both the fixed and broken builds — it proves the click activated the tab.
    #expect(
      terminal.frames.contains { $0.contains("WORK tick:0") },
      "expected the Work tab body to render after activation"
    )
    // The task only advances the tick if its start event reached the live task
    // registry. `run()` drains to scheduler quiescence before exiting on
    // `inputEnded`, so if the task ran the tick:1 re-render is already present;
    // if autonomous-task execution regressed outright, the tick stays 0 and this
    // fails (RED) rather than hanging. (See the suite SCOPE NOTE: this minimal
    // structure keeps the body children-reachable, so it does not isolate the
    // capture-host-seam fix specifically.)
    let frameTail = terminal.frames.suffix(3).joined(separator: "\n----\n")
    #expect(
      terminal.frames.contains { $0.contains("WORK tick:1") },
      "expected the activated Work tab's .task to run and advance its tick; frames:\n\(frameTail)"
    )
  }
}

extension PlacedNode {
  fileprivate var tabTaskFlattenedDescendants: [PlacedNode] {
    var result: [PlacedNode] = [self]
    for child in children {
      result.append(contentsOf: child.tabTaskFlattenedDescendants)
    }
    return result
  }
}

private struct TabTaskActivationRoot: View {
  var body: some View {
    // A stable root wrapping the selection-owning host. Keeping the `@State`
    // selection *below* the root is what makes the activation a frontier-scoped
    // (`.subtrees`) publication: the write invalidates the host's subtree, not
    // the root, so the runtime restores registrations via the ViewNode
    // children-walk — which cannot reach the capture-hosted tab body. A
    // root-owned selection would instead force a flat `.all` rebuild that
    // reaches the island and masks the bug.
    VStack(spacing: 0) {
      Text("root")
      TabTaskSelectionHost()
    }
  }
}

private struct TabTaskSelectionHost: View {
  @State private var selection = "home"

  var body: some View {
    // The toolbar scope is the load-bearing detail: its late-preference
    // reconcile re-resolves the hosted content into the live graph every frame
    // (the capture-host "island" seam). On the scoped activation frame, the
    // frontier children-walk that restores registrations cannot cross that
    // seam, so the newly resolved Work tab body's `.task` registration is left
    // out of the live task registry — unless the fix republishes it. A plain
    // TabView without this seam stays children-reachable and does NOT reproduce
    // the bug.
    Panel(id: "host") {
      VStack(spacing: 0) {
        Button("switch") { selection = "work" }
        TabView(selection: $selection) {
          Tab("Home", value: "home") {
            Text("HOME")
          }
          Tab("Work", value: "work") {
            TabTaskWorkContent()
          }
        }
        .tabViewStyle(.literalTabs)
      }
      .toolbarItem(
        .init(title: "Item", icon: nil, position: .top, isEnabled: true, action: {})
      )
    }
    .toolbar(style: DefaultTopToolbarStyle())
  }
}

private struct TabTaskWorkContent: View {
  @State private var tick = 0

  var body: some View {
    Text("WORK tick:\(tick)")
      .task(id: "advance") {
        tick = 1
      }
  }
}

private final class TabTaskFixedMouseReader: TerminalInputReading {
  private let scriptedEvents: [InputEvent]

  init(events: [InputEvent]) {
    scriptedEvents = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class TabTaskEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class TabTaskRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []

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
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    ).render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}
