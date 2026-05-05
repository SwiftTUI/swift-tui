public import SwiftTUICore
import SwiftTUIPTYPrimitives
import Synchronization

public final class TerminalProcessSession: TerminalSession {
  private let pty: ChildProcessPty
  private let emulator: TerminalEmulator
  private let state: TerminalProcessSessionStateStore
  private let eventBroadcaster = TerminalEventBroadcaster()

  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: String? = nil,
    initialSize: CellSize
  ) {
    self.pty = ChildProcessPty(
      executable: command,
      arguments: arguments,
      environment: environment,
      workingDirectory: workingDirectory,
      initialSize: initialSize
    )
    self.emulator = TerminalEmulator(size: initialSize)
    self.state = TerminalProcessSessionStateStore(
      cachedSnapshot: Self.emptyGrid(size: initialSize)
    )
  }

  public var cachedSnapshot: ForeignGrid {
    state.cachedSnapshot
  }

  public func start() async throws {
    let shouldStart = state.markStarting()
    guard shouldStart else {
      return
    }

    do {
      try await pty.start()
    } catch {
      state.markExited(reason: .sessionClosed)
      eventBroadcaster.finish()
      throw error
    }

    guard let pair = await pty.pair else {
      state.markExited(reason: .sessionClosed)
      eventBroadcaster.finish()
      return
    }

    let task = Task { [pty, emulator, state, eventBroadcaster] in
      let stream = await pair.read()
      for await chunk in stream {
        let events = await emulator.feed(chunk)
        let snapshot = await emulator.snapshot()
        state.update(snapshot: snapshot, events: events)
        for event in events {
          eventBroadcaster.publish(event)
          if case .clientReply(let replyBytes) = event {
            try? await pair.write(replyBytes)
          }
        }
      }

      let exitStatus = await pty.waitForExit()
      state.markExited(reason: Self.reason(from: exitStatus))
      eventBroadcaster.finish()
    }

    state.setPumpTask(task)
  }

  public func snapshot() async -> ForeignGrid {
    let snapshot = await emulator.snapshot()
    state.setCachedSnapshot(snapshot)
    return snapshot
  }

  public func currentTitle() async -> String? {
    state.title
  }

  public func currentWorkingDirectory() async -> String? {
    state.workingDirectory
  }

  public func currentLifecycle() async -> TerminalLifecycle {
    state.lifecycle
  }

  public func send(key: TerminalEmulatorKey) async {
    let bytes = await emulator.encode(key: key)
    guard !bytes.isEmpty, let pair = await pty.pair else {
      return
    }
    try? await pair.write(bytes)
  }

  public func send(paste: String) async {
    let bytes = await emulator.encode(paste: paste)
    guard !bytes.isEmpty, let pair = await pty.pair else {
      return
    }
    try? await pair.write(bytes)
  }

  public func send(mouse: TerminalEmulatorMouse) async {
    let bytes = await emulator.send(mouse: mouse)
    guard !bytes.isEmpty, let pair = await pty.pair else {
      return
    }
    try? await pair.write(bytes)
  }

  public func resize(_ size: CellSize) async throws {
    guard let pair = await pty.pair else {
      return
    }

    try await pair.resize(size)
    await emulator.resize(size)
    let snapshot = await emulator.snapshot()
    let event = TerminalEmulatorEvent.sizeReported(size)
    state.update(snapshot: snapshot, events: [event])
    eventBroadcaster.publish(event)
  }

  public func events() -> AsyncStream<TerminalEmulatorEvent> {
    eventBroadcaster.stream()
  }

  private static func reason(from exitStatus: ChildProcessPty.ExitStatus) -> TerminalExitReason {
    switch exitStatus {
    case .exited(let code):
      return .normal(code: code)
    case .signalled(let signal):
      return .signal(signal)
    case .unknown:
      return .sessionClosed
    }
  }

  private static func emptyGrid(size: CellSize) -> ForeignGrid {
    let row = Array(repeating: RasterCell.empty, count: max(0, size.width))
    return ForeignGrid(
      size: size,
      cells: Array(repeating: row, count: max(0, size.height))
    )
  }
}

private final class TerminalProcessSessionStateStore: Sendable {
  private let storage: Mutex<TerminalProcessSessionState>

  init(cachedSnapshot: ForeignGrid) {
    storage = Mutex(TerminalProcessSessionState(cachedSnapshot: cachedSnapshot))
  }

  var cachedSnapshot: ForeignGrid {
    storage.withLock { $0.cachedSnapshot }
  }

  var title: String? {
    storage.withLock { $0.title }
  }

  var workingDirectory: String? {
    storage.withLock { $0.workingDirectory }
  }

  var lifecycle: TerminalLifecycle {
    storage.withLock { $0.lifecycle }
  }

  func markStarting() -> Bool {
    storage.withLock { state in
      switch state.lifecycle {
      case .notStarted:
        state.lifecycle = .running
        return state.pumpTask == nil
      case .running, .exited:
        return false
      }
    }
  }

  func markExited(reason: TerminalExitReason) {
    storage.withLock { state in
      state.lifecycle = .exited(reason: reason)
      state.pumpTask = nil
    }
  }

  func setPumpTask(_ task: Task<Void, Never>) {
    storage.withLock { $0.pumpTask = task }
  }

  func setCachedSnapshot(_ snapshot: ForeignGrid) {
    storage.withLock { $0.cachedSnapshot = snapshot }
  }

  func update(snapshot: ForeignGrid, events: [TerminalEmulatorEvent]) {
    storage.withLock { state in
      state.cachedSnapshot = snapshot
      state.apply(events: events)
    }
  }
}

private struct TerminalProcessSessionState: Sendable {
  var lifecycle: TerminalLifecycle = .notStarted
  var title: String?
  var workingDirectory: String?
  var cachedSnapshot: ForeignGrid
  var pumpTask: Task<Void, Never>?

  mutating func apply(events: [TerminalEmulatorEvent]) {
    for event in events {
      switch event {
      case .titleChanged(let newTitle):
        title = newTitle
      case .workingDirectoryChanged(let directory):
        workingDirectory = directory
      default:
        break
      }
    }
  }
}

private final class TerminalEventBroadcaster: Sendable {
  private let state = Mutex(TerminalEventBroadcasterState())

  func stream() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { continuation in
      let id = state.withLock { state in
        let id = state.nextID
        state.nextID += 1
        state.continuations[id] = continuation
        return id
      }

      continuation.onTermination = { @Sendable [weak self] _ in
        self?.removeContinuation(id: id)
      }
    }
  }

  func publish(_ event: TerminalEmulatorEvent) {
    let continuations = state.withLock { Array($0.continuations.values) }
    for continuation in continuations {
      continuation.yield(event)
    }
  }

  func finish() {
    let continuations = state.withLock { state in
      let continuations = Array(state.continuations.values)
      state.continuations.removeAll()
      return continuations
    }
    for continuation in continuations {
      continuation.finish()
    }
  }

  private func removeContinuation(id: Int) {
    state.withLock { $0.continuations[id] = nil }
  }
}

private struct TerminalEventBroadcasterState {
  var nextID = 0
  var continuations: [Int: AsyncStream<TerminalEmulatorEvent>.Continuation] = [:]
}
