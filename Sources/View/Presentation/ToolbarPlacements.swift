/// Where a ``ToolbarItem`` lands in a toolbar host's layout.
///
/// The placement set mirrors SwiftUI's ``ToolbarItemPlacement`` but is
/// pruned to the cases that have a meaningful TUI interpretation. Each
/// dropped case in the full SwiftUI set refers to chrome the framework
/// does not render — see
/// ``docs/proposals/COMMAND_AND_CHROME_APIS.md`` §4.7 for the rationale.
public enum ToolbarItemPlacement: Hashable, Sendable {
  /// System-chosen. Resolves to ``bottomBar`` in the default host.
  case automatic

  /// The dominant action for the current scope. Right-docked in the
  /// bottom row.
  case primaryAction

  /// Less prominent actions. Default placement for the binding-derived
  /// hint stream when a host also renders a help strip.
  case secondaryAction

  /// Status indicators: file dirtiness, async progress, mode badges.
  /// Rendered on the left of the bottom row (or its own status row
  /// when present).
  case status

  /// Pinned to the bottom bar regardless of any host's ``automatic``
  /// resolution.
  case bottomBar

  /// The dominant action in a modal context (sheet, alert, dialog).
  /// Routes to the modal's confirm button slot, not the window
  /// toolbar.
  case confirmationAction

  /// The dismiss action in a modal context.
  case cancellationAction

  /// A discard / delete action in a modal context.
  case destructiveAction

  /// Top-row title slot. No-op in hosts that don't render a title row.
  case title
}

/// Names a toolbar row (bar) for visibility and background control.
///
/// This is the bar namespace for ``View/toolbar(_:for:)`` and
/// ``View/toolbarBackground(_:for:)``, distinct from
/// ``ToolbarItemPlacement`` (which is the item namespace).
public enum ToolbarPlacement: Hashable, Sendable {
  /// System-chosen. Resolves to ``bottomBar`` in the default host.
  case automatic

  /// The bottom row where ``ToolbarItemPlacement/bottomBar``,
  /// ``ToolbarItemPlacement/primaryAction``, and the help strip live.
  case bottomBar

  /// A dedicated status row; no-op in hosts that don't split status
  /// out of the bottom row.
  case statusBar

  /// The top title row; no-op until a title row is rendered.
  case titleBar
}
