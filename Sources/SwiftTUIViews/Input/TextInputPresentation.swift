package import SwiftTUICore

package struct TextInputPresentation: Equatable, Sendable {
  package var displayText: String
  package var isShowingPrompt: Bool
  package var layoutMap: TextInputLayoutMap
  package var caretAnchor: CellPoint
  package var selectionRects: [CellRect]
  package var shouldDrawSyntheticCaret: Bool

  package init(
    value: TextInputValue,
    traits: TextInputTraits,
    prompt: String?,
    isFocused: Bool,
    cursorFollowsFocus: Bool,
    width: Int?
  ) {
    let shouldShowPrompt = value.text.isEmpty && !isFocused && prompt != nil
    let shouldDrawSyntheticCaret = isFocused && !cursorFollowsFocus
    let projectedClusters = Self.projectedClusters(
      value: value,
      traits: traits,
      prompt: shouldShowPrompt ? prompt : nil
    )
    let layoutMap = TextInputLayoutMapBuilder.build(
      for: projectedClusters,
      width: width
    )
    let caretAnchor = layoutMap.caretPoint(for: value.selection.head)
    var displayText = String(projectedClusters.map(\.display))
    if shouldDrawSyntheticCaret {
      displayText.append("_")
    }

    self.displayText = displayText
    self.isShowingPrompt = shouldShowPrompt
    self.layoutMap = layoutMap
    self.caretAnchor = caretAnchor
    self.selectionRects = [
      CellRect(
        origin: caretAnchor,
        size: CellSize(width: 1, height: 1)
      )
    ]
    self.shouldDrawSyntheticCaret = shouldDrawSyntheticCaret
  }

  private static func projectedClusters(
    value: TextInputValue,
    traits: TextInputTraits,
    prompt: String?
  ) -> [TextInputProjectedCluster] {
    if let prompt {
      return prompt.enumerated().map { offset, character in
        TextInputProjectedCluster(
          textRange: TextRange(TextOffset(0)..<TextOffset(0)),
          display: character,
          isNewline: false
        )
      }
    }

    if value.text.isEmpty {
      return []
    }

    return value.text.enumerated().map { offset, character in
      let display: Character = traits.isSecure ? "\u{2022}" : character
      return TextInputProjectedCluster(
        textRange: TextRange(TextOffset(offset)..<TextOffset(offset + 1)),
        display: display,
        isNewline: character == "\n"
      )
    }
  }
}

package struct TextInputProjectedCluster: Equatable, Sendable {
  package var textRange: TextRange
  package var display: Character
  package var isNewline: Bool
}
