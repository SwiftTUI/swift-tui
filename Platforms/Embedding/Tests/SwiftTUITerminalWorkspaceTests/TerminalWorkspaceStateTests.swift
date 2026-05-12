import Foundation
import SwiftTUICore
import SwiftTUITerminalWorkspace
import Testing

@Suite("Terminal workspace state")
struct TerminalWorkspaceStateTests {
  @Test("splitting focused pane adds a stable pane and focuses it")
  func splittingFocusedPane() {
    var state = makeWorkspace()

    state.splitFocusedPane(
      axis: .horizontal,
      newPane: TerminalPaneSpec(id: "logs", title: "logs", command: "/usr/bin/log")
    )

    #expect(state.activePaneIDs == ["shell", "logs"])
    #expect(state.focusedPaneID == "logs")
    #expect(
      state.activeTab?.root
        == .split(
          TerminalSplit(
            axis: .horizontal,
            first: .terminal(.shell(id: "shell", title: "shell", command: "/bin/sh")),
            second: .terminal(TerminalPaneSpec(id: "logs", title: "logs", command: "/usr/bin/log"))
          )
        ))
  }

  @Test("closing a nested pane promotes its sibling without dropping the whole branch")
  func closingNestedPanePromotesSibling() {
    var state = makeWorkspace()
    state.splitFocusedPane(
      axis: .horizontal,
      newPane: TerminalPaneSpec(id: "logs", title: "logs", command: "/usr/bin/log")
    )
    state.focusPane("shell")
    state.splitFocusedPane(
      axis: .vertical,
      newPane: TerminalPaneSpec(id: "tests", title: "tests", command: "/usr/bin/true")
    )

    state.focusPane("tests")
    let removed = state.closeFocusedPane()

    #expect(removed == "tests")
    #expect(state.activePaneIDs == ["shell", "logs"])
    #expect(state.activeTab?.root.paneIDs == ["shell", "logs"])
  }

  @Test("directional focus uses pane frames before falling back to tree order")
  func directionalFocusUsesFrames() {
    var state = makeWorkspace()
    state.splitFocusedPane(
      axis: .horizontal,
      newPane: TerminalPaneSpec(id: "right", title: "right", command: "/bin/sh")
    )
    state.focusPane("shell")

    state.focus(.right, within: CellSize(width: 100, height: 30))

    #expect(state.focusedPaneID == "right")
  }

  @Test("workspace state round trips layout and command metadata")
  func codableRoundTrip() throws {
    var state = makeWorkspace()
    state.splitFocusedPane(
      axis: .horizontal,
      newPane: TerminalPaneSpec(
        id: "logs",
        title: "logs",
        command: "/usr/bin/env",
        arguments: ["tail", "-f", "app.log"],
        environment: ["TERM": "xterm-256color"],
        workingDirectory: "/tmp"
      )
    )
    state.toggleZoom()

    let encoded = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(TerminalWorkspaceState.self, from: encoded)

    #expect(decoded == state)
  }

  private func makeWorkspace() -> TerminalWorkspaceState {
    TerminalWorkspaceState(
      tabs: [
        TerminalWorkspaceTab(
          id: "dev",
          title: "dev",
          root: .terminal(.shell(id: "shell", title: "shell", command: "/bin/sh"))
        )
      ]
    )
  }
}
