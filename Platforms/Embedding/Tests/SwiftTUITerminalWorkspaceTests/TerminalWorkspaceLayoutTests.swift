import SwiftTUICore
import SwiftTUITerminalWorkspace
import Testing

@Suite("Terminal workspace layout")
struct TerminalWorkspaceLayoutTests {
  @Test("horizontal split divides width and preserves height")
  func horizontalSplit() {
    let split = TerminalSplit(
      axis: .horizontal,
      fraction: 0.25,
      first: .terminal(TerminalPaneSpec(id: "left", title: "left", command: "")),
      second: .terminal(TerminalPaneSpec(id: "right", title: "right", command: ""))
    )

    let rects = TerminalWorkspaceLayout.splitRects(
      for: split,
      in: CellRect(origin: .zero, size: CellSize(width: 80, height: 24))
    )

    #expect(rects.first.size == CellSize(width: 20, height: 24))
    #expect(rects.second.origin == CellPoint(x: 20, y: 0))
    #expect(rects.second.size == CellSize(width: 60, height: 24))
  }

  @Test("zoomed pane receives the full workspace rect")
  func zoomedPaneReceivesFullRect() {
    var state = TerminalWorkspaceState(
      tabs: [
        TerminalWorkspaceTab(
          id: "dev",
          title: "dev",
          root: .split(
            TerminalSplit(
              axis: .horizontal,
              first: .terminal(TerminalPaneSpec(id: "left", title: "left", command: "")),
              second: .terminal(TerminalPaneSpec(id: "right", title: "right", command: ""))
            )
          )
        )
      ]
    )
    state.focusPane("right")
    state.toggleZoom()

    let frames = TerminalWorkspaceLayout.frames(for: state, in: CellSize(width: 100, height: 40))

    #expect(
      frames == [
        TerminalWorkspacePaneFrame(
          paneID: "right",
          rect: CellRect(origin: .zero, size: CellSize(width: 100, height: 40))
        )
      ])
  }
}
