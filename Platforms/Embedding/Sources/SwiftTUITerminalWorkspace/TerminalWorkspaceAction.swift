public import SwiftTUICore

/// A workspace command intent.
public enum TerminalWorkspaceAction: Hashable, Sendable {
  case selectTab(TerminalWorkspaceTabID)
  case focusPane(TerminalPaneID)
  case focus(TerminalWorkspaceDirection, within: CellSize)
  case focusNextPane
  case focusPreviousPane
  case splitFocusedPane(axis: TerminalSplitAxis, newPane: TerminalPaneSpec, fraction: Double = 0.5)
  case closeFocusedPane
  case toggleZoom
  case renameFocusedPane(String)
  case renameActiveTab(String)
  case appendTab(TerminalWorkspaceTab)
}

extension TerminalWorkspaceState {
  public mutating func apply(_ action: TerminalWorkspaceAction) -> TerminalPaneID? {
    switch action {
    case .selectTab(let id):
      selectTab(id)
      return nil
    case .focusPane(let id):
      focusPane(id)
      return nil
    case .focus(let direction, let size):
      focus(direction, within: size)
      return nil
    case .focusNextPane:
      focusNextPane()
      return nil
    case .focusPreviousPane:
      focusPreviousPane()
      return nil
    case .splitFocusedPane(let axis, let newPane, let fraction):
      splitFocusedPane(axis: axis, newPane: newPane, fraction: fraction)
      return nil
    case .closeFocusedPane:
      return closeFocusedPane()
    case .toggleZoom:
      toggleZoom()
      return nil
    case .renameFocusedPane(let title):
      renameFocusedPane(title)
      return nil
    case .renameActiveTab(let title):
      renameActiveTab(title)
      return nil
    case .appendTab(let tab):
      appendTab(tab)
      return nil
    }
  }
}
