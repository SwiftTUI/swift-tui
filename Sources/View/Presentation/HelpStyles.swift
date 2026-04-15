/// Visual placement style for the auto-derived help strip attached by
/// ``View/help(_:overflow:)``.
///
/// Only ``HelpStripStyle/bottomBar`` is fully implemented in v1; the
/// other cases are accepted at the public API and silently fall back to
/// the bottom-bar rendering so authors can declare intent today without
/// blocking on secondary renderers.
public enum HelpStripStyle: Hashable, Sendable {
  /// Bottom-row inline strip that attaches to the nearest ``ToolbarHost``
  /// row. This is the default and the only style with a dedicated
  /// renderer in v1.
  case bottomBar

  /// Inline above the next sibling in the declared flow, useful for
  /// panel-local strips.
  ///
  /// v1 fallback: rendered as ``HelpStripStyle/bottomBar``. A dedicated
  /// inline renderer is a Stage 3.1 follow-up.
  case inline

  /// Bottom-row strip that hides itself after the user dismisses it and
  /// reappears on focus change.
  ///
  /// v1 fallback: rendered as ``HelpStripStyle/bottomBar`` without the
  /// dismiss-and-reappear behaviour. Stage 3.1.
  case dismissible
}

/// Overflow strategy for the help strip when declared commands exceed
/// the available width.
///
/// Only ``HelpStripOverflow/truncate`` is fully implemented in v1; the
/// other cases silently fall back to truncation.
public enum HelpStripOverflow: Hashable, Sendable {
  /// Drop trailing tokens and replace them with an ellipsis. Default.
  case truncate

  /// Horizontal scroll inside the bar. v1 fallback: truncate.
  /// Stage 3.1 follow-up.
  case scroll

  /// Wrap to additional rows up to `maxRows` (default 2). v1 fallback:
  /// truncate. Stage 3.1 follow-up.
  case wrap(maxRows: Int)
}

extension HelpStripOverflow {
  /// Convenience for ``HelpStripOverflow/wrap(maxRows:)`` with the
  /// default two-row cap.
  public static var wrap: HelpStripOverflow { .wrap(maxRows: 2) }
}
