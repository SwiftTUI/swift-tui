@unsafe @preconcurrency import Dispatch
import Foundation
import Synchronization
import Testing

@testable import TerminalUI
@testable import View

@MainActor
@Suite(.serialized)
struct AsyncFrameTailRenderingTests {
  @Test("blocked async frame tail queues input without committing ahead")
  func blockedFrameTailQueuesInputWithoutCommittingAhead() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailRoot")
    let gate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let lifecycleRecorder = AsyncFrameTailLifecycleRecorder()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      terminalHost: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailStressView(
          value: value,
          lifecycleRecorder: lifecycleRecorder
        )
      }
    )

    let runTask = Task {
      try await runLoop.run()
    }

    await gate.waitUntilBlocked()
    #expect(terminal.frames.isEmpty)

    inputReader.send(.key(.character("i")))
    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()

    #expect(terminal.frames.isEmpty)
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.finalState == 1)
    #expect(gate.rasterEntryCount >= 3)
    #expect(terminal.frames.count >= 2)
    #expect(terminal.frames.first?.contains("value 0") == true)
    #expect(terminal.frames.last?.contains("value 1") == true)
    #expect(lifecycleRecorder.events == ["appear 0", "appear 1"])
  }

  @Test("diagnostics count input queued during async render suspension")
  func diagnosticsCountInputQueuedDuringAsyncRenderSuspension() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailDiagnosticsRoot")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-async-tail-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let lifecycleRecorder = AsyncFrameTailLifecycleRecorder()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      terminalHost: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailStressView(
          value: value,
          lifecycleRecorder: lifecycleRecorder
        )
      }
    )
    runLoop.diagnosticsLogger = FrameDiagnosticsLogger(path: diagnosticsURL.path)
    #expect(runLoop.diagnosticsLogger != nil)

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("value 0") }
    }

    inputReader.send(.key(.character("i")))
    await gate.waitUntilBlocked()
    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }
    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(
      rows.contains { row in
        (Int(row["input_events_during_render_suspension"] ?? "") ?? 0) >= 1
      })
    #expect(
      rows.allSatisfy { row in
        row["main_actor_blocked_ms"] != nil
          && row["main_actor_suspended_ms"] != nil
      })
  }

  @Test("worker backlog commits blocked frame before later input batch")
  func workerBacklogCommitsBlockedFrameBeforeLaterInputBatch() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailBacklogRoot")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      terminalHost: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailCounterView(value: value)
      }
    )

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("value 0") }
    }

    inputReader.send(.key(.character("i")))
    await gate.waitUntilBlocked()
    #expect(terminal.frames.contains { $0.contains("value 1") } == false)

    inputReader.send(.key(.character("i")))
    inputReader.send(.key(.character("i")))
    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.finalState == 3)
    let value1Index = terminal.frames.firstIndex { $0.contains("value 1") }
    let value3Index = terminal.frames.firstIndex { $0.contains("value 3") }
    #expect(value1Index != nil)
    #expect(value3Index != nil)
    if let value1Index, let value3Index {
      #expect(value1Index < value3Index)
    }
  }

  @Test("async renderer records worker timing diagnostics")
  func asyncRendererRecordsWorkerTimingDiagnostics() async {
    let artifacts = await DefaultRenderer().renderAsync(
      VStack(alignment: .leading, spacing: 1) {
        Text("Async")
        Text("Diagnostics")
      },
      context: .init(identity: testIdentity("AsyncTimingRoot"))
    )

    #expect(artifacts.diagnostics.phaseTimings != nil)
    #expect(artifacts.diagnostics.workerTimings != nil)
    #expect(artifacts.diagnostics.mainActorTimings != nil)
  }
}

private struct AsyncFrameTailCounterView: View {
  var value: Int

  var body: some View {
    Text("value \(value)")
      .id(testIdentity("AsyncFrameTailCounterValue", "\(value)"))
  }
}

private struct AsyncFrameTailStressView: View {
  @FocusState private var focusedField: AsyncFrameTailFocusField?

  var value: Int
  var lifecycleRecorder: AsyncFrameTailLifecycleRecorder

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Focusable") {}
        .id(testIdentity("AsyncFrameTailFocus"))
        .focused($focusedField, equals: .button)
      if value == 0 {
        Text("value 0")
          .id(testIdentity("AsyncFrameTailValue", "zero"))
          .onAppear {
            lifecycleRecorder.record("appear 0")
          }
          .onDisappear {
            lifecycleRecorder.record("disappear 0")
          }
      } else {
        Text("value 1")
          .id(testIdentity("AsyncFrameTailValue", "one"))
          .onAppear {
            lifecycleRecorder.record("appear 1")
          }
          .onDisappear {
            lifecycleRecorder.record("disappear 1")
          }
      }
    }
    .defaultFocus($focusedField, .button)
  }
}

private enum AsyncFrameTailFocusField: Hashable {
  case button
}

@MainActor
private final class AsyncFrameTailLifecycleRecorder {
  var events: [String] = []

  func record(_ event: String) {
    events.append(event)
  }
}

private final class AsyncFrameTailBlockingGate: Sendable {
  private struct State: Sendable {
    var rasterEntryCount = 0
  }

  private let blockingEntry: Int
  private let state = Mutex(State())
  private let entered = DispatchSemaphore(value: 0)
  private let releaseSemaphore = DispatchSemaphore(value: 0)

  init(blockingEntry: Int = 1) {
    self.blockingEntry = blockingEntry
  }

  var rasterEntryCount: Int {
    state.withLock(\.rasterEntryCount)
  }

  func beforeRaster() {
    let shouldBlock = state.withLock { state in
      state.rasterEntryCount += 1
      return state.rasterEntryCount == blockingEntry
    }
    guard shouldBlock else {
      return
    }

    entered.signal()
    releaseSemaphore.wait()
  }

  func waitUntilBlocked() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        self.entered.wait()
        continuation.resume()
      }
    }
  }

  func release() {
    releaseSemaphore.signal()
  }
}

private final class AsyncFrameTailTerminalHost: TerminalHosting {
  var surfaceSize: Size {
    size
  }
  let size = Size(width: 32, height: 6)
  let proposal = ProposedSize(width: 32, height: 6)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var frames: [String] = []

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )
    .render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    return .fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
  }
}

private struct AsyncFrameTailTimeout: Error {}

@MainActor
private func waitUntil(
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  _ condition: () -> Bool
) async throws {
  let started = ContinuousClock().now
  while !condition() {
    if started.duration(to: ContinuousClock().now) > .nanoseconds(Int64(timeoutNanoseconds)) {
      throw AsyncFrameTailTimeout()
    }
    try await Task.sleep(nanoseconds: 1_000_000)
  }
}

private func diagnosticRows(_ text: String) -> [[String: String]] {
  let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
  guard let headerLine = lines.first else {
    return []
  }
  let headers = headerLine.components(separatedBy: "\t")
  return lines.dropFirst().map { line in
    let fields = line.components(separatedBy: "\t")
    var row: [String: String] = [:]
    for (index, header) in headers.enumerated() where index < fields.count {
      row[header] = fields[index]
    }
    return row
  }
}

private func valueWithTimeout<Value: Sendable>(
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
  try await withThrowingTaskGroup(of: Value.self) { group in
    group.addTask {
      try await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      throw AsyncFrameTailTimeout()
    }

    let value = try await group.next()!
    group.cancelAll()
    return value
  }
}
