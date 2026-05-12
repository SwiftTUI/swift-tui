/// A titled pane tree in a terminal workspace.
public struct TerminalWorkspaceTab: Identifiable, Hashable, Codable, Sendable {
  public var id: TerminalWorkspaceTabID
  public var title: String
  public var root: TerminalWorkspaceNode

  public init(
    id: TerminalWorkspaceTabID,
    title: String,
    root: TerminalWorkspaceNode
  ) {
    self.id = id
    self.title = title
    self.root = root
  }

  public var paneIDs: [TerminalPaneID] {
    root.paneIDs
  }

  public var panes: [TerminalPaneSpec] {
    root.panes
  }

  public func contains(_ paneID: TerminalPaneID) -> Bool {
    root.contains(paneID)
  }
}
