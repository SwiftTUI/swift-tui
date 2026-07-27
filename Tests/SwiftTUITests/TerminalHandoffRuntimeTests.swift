@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TerminalHandoffRuntimeTests {
  @Test("runtime handoff orders suspension, terminal modes, operation, and input resync")
  func successfulHandoffRestoresRuntimeAndRequestsFullRedraw() async throws {
    let recorder = HandoffRecorder()
    let fixture = makeHandoffRunLoop(recorder: recorder)
    fixture.runLoop.previousPresentedRasterSurface = RasterSurface(
      size: .init(width: 1, height: 1),
      lines: ["x"]
    )

    let action = fixture.runLoop.runtimeTerminalHandoffAction()
    try await TerminalHandoffAction.$current.withValue(action) {
      try await TerminalHandoffAction.perform {
        recorder.append("operation")
      }
    }

    #expect(
      recorder.events == [
        "suspend-input",
        "disable-raw-mode",
        "operation",
        "enable-raw-mode",
        "synchronize-input-capabilities",
        "resume-input",
      ]
    )
    #expect(fixture.runLoop.previousPresentedRasterSurface == nil)
    #expect(fixture.scheduler.pendingInvalidatedIdentities == [fixture.runLoop.rootIdentity])
    #expect(fixture.scheduler.hasPendingFrame(at: .now()))
  }

  @Test("throwing operation still restores terminal and resumes input")
  func throwingOperationRestoresRuntime() async {
    let recorder = HandoffRecorder()
    let fixture = makeHandoffRunLoop(recorder: recorder)
    let action = fixture.runLoop.runtimeTerminalHandoffAction()

    do {
      try await action {
        recorder.append("operation")
        throw HandoffTestError.operationFailed
      }
      Issue.record("handoff unexpectedly succeeded")
    } catch HandoffTestError.operationFailed {
    } catch {
      Issue.record("unexpected error: \(error)")
    }

    #expect(
      recorder.events == [
        "suspend-input",
        "disable-raw-mode",
        "operation",
        "enable-raw-mode",
        "synchronize-input-capabilities",
        "resume-input",
      ]
    )
    #expect(!fixture.runLoop.terminalHandoffInProgress)
  }

  @Test("cooperative cancellation still restores terminal and resumes input")
  func cancelledOperationRestoresRuntime() async {
    let recorder = HandoffRecorder()
    let fixture = makeHandoffRunLoop(recorder: recorder)
    let action = fixture.runLoop.runtimeTerminalHandoffAction()
    let operationStarted = AsyncEvent()
    let cancellationObserved = AsyncEvent()
    let cancellationGate = AsyncEvent()

    let handoff = Task {
      try await action {
        recorder.append("operation")
        operationStarted.fire()
        await cancellationGate.wait()
        cancellationObserved.fire()
        try Task.checkCancellation()
      }
    }
    await operationStarted.wait()
    handoff.cancel()
    do {
      try await handoff.value
      Issue.record("handoff unexpectedly succeeded")
    } catch is CancellationError {
    } catch {
      Issue.record("unexpected error: \(error)")
    }
    await cancellationObserved.wait()

    #expect(recorder.events.last == "resume-input")
    #expect(recorder.events.contains("enable-raw-mode"))
    #expect(!fixture.runLoop.terminalHandoffInProgress)
  }

  @Test("raw-mode exit failure still attempts runtime restoration")
  func rawModeExitFailureRestoresRuntime() async {
    let recorder = HandoffRecorder()
    let fixture = makeHandoffRunLoop(recorder: recorder, failsDisableRawMode: true)
    let action = fixture.runLoop.runtimeTerminalHandoffAction()

    do {
      try await action {
        Issue.record("operation must not run when raw-mode exit fails")
      }
      Issue.record("handoff unexpectedly succeeded")
    } catch HandoffTestError.rawModeExitFailed {
    } catch {
      Issue.record("unexpected error: \(error)")
    }

    #expect(
      recorder.events == [
        "suspend-input",
        "disable-raw-mode",
        "enable-raw-mode",
        "synchronize-input-capabilities",
        "resume-input",
      ]
    )
    #expect(!fixture.runLoop.terminalHandoffInProgress)
  }

  @Test("failed runtime restoration resumes input and reports a typed error")
  func restorationFailureResumesInput() async {
    let recorder = HandoffRecorder()
    let fixture = makeHandoffRunLoop(recorder: recorder, failsEnableRawMode: true)
    let action = fixture.runLoop.runtimeTerminalHandoffAction()

    do {
      try await action {
        recorder.append("operation")
      }
      Issue.record("handoff unexpectedly succeeded")
    } catch let error as TerminalHandoffError {
      #expect(error == .failedToRestoreTerminal)
    } catch {
      Issue.record("unexpected error: \(error)")
    }

    #expect(recorder.events.last == "resume-input")
    #expect(!fixture.runLoop.terminalHandoffInProgress)
  }

  @Test("a handoff finishing after run-loop shutdown never reclaims terminal ownership")
  func staleHandoffDoesNotReenterRawMode() async {
    let recorder = HandoffRecorder()
    let fixture = makeHandoffRunLoop(recorder: recorder)
    let action = fixture.runLoop.runtimeTerminalHandoffAction()
    let operationStarted = AsyncEvent()
    let finishOperation = AsyncEvent()

    let handoff = Task {
      try await action {
        recorder.append("operation")
        operationStarted.fire()
        await finishOperation.wait()
      }
    }
    await operationStarted.wait()
    fixture.runLoop.deactivateTerminalHandoffSession()
    finishOperation.fire()

    do {
      try await handoff.value
      Issue.record("stale handoff unexpectedly reclaimed the terminal")
    } catch let error as TerminalHandoffError {
      #expect(error == .unavailable)
    } catch {
      Issue.record("unexpected error: \(error)")
    }

    #expect(
      recorder.events == [
        "suspend-input",
        "disable-raw-mode",
        "operation",
        "resume-input",
      ]
    )
    #expect(!fixture.runLoop.terminalHandoffInProgress)
  }

  @Test("clipboard commands cannot access the terminal during a handoff")
  func clipboardCommandsRespectExclusiveTerminalOwnership() async throws {
    let recorder = HandoffRecorder()
    let fixture = makeHandoffRunLoop(recorder: recorder)
    let handoff = fixture.runLoop.runtimeTerminalHandoffAction()
    let clipboardWrite = fixture.runLoop.runtimeClipboardWriteAction()
    let clipboardRead = fixture.runLoop.runtimeClipboardReadAction()

    try await handoff {
      recorder.append("operation")
      #expect(!clipboardWrite("inside-handoff"))
      #expect(clipboardRead() == nil)
    }

    #expect(clipboardWrite("after-handoff"))
    #expect(clipboardRead() == "clipboard")
    #expect(
      recorder.events == [
        "suspend-input",
        "disable-raw-mode",
        "operation",
        "enable-raw-mode",
        "synchronize-input-capabilities",
        "resume-input",
        "clipboard-write",
        "clipboard-read",
      ]
    )
  }

  @Test("resolve context injects the live handoff without replacing a custom action")
  func resolveContextInjectionHonorsCustomAction() {
    let recorder = HandoffRecorder()
    let fixture = makeHandoffRunLoop(recorder: recorder)
    let frame = ScheduledFrame(
      causes: [.invalidation],
      invalidatedIdentities: [fixture.runLoop.rootIdentity],
      signalNames: [],
      externalReasons: [],
      triggeredDeadline: nil,
      nextDeadline: nil
    )

    let live = fixture.runLoop.resolveContext(for: frame)
    #expect(!live.environmentValues.terminalHandoff.isPlaceholder)
    #expect(live.environmentValues.terminalHandoff.description == "TerminalHandoffAction.runtime")

    var values = EnvironmentValues()
    values.terminalHandoff = TerminalHandoffAction { operation in
      try await operation()
    }
    let customFixture = makeHandoffRunLoop(recorder: recorder, environmentValues: values)
    let custom = customFixture.runLoop.resolveContext(for: frame)
    #expect(custom.environmentValues.terminalHandoff.description == "TerminalHandoffAction.custom")
  }

  @Test("static handoff fails closed outside a run-loop task")
  func staticHandoffRequiresActiveTaskLocalSession() async {
    do {
      try await TerminalHandoffAction.perform {}
      Issue.record("handoff unexpectedly succeeded")
    } catch let error as TerminalHandoffError {
      #expect(error == .unavailable)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }
}

private enum HandoffTestError: Error {
  case operationFailed
  case rawModeExitFailed
  case rawModeEntryFailed
}

private final class HandoffRecorder: Sendable {
  private let storage = Mutex<[String]>([])

  var events: [String] {
    storage.withLock { $0 }
  }

  func append(_ event: String) {
    storage.withLock { $0.append(event) }
  }
}

private final class HandoffInputReader: TerminalInputReading, TerminalInputHandoffSuspending,
  TerminalInputCapabilityConfiguring
{
  let recorder: HandoffRecorder

  init(recorder: HandoffRecorder) {
    self.recorder = recorder
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { _ in }
  }

  func updateInputCapabilities(_: ResolvedTerminalInputCapabilities) {
    recorder.append("synchronize-input-capabilities")
  }

  func withInputSuspended<T>(_ body: () throws -> T) rethrows -> T {
    recorder.append("suspend-input")
    defer {
      recorder.append("resume-input")
    }
    return try body()
  }

  @MainActor
  func withInputSuspended<T: Sendable>(
    _ body: @MainActor @Sendable () async throws -> T
  ) async rethrows -> T {
    recorder.append("suspend-input")
    defer {
      recorder.append("resume-input")
    }
    return try await body()
  }
}

private final class HandoffTerminalHost: PresentationSurface,
  TerminalInputCapabilityProviding, ClipboardWritingPresentationSurface,
  ClipboardReadingPresentationSurface
{
  let recorder: HandoffRecorder
  let surfaceSize = CellSize(width: 40, height: 8)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  let resolvedInputCapabilities = ResolvedTerminalInputCapabilities()
  let failsDisableRawMode: Bool
  let failsEnableRawMode: Bool

  init(
    recorder: HandoffRecorder,
    failsDisableRawMode: Bool,
    failsEnableRawMode: Bool
  ) {
    self.recorder = recorder
    self.failsDisableRawMode = failsDisableRawMode
    self.failsEnableRawMode = failsEnableRawMode
  }

  func enableRawMode() throws {
    recorder.append("enable-raw-mode")
    if failsEnableRawMode {
      throw HandoffTestError.rawModeEntryFailed
    }
  }

  func disableRawMode() throws {
    recorder.append("disable-raw-mode")
    if failsDisableRawMode {
      throw HandoffTestError.rawModeExitFailed
    }
  }

  func write(_: String) throws {}
  func writeClipboard(_: String) throws -> Bool {
    recorder.append("clipboard-write")
    return true
  }
  func readClipboard() throws -> String? {
    recorder.append("clipboard-read")
    return "clipboard"
  }
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}

@MainActor
private func makeHandoffRunLoop(
  recorder: HandoffRecorder,
  environmentValues: EnvironmentValues = .init(),
  failsDisableRawMode: Bool = false,
  failsEnableRawMode: Bool = false
) -> (
  runLoop: RunLoop<Int, Text>,
  scheduler: FrameScheduler
) {
  let rootIdentity = testIdentity("TerminalHandoffRuntimeTests")
  let scheduler = FrameScheduler()
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    renderer: DefaultRenderer(),
    presentationSurface: HandoffTerminalHost(
      recorder: recorder,
      failsDisableRawMode: failsDisableRawMode,
      failsEnableRawMode: failsEnableRawMode
    ),
    terminalInputReader: HandoffInputReader(recorder: recorder),
    scheduler: scheduler,
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
    environmentValues: environmentValues,
    viewBuilder: { _, _ in Text("handoff") }
  )
  runLoop.activateTerminalHandoffSession()
  return (runLoop, scheduler)
}
