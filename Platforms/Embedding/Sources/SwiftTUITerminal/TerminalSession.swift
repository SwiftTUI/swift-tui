// This whole module is compiled out on Windows: the dependency edges to
// SwiftTerm and the PTY layer are platform-conditional in Package.swift, so
// the target must compile to an empty module there.
#if !os(Windows)
  public import SwiftTUICore
  public import SwiftTUITerminalEmulation

  public protocol TerminalSession: AnyObject, Sendable {
    var cachedSnapshot: ForeignGrid { get }

    func start() async throws
    func snapshot() async -> ForeignGrid
    func currentTitle() async -> String?
    func currentWorkingDirectory() async -> String?
    func currentLifecycle() async -> TerminalLifecycle
    func send(key: TerminalEmulatorKey) async
    func send(paste: String) async
    func send(mouse: TerminalEmulatorMouse) async
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
#endif
