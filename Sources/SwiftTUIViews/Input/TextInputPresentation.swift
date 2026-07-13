package import SwiftTUICore

package struct TextInputDisplayRun: Equatable, Sendable {
  package var text: String
  package var isSelected: Bool

  package init(
    text: String,
    isSelected: Bool
  ) {
    self.text = text
    self.isSelected = isSelected
  }
}

package struct TextInputPresentation: Equatable, Sendable {
  package var displayText: String
  package var displayRuns: [TextInputDisplayRun]
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
    let shouldDrawSyntheticCaret = isFocused && !cursorFollowsFocus && value.selection.isCollapsed
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
    let selectedRange =
      isFocused && !value.selection.isCollapsed && !shouldShowPrompt
      ? value.selection.range
      : nil
    var displayRuns = Self.displayRuns(
      for: projectedClusters,
      selectedRange: selectedRange
    )
    if shouldDrawSyntheticCaret {
      displayRuns.append(TextInputDisplayRun(text: "_", isSelected: false))
    }
    let displayText = displayRuns.map(\.text).joined()

    self.displayText = displayText
    self.displayRuns = displayRuns
    self.isShowingPrompt = shouldShowPrompt
    self.layoutMap = layoutMap
    self.caretAnchor = caretAnchor
    self.selectionRects =
      if let selectedRange {
        layoutMap.selectionRects(for: selectedRange)
      } else {
        [
          CellRect(
            origin: caretAnchor,
            size: CellSize(width: 1, height: 1)
          )
        ]
      }
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
        isNewline: character.unicodeScalars.allSatisfy {
          $0.value == 0x0A || $0.value == 0x0D
        }
      )
    }
  }

  private static func displayRuns(
    for clusters: [TextInputProjectedCluster],
    selectedRange: TextRange?
  ) -> [TextInputDisplayRun] {
    var runs: [TextInputDisplayRun] = []

    for cluster in clusters {
      let isSelected = selectedRange?.intersects(cluster.textRange) ?? false
      if let lastIndex = runs.indices.last,
        runs[lastIndex].isSelected == isSelected
      {
        runs[lastIndex].text.append(cluster.display)
        continue
      }

      runs.append(
        TextInputDisplayRun(
          text: String(cluster.display),
          isSelected: isSelected
        )
      )
    }

    return runs
  }
}

package struct TextInputProjectedCluster: Equatable, Sendable {
  package var textRange: TextRange
  package var display: Character
  package var isNewline: Bool
}
