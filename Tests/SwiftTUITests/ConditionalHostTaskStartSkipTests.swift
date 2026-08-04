import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// gifeditor launch repro: a `.task(id:)` attached to a `@ViewBuilder`
/// if/else-if/else chain hosts its descriptor on the *active branch's*
/// resolved node (`ConditionalContent` mints no node of its own), while its
/// registration is recorded on the *ambient authoring node*. When the branch
/// content carries its own `.task` on its root chain, the two registrations
/// share one host identity but live on two view nodes. Publication restores
/// per node (in `Set` iteration order), so a replace-per-identity restore let
/// the last-iterated node erase its sibling's registrations — and the erased
/// task's committed `.taskStart` skipped at commit and silently never ran.
/// `LocalTaskRegistry.restore` now merges per identity by descriptor id.
///
/// Observed in the wild (racy — hash-seed dependent, roughly a third of
/// launches) as `[lifecycle.taskStartSkipped] … committed task
/// '…/true/false#task[id:N]' never started: no task registration at commit`
/// at gifeditor startup — `true/false` is the *editor* branch of the
/// left-leaning `ConditionalContent<ConditionalContent<Recovery, Editor>,
/// Loading>` tree, whose `EditorView` root chain has the playback
/// `.task(id:)` beside the outer launch `.task(id:)`.
@MainActor
@Suite
struct ConditionalHostTaskStartSkipTests {
  @Test("task on a branch-flipping conditional never drops a committed start")
  func conditionalHostTaskStartSurvivesBranchFlip() async throws {
    var failures: [String] = []
    for iteration in 0..<40 {
      let outcome = try await runLaunchFlip(spinnerTicks: iteration % 5)
      if let failure = outcome {
        failures.append("iteration \(iteration): \(failure)")
      }
    }
    #expect(failures.isEmpty, "committed task starts were dropped: \(failures)")
  }

  /// Runs one fresh launch-shaped run loop; returns a failure description if
  /// a committed `.taskStart` was dropped at commit.
  private func runLaunchFlip(spinnerTicks: Int) async throws -> String? {
    let terminal = ConditionalTaskRecordingHost(
      surfaceSize: .init(width: 60, height: 8)
    )
    let rootIdentity = testIdentity("ConditionalTaskRoot")
    let inputReader = ConditionalTaskAwaitedInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .awaitCondition {
          terminal.frames.contains { $0.contains("editor ready") }
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: ConditionalTaskEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 60, height: 8),
      viewBuilder: { _, _ in
        ConditionalTaskLaunchProbe(spinnerTicks: spinnerTicks)
      }
    )
    let issues = ConditionalTaskIssueLog()
    runLoop.runtimeIssueSink = RuntimeIssueSink { issue in
      issues.record(issue.description)
    }

    let result = try await runLoop.run()

    guard result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)) else {
      return "unexpected exit reason \(result.exitReason)"
    }
    let skips = runLoop.lifecycleCoordinator.taskStartSkipCount
    if skips > 0 || issues.entries.contains(where: { $0.contains("taskStartSkipped") }) {
      return "skips=\(skips) issues=\(issues.entries)"
    }
    return nil
  }
}

/// Mirrors `GIFEditor.body`: content is an if/else-if/else chain, the task is
/// attached outside it, and the task's own writes drive the branch — first a
/// few loading-progress writes (the app renders several frames while the
/// document loads), then the flip to the editor branch.
private struct ConditionalTaskLaunchProbe: View {
  let spinnerTicks: Int
  @State private var revision = 0
  @State private var dots = 0
  @State private var lifecycle: Int?

  var body: some View {
    _ = revision
    content
      .task(id: "path") {
        lifecycle = nil
        for _ in 0..<spinnerTicks {
          dots &+= 1
          await Task.yield()
        }
        await Task.yield()
        guard !Task.isCancelled else {
          return
        }
        lifecycle = 1
      }
  }

  @ViewBuilder
  private var content: some View {
    if lifecycle == 2 {
      VStack(alignment: .leading, spacing: 1) {
        Text("recovery prompt")
        HStack(spacing: 2) {
          Button("Recover") {
            revision &+= 1
          }
          Button("Discard") {
            revision &+= 1
          }
        }
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else if lifecycle != nil {
      // The editor analog. Crucially it carries its OWN `.task` on its root
      // chain (like EditorView's playback task): after the flip, that task
      // and the outer launch task share the same host identity while being
      // recorded on different view nodes — the collision under test.
      ConditionalTaskEditorPane(revision: $revision)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text("gifeditor")
        Text("loading document \(dots)")
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

/// The EditorView analog: a composite view minted at the branch identity,
/// with focusable content and its own `.task(id:)` on the root chain.
private struct ConditionalTaskEditorPane: View {
  @Binding var revision: Int
  @State private var playbackTicks = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("editor ready \(playbackTicks)")
      HStack(spacing: 2) {
        Button("Play") {
          revision &+= 1
        }
        Button("Stop") {
          revision &+= 1
        }
      }
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: false) {
      playbackTicks &+= 1
    }
  }
}

@MainActor
private final class ConditionalTaskIssueLog {
  private(set) var entries: [String] = []

  func record(_ entry: String) {
    entries.append(entry)
  }
}

private final class ConditionalTaskRecordingHost: PresentationSurface {
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
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
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

private enum ConditionalTaskInputStep {
  case press(KeyPress)
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class ConditionalTaskAwaitedInputReader: InputReading {
  private let steps: [ConditionalTaskInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [ConditionalTaskInputStep]
  ) {
    self.frameSignal = frameSignal
    self.steps = steps
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let event):
            continuation.yield(event)
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class ConditionalTaskEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
