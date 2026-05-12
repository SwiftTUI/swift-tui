/// One node in a terminal workspace pane tree.
public indirect enum TerminalWorkspaceNode: Hashable, Codable, Sendable {
  case terminal(TerminalPaneSpec)
  case split(TerminalSplit)

  public var paneIDs: [TerminalPaneID] {
    switch self {
    case .terminal(let pane):
      [pane.id]
    case .split(let split):
      split.first.paneIDs + split.second.paneIDs
    }
  }

  public var panes: [TerminalPaneSpec] {
    switch self {
    case .terminal(let pane):
      [pane]
    case .split(let split):
      split.first.panes + split.second.panes
    }
  }

  public func contains(_ paneID: TerminalPaneID) -> Bool {
    paneIDs.contains(paneID)
  }

  public func pane(id paneID: TerminalPaneID) -> TerminalPaneSpec? {
    switch self {
    case .terminal(let pane):
      pane.id == paneID ? pane : nil
    case .split(let split):
      split.first.pane(id: paneID) ?? split.second.pane(id: paneID)
    }
  }
}

/// A binary split between two workspace nodes.
public struct TerminalSplit: Hashable, Codable, Sendable {
  public var axis: TerminalSplitAxis
  public var fraction: Double
  public var first: TerminalWorkspaceNode
  public var second: TerminalWorkspaceNode

  public init(
    axis: TerminalSplitAxis,
    fraction: Double = 0.5,
    first: TerminalWorkspaceNode,
    second: TerminalWorkspaceNode
  ) {
    self.axis = axis
    self.fraction = Self.clampedFraction(fraction)
    self.first = first
    self.second = second
  }

  static func clampedFraction(_ fraction: Double) -> Double {
    min(max(fraction, 0.1), 0.9)
  }
}
