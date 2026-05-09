import SwiftTUI
import SwiftTUICore
import Synchronization
import Testing

@testable import SwiftTUITerminal

@MainActor
@Suite("TerminalView layout")
struct TerminalViewLayoutTests {
  @Test("TerminalView accepts the parent's full proposal")
  func acceptsProposal() {
    let session = StubTerminalSession(grid: ForeignGrid.empty)
    let artifacts = DefaultRenderer().render(
      TerminalView(session: session),
      proposal: ProposedSize(width: 40, height: 12)
    )

    #expect(artifacts.rasterSurface.size == CellSize(width: 40, height: 12))
  }

  @Test("draw emits exactly one foreignSurface command at the assigned bounds")
  func emitsForeignSurface() {
    let row = Array(repeating: RasterCell(character: "x"), count: 4)
    let grid = ForeignGrid(
      size: CellSize(width: 4, height: 2),
      cells: Array(repeating: row, count: 2)
    )
    let session = StubTerminalSession(grid: grid)
    let artifacts = DefaultRenderer().render(
      TerminalView(session: session),
      proposal: ProposedSize(width: 4, height: 2)
    )

    let surfaces = allCommands(in: artifacts.drawTree).compactMap { command -> CellRect? in
      if case .foreignSurface(let bounds, _) = command {
        return bounds
      }
      return nil
    }

    #expect(surfaces == [CellRect(origin: .zero, size: CellSize(width: 4, height: 2))])
  }

  @Test("render registers one lifecycle task for start, resize, and event consumption")
  func registersLifecycleTask() {
    let session = StubTerminalSession(grid: ForeignGrid.empty)
    let artifacts = DefaultRenderer().render(
      TerminalView(session: session),
      proposal: ProposedSize(width: 7, height: 3)
    )

    let taskStarts = artifacts.commitPlan.lifecycle.compactMap { entry -> TaskDescriptor? in
      if case .taskStart(let descriptor) = entry.operation {
        return descriptor
      }
      return nil
    }

    #expect(taskStarts.count == 1)
    #expect(taskStarts.first?.priority == .userInitiated)
  }

  @Test("TerminalView forwards child clipboard requests to the host clipboard action")
  func forwardsChildClipboardRequests() async throws {
    let session = EventingTerminalSession(grid: ForeignGrid.empty)
    let inputReader = ClipboardTerminalInputReader()
    let host = ClipboardTerminalHost()
    let rootIdentity = Identity(components: [.named("TerminalViewClipboardRoot")])
    let runLoop = SwiftTUI.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: ClipboardSignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: ProposedSize(width: 8, height: 2),
      exitKeyBindings: .none,
      viewBuilder: { _, _ in
        TerminalView(session: session)
      }
    )

    let task = Task {
      try await runLoop.run()
    }

    try await waitUntil("session started") {
      session.isStarted
    }
    session.publish(.clipboardWriteRequested(Array("child text".utf8)))

    try await waitUntil("clipboard write") {
      host.clipboardWrites == ["child text"]
    }

    inputReader.finish()
    let result = try await task.value
    #expect(result.exitReason == .inputEnded)
  }
}

private final class StubTerminalSession: TerminalSession {
  private let snapshotStorage: Mutex<ForeignGrid>

  init(grid: ForeignGrid) {
    snapshotStorage = Mutex(grid)
  }

  var cachedSnapshot: ForeignGrid {
    snapshotStorage.withLock { $0 }
  }

  func start() async throws {}

  func snapshot() async -> ForeignGrid {
    cachedSnapshot
  }

  func currentTitle() async -> String? {
    nil
  }

  func currentWorkingDirectory() async -> String? {
    nil
  }

  func currentLifecycle() async -> TerminalLifecycle {
    .notStarted
  }

  func send(key _: TerminalEmulatorKey) async {}

  func send(paste _: String) async {}

  func send(mouse _: TerminalEmulatorMouse) async {}

  func resize(_ size: CellSize) async throws {
    snapshotStorage.withLock { grid in
      grid.size = size
    }
  }

  func events() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class EventingTerminalSession: TerminalSession, Sendable {
  private struct State: Sendable {
    var snapshot: ForeignGrid
    var continuation: AsyncStream<TerminalEmulatorEvent>.Continuation?
    var isStarted = false
  }

  private let state: Mutex<State>

  init(grid: ForeignGrid) {
    state = Mutex(State(snapshot: grid))
  }

  var cachedSnapshot: ForeignGrid {
    state.withLock(\.snapshot)
  }

  var isStarted: Bool {
    state.withLock(\.isStarted)
  }

  func start() async throws {
    state.withLock { state in
      state.isStarted = true
    }
  }

  func snapshot() async -> ForeignGrid {
    cachedSnapshot
  }

  func currentTitle() async -> String? {
    nil
  }

  func currentWorkingDirectory() async -> String? {
    nil
  }

  func currentLifecycle() async -> TerminalLifecycle {
    .running
  }

  func send(key _: TerminalEmulatorKey) async {}

  func send(paste _: String) async {}

  func send(mouse _: TerminalEmulatorMouse) async {}

  func resize(_ size: CellSize) async throws {
    state.withLock { state in
      state.snapshot.size = size
    }
  }

  func events() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { continuation in
      state.withLock { state in
        state.continuation = continuation
      }
    }
  }

  func publish(
    _ event: TerminalEmulatorEvent
  ) {
    state.withLock(\.continuation)?.yield(event)
  }
}

private final class ClipboardTerminalHost: PresentationSurface, ClipboardWritingPresentationSurface
{
  var surfaceSize: CellSize { .init(width: 8, height: 2) }
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private let clipboardWritesStorage = Mutex<[String]>([])

  var clipboardWrites: [String] {
    clipboardWritesStorage.withLock { $0 }
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  @MainActor
  func writeClipboard(_ text: String) throws -> Bool {
    clipboardWritesStorage.withLock { $0.append(text) }
    return true
  }
}

private final class ClipboardTerminalInputReader: TerminalInputReading, Sendable {
  private struct State: Sendable {
    var continuation: AsyncStream<InputEvent>.Continuation?
    var finished = false
  }

  private let state = Mutex(State())

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let shouldFinish = state.withLock { state in
        if state.finished {
          return true
        }
        state.continuation = continuation
        return false
      }

      if shouldFinish {
        continuation.finish()
      }
    }
  }

  func finish() {
    let continuation = state.withLock { state in
      state.finished = true
      let continuation = state.continuation
      state.continuation = nil
      return continuation
    }
    continuation?.finish()
  }
}

private final class ClipboardSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private func allCommands(in node: DrawNode) -> [DrawCommand] {
  node.commands
    + node.children.flatMap(allCommands(in:))
    + node.postCommands
}

private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  pollNanoseconds: UInt64 = 10_000_000,
  condition: @escaping () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let start = clock.now

  while !(await condition()) {
    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw TerminalViewLayoutTestTimeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private struct TerminalViewLayoutTestTimeout: Error, CustomStringConvertible {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var description: String {
    "Timed out waiting for \(label)"
  }
}
