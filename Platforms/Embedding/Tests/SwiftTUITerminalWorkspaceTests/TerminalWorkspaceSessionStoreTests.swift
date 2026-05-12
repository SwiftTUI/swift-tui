import SwiftTUITerminalWorkspace
import Testing

@MainActor
@Suite("Terminal workspace session store")
struct TerminalWorkspaceSessionStoreTests {
  @Test("sessions are retained by pane id")
  func sessionsAreRetainedByPaneID() {
    let store = TerminalWorkspaceSessionStore()
    let pane = TerminalPaneSpec(id: "shell", title: "shell", command: "/bin/sh")

    let first = store.session(for: pane)
    let second = store.session(for: pane)

    #expect(first === second)
    #expect(store.sessionCount == 1)
  }

  @Test("removing absent pane ids preserves retained sessions")
  func removeSessionsExcept() {
    let store = TerminalWorkspaceSessionStore()
    _ = store.session(for: TerminalPaneSpec(id: "one", title: "one", command: "/bin/sh"))
    _ = store.session(for: TerminalPaneSpec(id: "two", title: "two", command: "/bin/sh"))

    store.removeSessions(except: [TerminalPaneID("two")])

    #expect(!store.containsSession(for: "one"))
    #expect(store.containsSession(for: "two"))
    #expect(store.sessionCount == 1)
  }
}
