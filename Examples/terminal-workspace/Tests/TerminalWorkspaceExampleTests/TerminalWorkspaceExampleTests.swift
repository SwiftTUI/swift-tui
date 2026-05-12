import SwiftTUITerminalWorkspace
import TerminalWorkspaceExample
import Testing

struct TerminalWorkspaceExampleTests {
  @Test("initial workspace has useful dev and ops tabs")
  func initialWorkspaceShape() {
    let workspace = TerminalWorkspaceExampleModel.initialWorkspace(workingDirectory: "/tmp")

    #expect(workspace.tabs.map(\.id) == ["dev", "ops"])
    #expect(workspace.activeTabID == "dev")
    #expect(workspace.focusedPaneID == "dev-shell")
    #expect(workspace.allPaneIDs.contains("git-status"))
    #expect(workspace.allPaneIDs.contains("processes"))
  }
}
