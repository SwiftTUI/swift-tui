@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F3 RunLoop session cleanup", .serialized)
struct AdversarialSetESessionLifetimeTests {
  @Test(arguments: Array(81...90))
  func sessionLifetime(id: Int) async throws {
    let probe = SetESessionProbe()
    let surface = SetESessionSurface(kind: id)
    let input = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
    let signals = InProcessSignalReader()
    let identity = testIdentity("setE", String(id))
    let loop = RunLoop(
      rootIdentity: identity, presentationSurface: surface, terminalInputReader: input,
      signalReader: signals, scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      viewBuilder: { _, _ in SetESessionContent(kind: id, probe: probe) })
    if id <= 85 { input.finish() }
    let runner = Task {
      let result: Result<RunLoopResult<Int>, any Error>
      do { result = .success(try await loop.run()) } catch { result = .failure(error) }
      probe.runEnded = true
      probe.changed.notify()
      return result
    }
    @MainActor func cleanup() async {
      input.finish()
      signals.finish()
      runner.cancel()
      _ = await runner.value
      loop.lifecycleCoordinator.shutdown()
      probe.release.fire()
      await probe.changed.wait { probe.finished == probe.started }
    }
    do {
      if id >= 86 {
        await probe.changed.wait { probe.started == 1 || probe.runEnded }
        try #require(probe.started == 1)
        try #require(loop.lifecycleCoordinator.activeTaskCount == 1)
        switch id {
        case 86: input.finish()
        case 87: input.send(.key(.character("c"), modifiers: .ctrl))
        case 88: signals.send("SIGTERM")
        case 89: runner.cancel()
        default: #expect(loop.runtimeRequestTerminationAction()())
        }
      }
      let result = await runner.value
      if id == 81 {
        setEKnown("STUI-1182: failed raw-mode entry must retire session bookkeeping") {
          #expect(!loop.isSessionActive)
        }
        setEKnown("STUI-1182: an ended session must refuse termination requests") {
          #expect(!loop.runtimeRequestTerminationAction()())
        }
      } else {
        #expect(!loop.isSessionActive)
        #expect(!loop.runtimeRequestTerminationAction()())
      }
      #expect(loop.lifecycleCoordinator.activeTaskCount == 0)
      #expect(loop.lifecycleCoordinator.activeTaskDescriptors.isEmpty)
      #expect(surface.enables == 1)
      #expect(surface.disables == (id == 81 ? 0 : 1))
      if [81, 82, 83, 85].contains(id) {
        switch result {
        case .failure(let error): #expect(error as? SetESessionError == .planned(id))
        case .success: Issue.record("expected the configured surface error")
        }
      } else if id != 89 {
        let value = try result.get()
        switch id {
        case 87: #expect(value.exitReason == .userExit(.init(.character("c"), modifiers: .ctrl)))
        case 88: #expect(value.exitReason == .signal("SIGTERM"))
        case 90: #expect(value.exitReason == .programmatic)
        default: #expect(value.exitReason == .inputEnded)
        }
      }
      if id >= 86 {
        await probe.changed.wait { probe.finished == 1 }
        #expect(probe.cancelled == 1)
      }
      await cleanup()
    } catch {
      await cleanup()
      throw error
    }
  }
}

@MainActor
private final class SetESessionProbe {
  let changed = MainActorConditionSignal()
  let release = AsyncEvent()
  var started = 0
  var finished = 0
  var cancelled = 0
  var runEnded = false
  func run() async {
    started += 1
    changed.notify()
    await release.wait()
    if Task.isCancelled { cancelled += 1 }
    finished += 1
    changed.notify()
  }
}

private struct SetESessionContent: View {
  let kind: Int
  let probe: SetESessionProbe
  @State private var value = 0
  var body: some View {
    Text("Value \(value)")
      .onAppear { if kind == 83 { value += 1 } }
      .onPointerHover { _ in }
      .task { await probe.run() }
  }
}

private enum SetESessionError: Error, Equatable { case planned(Int) }

private final class SetESessionSurface: PresentationSurface {
  let kind: Int
  let surfaceSize = CellSize(width: 20, height: 4)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  var enables = 0
  var disables = 0
  var presentations = 0
  init(kind: Int) { self.kind = kind }
  func enableRawMode() throws {
    enables += 1
    if kind == 81 { throw SetESessionError.planned(kind) }
  }
  func disableRawMode() throws {
    disables += 1
    if kind == 84 { throw SetESessionError.planned(kind) }
  }
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func setPointerHoverEnabled(_ enabled: Bool) throws {
    if kind == 85 && enabled { throw SetESessionError.planned(kind) }
  }
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentations += 1
    if (kind == 82 && presentations == 1) || (kind == 83 && presentations == 2) {
      throw SetESessionError.planned(kind)
    }
    return .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}
