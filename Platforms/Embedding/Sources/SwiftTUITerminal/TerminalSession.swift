public import SwiftTUICore

public protocol TerminalSession: AnyObject, Sendable {
  var cachedSnapshot: ForeignGrid { get }

  func start() async throws
  func snapshot() async -> ForeignGrid
  func currentTitle() async -> String?
  func currentWorkingDirectory() async -> String?
  func currentLifecycle() async -> TerminalLifecycle
  func send(key: TerminalEmulatorKey) async
  func send(paste: String) async
  func resize(_ size: CellSize) async throws
  func events() -> AsyncStream<TerminalEmulatorEvent>
}

public enum TerminalLifecycle: Sendable, Equatable {
  case notStarted
  case running
  case exited(reason: TerminalExitReason)
}

public enum TerminalExitReason: Sendable, Equatable {
  case normal(code: Int32)
  case signal(Int32)
  case sessionClosed
}
