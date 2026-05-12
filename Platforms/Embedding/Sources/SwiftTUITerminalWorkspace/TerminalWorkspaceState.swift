public import SwiftTUICore

/// Serializable state for a terminal workspace.
public struct TerminalWorkspaceState: Hashable, Codable, Sendable {
  public var tabs: [TerminalWorkspaceTab]
  public var activeTabID: TerminalWorkspaceTabID?
  public var focusedPaneID: TerminalPaneID?
  public var zoomedPaneID: TerminalPaneID?

  public init(
    tabs: [TerminalWorkspaceTab],
    activeTabID: TerminalWorkspaceTabID? = nil,
    focusedPaneID: TerminalPaneID? = nil,
    zoomedPaneID: TerminalPaneID? = nil
  ) {
    self.tabs = tabs
    self.activeTabID = activeTabID ?? tabs.first?.id
    self.focusedPaneID = focusedPaneID ?? tabs.first?.paneIDs.first
    self.zoomedPaneID = zoomedPaneID
    normalizeFocus()
  }

  public var activeTab: TerminalWorkspaceTab? {
    guard let activeTabID else {
      return tabs.first
    }
    return tabs.first { $0.id == activeTabID } ?? tabs.first
  }

  public var activeTabIndex: Int? {
    guard let tab = activeTab else {
      return nil
    }
    return tabs.firstIndex { $0.id == tab.id }
  }

  public var focusedPane: TerminalPaneSpec? {
    guard let focusedPaneID else {
      return activeTab?.panes.first
    }
    return activeTab?.root.pane(id: focusedPaneID) ?? activeTab?.panes.first
  }

  public var activePaneIDs: [TerminalPaneID] {
    activeTab?.paneIDs ?? []
  }

  public var allPaneIDs: [TerminalPaneID] {
    tabs.flatMap(\.paneIDs)
  }

  public var canCloseFocusedPane: Bool {
    activePaneIDs.count > 1
  }

  public mutating func selectTab(_ id: TerminalWorkspaceTabID) {
    guard tabs.contains(where: { $0.id == id }) else {
      return
    }
    activeTabID = id
    zoomedPaneID = nil
    normalizeFocus()
  }

  public mutating func focusPane(_ id: TerminalPaneID) {
    guard activeTab?.contains(id) == true else {
      return
    }
    focusedPaneID = id
  }

  public mutating func focusNextPane() {
    moveFocus(by: 1)
  }

  public mutating func focusPreviousPane() {
    moveFocus(by: -1)
  }

  public mutating func focus(
    _ direction: TerminalWorkspaceDirection,
    within size: CellSize
  ) {
    let frames = TerminalWorkspaceLayout.frames(for: self, in: size)
    guard
      let focusedPaneID,
      let active = frames.first(where: { $0.paneID == focusedPaneID })
    else {
      normalizeFocus()
      return
    }

    let candidates = frames.filter { frame in
      frame.paneID != focusedPaneID
        && isCandidate(frame.rect, in: direction, from: active.rect)
    }
    if let nearest = candidates.min(by: { lhs, rhs in
      distance(from: active.rect, to: lhs.rect, direction: direction)
        < distance(from: active.rect, to: rhs.rect, direction: direction)
    }) {
      self.focusedPaneID = nearest.paneID
      return
    }

    switch direction {
    case .left, .up:
      focusPreviousPane()
    case .right, .down:
      focusNextPane()
    }
  }

  public mutating func splitFocusedPane(
    axis: TerminalSplitAxis,
    newPane: TerminalPaneSpec,
    fraction: Double = 0.5
  ) {
    guard let tabIndex = activeTabIndex else {
      return
    }
    normalizeFocus()
    guard let focusedPaneID else {
      return
    }
    guard !allPaneIDs.contains(newPane.id) else {
      return
    }

    if split(
      paneID: focusedPaneID,
      in: &tabs[tabIndex].root,
      axis: axis,
      newPane: newPane,
      fraction: fraction
    ) {
      self.focusedPaneID = newPane.id
      zoomedPaneID = nil
    }
  }

  @discardableResult
  public mutating func closeFocusedPane() -> TerminalPaneID? {
    guard
      canCloseFocusedPane,
      let tabIndex = activeTabIndex,
      let focusedPaneID
    else {
      return nil
    }

    guard let removal = remove(paneID: focusedPaneID, from: tabs[tabIndex].root),
      let replacement = removal.replacement
    else {
      return nil
    }

    tabs[tabIndex].root = replacement

    if zoomedPaneID == removal.removed {
      zoomedPaneID = nil
    }
    normalizeFocus()
    return removal.removed
  }

  public mutating func toggleZoom() {
    normalizeFocus()
    guard let focusedPaneID else {
      zoomedPaneID = nil
      return
    }
    zoomedPaneID = zoomedPaneID == focusedPaneID ? nil : focusedPaneID
  }

  public mutating func renameFocusedPane(_ title: String) {
    guard
      let tabIndex = activeTabIndex,
      let focusedPaneID
    else {
      return
    }
    rename(paneID: focusedPaneID, title: title, in: &tabs[tabIndex].root)
  }

  public mutating func renameActiveTab(_ title: String) {
    guard let activeTabIndex else {
      return
    }
    tabs[activeTabIndex].title = title
  }

  public mutating func appendTab(_ tab: TerminalWorkspaceTab) {
    guard !tabs.contains(where: { $0.id == tab.id }) else {
      return
    }
    tabs.append(tab)
    activeTabID = tab.id
    focusedPaneID = tab.paneIDs.first
    zoomedPaneID = nil
  }

  public func nextAvailablePaneID(prefix: String = "pane") -> TerminalPaneID {
    var index = allPaneIDs.count + 1
    while true {
      let id = TerminalPaneID("\(prefix)-\(index)")
      if !allPaneIDs.contains(id) {
        return id
      }
      index += 1
    }
  }

  public func nextAvailableTabID(prefix: String = "tab") -> TerminalWorkspaceTabID {
    var index = tabs.count + 1
    while true {
      let id = TerminalWorkspaceTabID("\(prefix)-\(index)")
      if !tabs.contains(where: { $0.id == id }) {
        return id
      }
      index += 1
    }
  }

  public mutating func normalizeFocus() {
    guard let tab = activeTab else {
      activeTabID = nil
      focusedPaneID = nil
      zoomedPaneID = nil
      return
    }

    if activeTabID == nil || !tabs.contains(where: { $0.id == activeTabID }) {
      activeTabID = tab.id
    }
    if let focusedPaneID, tab.contains(focusedPaneID) {
      return
    }
    focusedPaneID = tab.paneIDs.first
  }

  private mutating func moveFocus(by delta: Int) {
    let paneIDs = activePaneIDs
    guard !paneIDs.isEmpty else {
      focusedPaneID = nil
      return
    }

    let currentIndex = focusedPaneID.flatMap { paneIDs.firstIndex(of: $0) } ?? 0
    let nextIndex = (currentIndex + delta + paneIDs.count) % paneIDs.count
    focusedPaneID = paneIDs[nextIndex]
  }
}

private func split(
  paneID: TerminalPaneID,
  in node: inout TerminalWorkspaceNode,
  axis: TerminalSplitAxis,
  newPane: TerminalPaneSpec,
  fraction: Double
) -> Bool {
  switch node {
  case .terminal(let pane) where pane.id == paneID:
    node = .split(
      TerminalSplit(
        axis: axis,
        fraction: fraction,
        first: .terminal(pane),
        second: .terminal(newPane)
      )
    )
    return true
  case .terminal:
    return false
  case .split(var splitNode):
    if split(
      paneID: paneID,
      in: &splitNode.first,
      axis: axis,
      newPane: newPane,
      fraction: fraction
    ) {
      node = .split(splitNode)
      return true
    }
    if split(
      paneID: paneID,
      in: &splitNode.second,
      axis: axis,
      newPane: newPane,
      fraction: fraction
    ) {
      node = .split(splitNode)
      return true
    }
    return false
  }
}

private struct PaneRemoval {
  var removed: TerminalPaneID
  var replacement: TerminalWorkspaceNode?
}

private func remove(
  paneID: TerminalPaneID,
  from node: TerminalWorkspaceNode
) -> PaneRemoval? {
  switch node {
  case .terminal(let pane):
    return pane.id == paneID
      ? PaneRemoval(removed: pane.id, replacement: nil)
      : nil
  case .split(let splitNode):
    if let firstRemoval = remove(paneID: paneID, from: splitNode.first) {
      return PaneRemoval(
        removed: firstRemoval.removed,
        replacement: firstRemoval.replacement.map { replacement in
          .split(
            TerminalSplit(
              axis: splitNode.axis,
              fraction: splitNode.fraction,
              first: replacement,
              second: splitNode.second
            )
          )
        } ?? splitNode.second
      )
    }
    if let secondRemoval = remove(paneID: paneID, from: splitNode.second) {
      return PaneRemoval(
        removed: secondRemoval.removed,
        replacement: secondRemoval.replacement.map { replacement in
          .split(
            TerminalSplit(
              axis: splitNode.axis,
              fraction: splitNode.fraction,
              first: splitNode.first,
              second: replacement
            )
          )
        } ?? splitNode.first
      )
    }
    return nil
  }
}

private func rename(
  paneID: TerminalPaneID,
  title: String,
  in node: inout TerminalWorkspaceNode
) {
  switch node {
  case .terminal(var pane) where pane.id == paneID:
    pane.title = title
    node = .terminal(pane)
  case .terminal:
    return
  case .split(var split):
    rename(paneID: paneID, title: title, in: &split.first)
    rename(paneID: paneID, title: title, in: &split.second)
    node = .split(split)
  }
}

private func isCandidate(
  _ candidate: CellRect,
  in direction: TerminalWorkspaceDirection,
  from active: CellRect
) -> Bool {
  switch direction {
  case .left:
    candidate.maxX <= active.origin.x
      && rangesOverlap(
        candidate.origin.y..<candidate.maxY,
        active.origin.y..<active.maxY
      )
  case .right:
    candidate.origin.x >= active.maxX
      && rangesOverlap(
        candidate.origin.y..<candidate.maxY,
        active.origin.y..<active.maxY
      )
  case .up:
    candidate.maxY <= active.origin.y
      && rangesOverlap(
        candidate.origin.x..<candidate.maxX,
        active.origin.x..<active.maxX
      )
  case .down:
    candidate.origin.y >= active.maxY
      && rangesOverlap(
        candidate.origin.x..<candidate.maxX,
        active.origin.x..<active.maxX
      )
  }
}

private func distance(
  from active: CellRect,
  to candidate: CellRect,
  direction: TerminalWorkspaceDirection
) -> Int {
  switch direction {
  case .left:
    active.origin.x - candidate.maxX
  case .right:
    candidate.origin.x - active.maxX
  case .up:
    active.origin.y - candidate.maxY
  case .down:
    candidate.origin.y - active.maxY
  }
}

private func rangesOverlap(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
  lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
}
