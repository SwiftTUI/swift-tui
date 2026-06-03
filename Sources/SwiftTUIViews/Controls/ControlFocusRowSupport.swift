package import SwiftTUICore

// Shared control chrome: the focus rail, highlighted rows, and the text-editor
// body.
//
// `controlFocusRail` draws (or reserves space for) the leading focus-indicator
// glyph; `highlightedControlRow` fills a row background when selected;
// `controlFocusRow` composes the two into the standard interactive-row layout
// used by lists, menus, pickers, and tab strips. `textEditorBody` is the
// shared scrollable text-editor surface.
//
// Split out of `SelectionAndValueSupport.swift` so that file's remaining
// concerns are not mixed with the shared row chrome.

package let controlFocusRailGlyph = "▌"

@MainActor
@ViewBuilder
package func controlFocusRail(
  isVisible: Bool,
  style: AnyShapeStyle,
  inactiveStyle: AnyShapeStyle = AnyShapeStyle(.background),
  reservesSpaceWhenHidden: Bool = false
) -> some View {
  if isVisible {
    Text(controlFocusRailGlyph)
      .foregroundStyle(style)
  } else if reservesSpaceWhenHidden {
    Text(String(repeating: " ", count: controlFocusRailGlyph.count))
      .foregroundStyle(inactiveStyle)
  }
}

@MainActor
@ViewBuilder
package func highlightedControlRow<Row: View>(
  _ row: Row,
  isHighlighted: Bool,
  backgroundStyle: AnyShapeStyle
) -> some View {
  if isHighlighted {
    row.background {
      Rectangle().fill(backgroundStyle)
    }
  } else {
    row
  }
}

@MainActor
package func controlFocusRow<Content: View>(
  showsRail: Bool,
  railStyle: AnyShapeStyle,
  isHighlighted: Bool,
  backgroundStyle: AnyShapeStyle,
  inactiveRailStyle: AnyShapeStyle = AnyShapeStyle(.background),
  reservesRailSpaceWhenHidden: Bool = false,
  spacing: Int = 1,
  @ViewBuilder content: () -> Content
) -> some View {
  highlightedControlRow(
    HStack(alignment: .center, spacing: spacing) {
      if showsRail || reservesRailSpaceWhenHidden {
        controlFocusRail(
          isVisible: showsRail,
          style: railStyle,
          inactiveStyle: inactiveRailStyle,
          reservesSpaceWhenHidden: reservesRailSpaceWhenHidden
        )
      }
      content()
    },
    isHighlighted: isHighlighted,
    backgroundStyle: backgroundStyle
  )
}

@MainActor
package func textEditorBody(
  displayText: String,
  displayRuns: [TextInputDisplayRun]? = nil,
  ownerIdentity: Identity? = nil,
  caretAnchor: CellPoint? = nil,
  chrome: ControlChrome,
  scrollPosition: Binding<ScrollPosition>,
  focusActive: Bool = false
) -> some View {
  ScrollView(.vertical, showsIndicators: true, position: scrollPosition) {
    VStack(alignment: .leading, spacing: 0) {
      TextInputContent(
        displayText: displayText,
        displayRuns: displayRuns,
        ownerIdentity: ownerIdentity,
        caretAnchor: caretAnchor
      )
      .fixedSize(horizontal: false, vertical: true)
      .foregroundStyle(chrome.foregroundStyle)
      .drawMetadata(.init(opacity: chrome.opacity))
    }
  }
  .padding(.init(horizontal: 1, vertical: 1))
  .focusable(false)
  .background {
    RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(chrome.backgroundStyle)
  }
  .overlay {
    RoundedRectangle(cornerRadius: 1).strokeBorder(
      chrome.borderStyle,
      style: focusActive ? .heavy : .init(),
      background: chrome.borderBackgroundStyle
    )
  }
  .layoutMetadata(.init(minimumHeight: 3))
}
