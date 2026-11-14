import SwiftTUICore

package struct TextInputContent: View, Sendable {
  package var displayText: String
  package var displayRuns: [TextInputDisplayRun]
  package var ownerIdentity: Identity?
  package var caretAnchor: CellPoint?
  package var wrappedCaretOffset: Int?
  package var accessibilityText: TextInputAccessibilityText?

  nonisolated package init(
    displayText: String,
    displayRuns: [TextInputDisplayRun]? = nil,
    ownerIdentity: Identity? = nil,
    caretAnchor: CellPoint? = nil,
    wrappedCaretOffset: Int? = nil,
    accessibilityText: TextInputAccessibilityText? = nil
  ) {
    self.displayText = displayText
    self.displayRuns = displayRuns ?? Self.unselectedRuns(for: displayText)
    self.ownerIdentity = ownerIdentity
    self.caretAnchor = caretAnchor
    self.wrappedCaretOffset = wrappedCaretOffset
    self.accessibilityText = accessibilityText
  }

  @ViewBuilder
  package var body: some View {
    if let ownerIdentity, let caretAnchor {
      renderedText
        .semanticMetadata(
          .init(
            textInputAccessibilityCursorAnchor: .init(
              ownerIdentity: ownerIdentity,
              anchor: caretAnchor,
              wrappedText: wrappedCaretOffset == nil ? nil : displayText,
              characterOffset: wrappedCaretOffset ?? 0,
              text: accessibilityText
            )
          )
        )
    } else {
      renderedText
    }
  }

  private var renderedText: Text {
    guard displayRuns.contains(where: { $0.isSelected || $0.isComposing }) else {
      return Text(displayText)
    }

    var richContent = Text.RichContent(stringLiteral: "")
    richContent.fragments = displayRuns.compactMap { run in
      guard !run.text.isEmpty else {
        return nil
      }
      guard run.isSelected || run.isComposing else {
        return .literal(run.text)
      }
      // Marked text is underlined, the platform convention for pre-edit
      // text; a selection or caret inside it still reverses.
      var text = Text(run.text)
      if run.isComposing {
        text = text.underline()
      }
      if run.isSelected {
        text = text.reverse()
      }
      return .text(text)
    }
    return Text(richContent)
  }

  nonisolated private static func unselectedRuns(
    for displayText: String
  ) -> [TextInputDisplayRun] {
    guard !displayText.isEmpty else {
      return []
    }
    return [TextInputDisplayRun(text: displayText, isSelected: false)]
  }
}
