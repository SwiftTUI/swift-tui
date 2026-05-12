public import SwiftTUICore

/// The computed bounds for one terminal pane.
public struct TerminalWorkspacePaneFrame: Hashable, Sendable {
  public var paneID: TerminalPaneID
  public var rect: CellRect

  public init(
    paneID: TerminalPaneID,
    rect: CellRect
  ) {
    self.paneID = paneID
    self.rect = rect
  }
}

/// Pure layout math for a terminal workspace pane tree.
public enum TerminalWorkspaceLayout {
  public static func frames(
    for state: TerminalWorkspaceState,
    in size: CellSize
  ) -> [TerminalWorkspacePaneFrame] {
    guard let tab = state.activeTab else {
      return []
    }

    let bounds = CellRect(origin: .zero, size: size)
    if let zoomedPaneID = state.zoomedPaneID, tab.contains(zoomedPaneID) {
      return [TerminalWorkspacePaneFrame(paneID: zoomedPaneID, rect: bounds)]
    }

    return frames(for: tab.root, in: bounds)
  }

  public static func frames(
    for node: TerminalWorkspaceNode,
    in rect: CellRect
  ) -> [TerminalWorkspacePaneFrame] {
    switch node {
    case .terminal(let pane):
      return [TerminalWorkspacePaneFrame(paneID: pane.id, rect: rect)]
    case .split(let split):
      let children = splitRects(for: split, in: rect)
      return frames(for: split.first, in: children.first)
        + frames(for: split.second, in: children.second)
    }
  }

  public static func splitRects(
    for split: TerminalSplit,
    in rect: CellRect
  ) -> (first: CellRect, second: CellRect) {
    switch split.axis {
    case .horizontal:
      let firstWidth = splitExtent(total: rect.size.width, fraction: split.fraction)
      let secondWidth = max(0, rect.size.width - firstWidth)
      return (
        CellRect(origin: rect.origin, size: CellSize(width: firstWidth, height: rect.size.height)),
        CellRect(
          origin: CellPoint(x: rect.origin.x + firstWidth, y: rect.origin.y),
          size: CellSize(width: secondWidth, height: rect.size.height)
        )
      )
    case .vertical:
      let firstHeight = splitExtent(total: rect.size.height, fraction: split.fraction)
      let secondHeight = max(0, rect.size.height - firstHeight)
      return (
        CellRect(origin: rect.origin, size: CellSize(width: rect.size.width, height: firstHeight)),
        CellRect(
          origin: CellPoint(x: rect.origin.x, y: rect.origin.y + firstHeight),
          size: CellSize(width: rect.size.width, height: secondHeight)
        )
      )
    }
  }

  private static func splitExtent(total: Int, fraction: Double) -> Int {
    guard total > 1 else {
      return total
    }
    return min(
      max(1, Int((Double(total) * TerminalSplit.clampedFraction(fraction)).rounded())), total - 1)
  }
}
