import SwiftTUICore

package struct TextInputDisplayRun: Equatable, Sendable {
  package var text: String
  package var isSelected: Bool
  /// Marked (pre-edit) text from a host input method, drawn underlined.
  package var isComposing: Bool

  package init(
    text: String,
    isSelected: Bool,
    isComposing: Bool = false
  ) {
    self.text = text
    self.isSelected = isSelected
    self.isComposing = isComposing
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
    let shouldShowPrompt = value.text.isEmpty && prompt != nil
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
    // A composition belongs to the keyboard focus that is typing it. An
    // unfocused control never draws a mark, whatever its retained state says.
    let composingRange =
      isFocused && !shouldShowPrompt
      ? value.composingRange?.clamped(to: TextOffset(value.text.count))
      : nil
    var displayRuns = Self.displayRuns(
      for: projectedClusters,
      selectedRange: selectedRange,
      composingRange: composingRange,
      caretOffset: shouldDrawSyntheticCaret ? value.selection.head : nil
    )
    if shouldDrawSyntheticCaret && !shouldShowPrompt
      && value.selection.head.rawValue == value.text.count
    {
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
        isNewline: character.isNewline
      )
    }
  }

  private static func displayRuns(
    for clusters: [TextInputProjectedCluster],
    selectedRange: TextRange?,
    composingRange: TextRange?,
    caretOffset: TextOffset?
  ) -> [TextInputDisplayRun] {
    var runs: [TextInputDisplayRun] = []

    for (index, cluster) in clusters.enumerated() {
      let isCaret =
        caretOffset == cluster.textRange.lowerBound
        && (!cluster.textRange.isEmpty || index == 0)
      // Highlight the existing glyph without shifting later text. At a line
      // break there is no glyph, so supply the empty caret cell before it.
      if isCaret && cluster.isNewline {
        runs.append(TextInputDisplayRun(text: "_", isSelected: false))
      }
      let isSelected =
        (selectedRange?.intersects(cluster.textRange) ?? false) || (isCaret && !cluster.isNewline)
      // A line break has no glyph to underline.
      let isComposing =
        !cluster.isNewline && (composingRange?.intersects(cluster.textRange) ?? false)
      if let lastIndex = runs.indices.last,
        runs[lastIndex].isSelected == isSelected,
        runs[lastIndex].isComposing == isComposing
      {
        runs[lastIndex].text.append(cluster.display)
        continue
      }

      runs.append(
        TextInputDisplayRun(
          text: String(cluster.display),
          isSelected: isSelected,
          isComposing: isComposing
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
