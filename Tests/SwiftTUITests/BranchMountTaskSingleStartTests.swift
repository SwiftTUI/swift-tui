import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Counter-demo ripple repro (0.7.0 diagnosis residual): a one-shot `.task`
/// on the body chain of a view mounted inside an `if` branch must start
/// exactly ONCE per mount. The probed 0.7.0 counter build showed the
/// RippleLayer's `.task` starting TWICE per mount — the second start 0-1ms
/// after the first, reading the same `@State` slot (progress already 1.0),
/// so same identity, not a remount. SwiftUI ground truth (native probe,
/// diagnosis session 2026-08-06): exactly one start per mount, including
/// the first. The second start's `withAnimation` re-writes an unchanged
/// value, producing an empty animation batch whose registered completion
/// never fires — a completion leak.
///
/// The fixture mirrors the 0.7.0 `CounterView`/`RippleLayer` shape: a
/// `.background { if active { Pane() } }` branch mounted by an
/// `onChange(of: count)` flip, where the pane's own body chain carries the
/// `.task` and the task's first write (`progress = 1`) re-evaluates the
/// still-mounted pane on the following frame.
@MainActor
@Suite
struct BranchMountTaskSingleStartTests {
  @Test("plain .task in a mounted branch starts once per mount")
  func plainBranchTaskStartsOncePerMount() async throws {
    let terminal = BranchTaskRecordingHost(
      surfaceSize: .init(width: 60, height: 8)
    )
    let recorder = BranchTaskRunRecorder(signal: terminal.frameSignal)
    let outcome = try await runTwoMountCycles(terminal: terminal, recorder: recorder) {
      generation, recorder, awaitPaneDone, dismiss in
      PlainBranchTaskPane(
        generation: generation,
        recorder: recorder,
        awaitPaneDone: awaitPaneDone,
        onCompletion: dismiss
      )
    }
    #expect(outcome == nil, "\(outcome ?? "")")
    #expect(
      recorder.startCount(generation: 1) == 1
        && recorder.startCount(generation: 2) == 1,
      "one start per mount expected; recorded starts: \(recorder.startDescriptions)"
    )
  }

  @Test(".task(id:) in a mounted branch starts once per mount")
  func idKeyedBranchTaskStartsOncePerMount() async throws {
    let terminal = BranchTaskRecordingHost(
      surfaceSize: .init(width: 60, height: 8)
    )
    let recorder = BranchTaskRunRecorder(signal: terminal.frameSignal)
    let outcome = try await runTwoMountCycles(terminal: terminal, recorder: recorder) {
      generation, recorder, awaitPaneDone, dismiss in
      IDKeyedBranchTaskPane(
        generation: generation,
        recorder: recorder,
        awaitPaneDone: awaitPaneDone,
        onCompletion: dismiss
      )
    }
    #expect(outcome == nil, "\(outcome ?? "")")
    #expect(
      recorder.startCount(generation: 1) == 1
        && recorder.startCount(generation: 2) == 1,
      "one start per mount expected; recorded starts: \(recorder.startDescriptions)"
    )
  }

  /// The observed casualty of the double start, asserted through the public
  /// surface: every task run registers exactly one `withAnimation`
  /// completion, so runs and fired completions must stay in parity. Under
  /// the double start the second run's `withAnimation` writes an unchanged
  /// value — an empty batch whose completion never fires (2 runs, 1
  /// completion).
  @Test("branch task withAnimation completion stays in parity with starts")
  func branchTaskAnimationCompletionParity() async throws {
    let terminal = BranchTaskRecordingHost(
      surfaceSize: .init(width: 60, height: 8)
    )
    let recorder = BranchTaskRunRecorder(signal: terminal.frameSignal)
    let inputReader = BranchTaskAwaitedInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .awaitCondition {
          terminal.frames.contains { $0.contains("count 0") }
        },
        .press(KeyPress(.return)),
        .awaitCondition {
          recorder.activeTransitions == [true, false]
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ])
    let runLoop = makeRunLoop(
      terminal: terminal,
      inputReader: inputReader
    ) { generation, dismiss in
      AnimatedCompletionBranchTaskPane(
        generation: generation,
        recorder: recorder,
        onCompletion: dismiss
      )
    } recorder: { recorder }

    let result = try await runLoop.run()
    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(runLoop.lifecycleCoordinator.taskStartSkipCount == 0)
    #expect(
      recorder.starts.count == 1,
      "one start per mount expected; recorded starts: \(recorder.startDescriptions)"
    )
    #expect(
      recorder.completions == recorder.starts.count,
      "every task run registers one completion; runs=\(recorder.starts.count) completions=\(recorder.completions)"
    )
  }

  /// Runs one launch: mount the pane (return press), let its task finish and
  /// dismiss it, remount (second return press), dismiss again, then exit.
  /// Returns a failure description for harness-level breakage, nil otherwise.
  private func runTwoMountCycles<Pane: View>(
    terminal: BranchTaskRecordingHost,
    recorder: BranchTaskRunRecorder,
    makePane: @escaping @MainActor (
      Int,
      BranchTaskRunRecorder,
      @escaping @MainActor @Sendable (Int) async -> Void,
      @escaping @MainActor @Sendable () -> Void
    ) -> Pane
  ) async throws -> String? {
    let awaitPaneDone: @MainActor @Sendable (Int) async -> Void = {
      [frameSignal = terminal.frameSignal] generation in
      await frameSignal.wait {
        terminal.frames.contains { $0.contains("pane \(generation) done") }
      }
    }
    let inputReader = BranchTaskAwaitedInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .awaitCondition {
          terminal.frames.contains { $0.contains("count 0") }
        },
        .press(KeyPress(.return)),
        .awaitCondition {
          recorder.activeTransitions == [true, false]
        },
        .press(KeyPress(.return)),
        .awaitCondition {
          recorder.activeTransitions == [true, false, true, false]
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ])
    let runLoop = makeRunLoop(
      terminal: terminal,
      inputReader: inputReader
    ) { generation, dismiss in
      makePane(generation, recorder, awaitPaneDone, dismiss)
    } recorder: { recorder }

    let result = try await runLoop.run()
    guard result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)) else {
      return "unexpected exit reason \(result.exitReason)"
    }
    let skips = runLoop.lifecycleCoordinator.taskStartSkipCount
    guard skips == 0 else {
      return "taskStartSkipCount=\(skips)"
    }
    return nil
  }

  private func makeRunLoop<Pane: View>(
    terminal: BranchTaskRecordingHost,
    inputReader: BranchTaskAwaitedInputReader,
    makePane: @escaping @MainActor (Int, @escaping @MainActor @Sendable () -> Void) -> Pane,
    recorder: @escaping @MainActor () -> BranchTaskRunRecorder
  ) -> SwiftTUIRuntime.RunLoop<Int, BranchMountTaskProbe<Pane>> {
    let rootIdentity = testIdentity("BranchMountTaskRoot")
    return SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: BranchTaskEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 60, height: 8),
      viewBuilder: { _, _ in
        BranchMountTaskProbe(
          recorder: recorder(),
          makePane: makePane
        )
      }
    )
  }
}

/// Mirrors the 0.7.0 `CounterView`: an increment button, an
/// `onChange(of: count)` that raises the mount guard, and a `.background`
/// builder `if` that mounts the pane while the guard is up.
private struct BranchMountTaskProbe<Pane: View>: View {
  let recorder: BranchTaskRunRecorder
  let makePane: @MainActor (Int, @escaping @MainActor @Sendable () -> Void) -> Pane

  @State private var count = 0
  @State private var active = false

  var body: some View {
    VStack(spacing: 1) {
      Text("count \(count)")
      Button("Increment") {
        count += 1
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: count) {
      if !active {
        active = true
      }
    }
    .onChange(of: active) {
      recorder.recordActive(active)
    }
    .background {
      if active {
        makePane(count) {
          active = false
        }
      }
    }
  }
}

/// The `RippleLayer` analog: the one-shot `.task` sits on the pane's own
/// body chain, records its start, writes state that re-evaluates the
/// still-mounted pane (the ripple's `withAnimation { progress = 1 }`
/// analog), waits for that write's frame to render, then dismisses.
private struct PlainBranchTaskPane: View {
  let generation: Int
  let recorder: BranchTaskRunRecorder
  let awaitPaneDone: @MainActor @Sendable (Int) async -> Void
  let onCompletion: @MainActor @Sendable () -> Void

  @State private var progress: Double = 0

  var body: some View {
    BranchTaskPaneLabel(generation: generation, progress: progress)
      .task {
        recorder.recordStart(generation: generation, progress: progress)
        progress = 1
        await awaitPaneDone(generation)
        // A duplicate start cancels this run (`TaskRunner.start` restarts
        // per descriptor); the wait resumes on cancellation, and a
        // cancelled run must not dismiss the pane its replacement owns.
        guard !Task.isCancelled else {
          return
        }
        onCompletion()
      }
  }
}

private struct IDKeyedBranchTaskPane: View {
  let generation: Int
  let recorder: BranchTaskRunRecorder
  let awaitPaneDone: @MainActor @Sendable (Int) async -> Void
  let onCompletion: @MainActor @Sendable () -> Void

  @State private var progress: Double = 0

  var body: some View {
    BranchTaskPaneLabel(generation: generation, progress: progress)
      .task(id: "ripple") {
        recorder.recordStart(generation: generation, progress: progress)
        progress = 1
        await awaitPaneDone(generation)
        guard !Task.isCancelled else {
          return
        }
        onCompletion()
      }
  }
}

/// The ripple's exact one-shot shape: `withAnimation` with a registered
/// completion, where the completion dismisses the pane.
private struct AnimatedCompletionBranchTaskPane: View {
  let generation: Int
  let recorder: BranchTaskRunRecorder
  let onCompletion: @MainActor @Sendable () -> Void

  @State private var progress: Double = 0

  var body: some View {
    BranchTaskPaneLabel(generation: generation, progress: progress)
      .task {
        recorder.recordStart(generation: generation, progress: progress)
        withAnimation(.linear(duration: .milliseconds(120))) {
          progress = 1
        } completion: {
          recorder.recordCompletion()
          onCompletion()
        }
      }
  }
}

private struct BranchTaskPaneLabel: View {
  let generation: Int
  let progress: Double

  var body: some View {
    Text(progress >= 1 ? "pane \(generation) done" : "pane \(generation) starting")
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }
}

/// Records the task runs and mount transitions the tests assert on. Every
/// mutation notifies the shared condition signal: the records land in
/// lifecycle dispatch AFTER the frame's present, so a choreography step
/// waiting on recorder state would otherwise miss its wakeup when no later
/// frame renders.
@MainActor
private final class BranchTaskRunRecorder {
  private let signal: MainActorConditionSignal
  private(set) var starts: [(generation: Int, progress: Double)] = []
  private(set) var completions = 0
  private(set) var activeTransitions: [Bool] = []

  init(signal: MainActorConditionSignal) {
    self.signal = signal
  }

  func recordStart(generation: Int, progress: Double) {
    starts.append((generation: generation, progress: progress))
    signal.notify()
  }

  func recordCompletion() {
    completions += 1
    signal.notify()
  }

  func recordActive(_ value: Bool) {
    activeTransitions.append(value)
    signal.notify()
  }

  func startCount(generation: Int) -> Int {
    starts.count { $0.generation == generation }
  }

  var startDescriptions: [String] {
    starts.map { "gen=\($0.generation) progressAtStart=\($0.progress)" }
  }
}

private final class BranchTaskRecordingHost: PresentationSurface {
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

private enum BranchTaskInputStep {
  case press(KeyPress)
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class BranchTaskAwaitedInputReader: InputReading {
  private let steps: [BranchTaskInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [BranchTaskInputStep]
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

private final class BranchTaskEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
