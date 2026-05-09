package import SwiftTUICore

package struct TextInputContent: View, Sendable {
  package var displayText: String
  package var displayRuns: [TextInputDisplayRun]
  package var ownerIdentity: Identity?
  package var caretAnchor: CellPoint?

  nonisolated package init(
    displayText: String,
    displayRuns: [TextInputDisplayRun]? = nil,
    ownerIdentity: Identity? = nil,
    caretAnchor: CellPoint? = nil
  ) {
    self.displayText = displayText
    self.displayRuns = displayRuns ?? Self.unselectedRuns(for: displayText)
    self.ownerIdentity = ownerIdentity
    self.caretAnchor = caretAnchor
  }

  @ViewBuilder
  package var body: some View {
    if let ownerIdentity, let caretAnchor {
      renderedText
        .semanticMetadata(
          .init(
            textInputAccessibilityCursorAnchor: .init(
              ownerIdentity: ownerIdentity,
              anchor: caretAnchor
            )
          )
        )
    } else {
      renderedText
    }
  }

  private var renderedText: Text {
    guard displayRuns.contains(where: \.isSelected) else {
      return Text(displayText)
    }

    var richContent = Text.RichContent(stringLiteral: "")
    richContent.fragments = displayRuns.compactMap { run in
      guard !run.text.isEmpty else {
        return nil
      }

      return run.isSelected
        ? .text(Text(run.text).reverse())
        : .literal(run.text)
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
