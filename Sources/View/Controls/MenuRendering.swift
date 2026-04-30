import Core

extension Menu {
  /// The 1-cell-tall trigger row that sits inline in the layout. The
  /// chevron flips between `▾` (collapsed) and `▴` (expanded) so the
  /// surface still telegraphs menu state even though the expanded
  /// content lives in an overlay (see `menuPromptPresentationSpec`).
  ///
  /// Wrapped in a `VStack` so the resolved-tree shape (Menu > VStack >
  /// trigger) matches the prior inline-expanded layout exactly. State
  /// dependency tracking is keyed off the view-node hierarchy that
  /// existed when the binding was registered; preserving the wrapper
  /// keeps the action handler's `@State` capture pointing at the same
  /// slot across re-renders.
  @ViewBuilder
  func menuTriggerRow(
    isExpanded: Bool,
    isFocused: Bool,
    isPressed: Bool,
    chrome: ControlChrome
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      controlFocusRow(
        showsRail: isFocused,
        railStyle: chrome.borderStyle,
        isHighlighted: isFocused || isPressed,
        backgroundStyle: chrome.backgroundStyle,
        reservesRailSpaceWhenHidden: true
      ) {
        label
        Spacer()
        Text(isExpanded ? "▴" : "▾")
      }
    }
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
  }
}
