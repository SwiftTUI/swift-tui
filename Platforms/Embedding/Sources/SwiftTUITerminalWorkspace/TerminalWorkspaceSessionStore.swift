public import SwiftTUITerminal

/// Retains terminal process sessions by pane identity.
@MainActor
public final class TerminalWorkspaceSessionStore {
  private var sessions: [TerminalPaneID: TerminalProcessSession] = [:]

  public init() {}

  public var sessionCount: Int {
    sessions.count
  }

  public func containsSession(for paneID: TerminalPaneID) -> Bool {
    sessions[paneID] != nil
  }

  public func session(for pane: TerminalPaneSpec) -> TerminalProcessSession {
    if let session = sessions[pane.id] {
      return session
    }

    let session = TerminalProcessSession(
      command: pane.command,
      arguments: pane.arguments,
      environment: pane.environment,
      workingDirectory: pane.workingDirectory,
      initialSize: pane.initialSize
    )
    sessions[pane.id] = session
    return session
  }

  public func removeSession(for paneID: TerminalPaneID) {
    guard let session = sessions.removeValue(forKey: paneID) else {
      return
    }
    Task {
      await session.terminate()
    }
  }

  public func removeSessions(except livePaneIDs: some Sequence<TerminalPaneID>) {
    let live = Set(livePaneIDs)
    for paneID in sessions.keys where !live.contains(paneID) {
      removeSession(for: paneID)
    }
  }

  public func removeAllSessions() {
    for paneID in Array(sessions.keys) {
      removeSession(for: paneID)
    }
  }
}
