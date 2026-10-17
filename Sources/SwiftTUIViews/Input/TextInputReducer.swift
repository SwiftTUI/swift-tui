package struct TextInputReducer: Sendable {
  package init() {}

  package func reduce(
    _ value: TextInputValue,
    command: TextInputCommand,
    traits: TextInputTraits,
    layout: TextInputLayoutMap?
  ) -> TextInputMutation {
    let value = value.clampingSelection()
    switch command {
    case .insertText(let text):
      return insert(text, into: value, traits: traits)
    case .replaceSelection(let text):
      return insert(text, into: value, traits: traits)
    case .deleteBackward(let granularity):
      return deleteBackward(granularity: granularity, in: value)
    case .deleteForward(let granularity):
      return deleteForward(granularity: granularity, in: value)
    case .move(let movement, let selecting):
      return move(movement, in: value, selecting: selecting, layout: layout)
    case .setSelection(let selection):
      var next = value
      next.selection = selection
      next.preferredVisualColumn = nil
      return TextInputMutation(value: next.clampingSelection(), shouldRequestFrame: true)
    case .selectAll:
      var next = value
      next.selection = TextSelection(anchor: TextOffset(0), head: TextOffset(value.text.count))
      next.preferredVisualColumn = nil
      return TextInputMutation(value: next, shouldRequestFrame: next != value)
    case .copySelection:
      return copySelection(in: value, traits: traits)
    case .cutSelection:
      return cutSelection(in: value, traits: traits)
    case .pasteClipboard:
      return TextInputMutation(value: value)
    }
  }

  private func insert(
    _ text: String,
    into value: TextInputValue,
    traits: TextInputTraits
  ) -> TextInputMutation {
    let insertedText = sanitizedInsertion(text, traits: traits)
    let range = value.selection.range
    let replacement = TextInputStringMetrics.replacing(
      range: range,
      in: value.text,
      with: insertedText
    )
    let caret = replacement.caret
    let nextValue = TextInputValue(
      text: replacement.text,
      selection: .caret(at: caret)
    )
    return TextInputMutation(
      value: nextValue,
      changedRange: TextRange(
        lowerBound: range.lowerBound,
        upperBound: caret
      ),
      insertedText: insertedText,
      shouldWriteBinding: replacement.text != value.text,
      shouldRequestFrame: true
    )
  }

  private func deleteBackward(
    granularity: TextGranularity,
    in value: TextInputValue
  ) -> TextInputMutation {
    if !value.selection.isCollapsed {
      return delete(range: value.selection.range, in: value)
    }
    guard value.selection.head.rawValue > 0 else {
      return TextInputMutation(value: value)
    }
    let lowerBound = backwardDeletionBoundary(granularity: granularity, in: value)
    guard lowerBound < value.selection.head else {
      return TextInputMutation(value: value)
    }
    let range = TextRange(
      lowerBound..<value.selection.head
    )
    return delete(range: range, in: value)
  }

  private func deleteForward(
    granularity: TextGranularity,
    in value: TextInputValue
  ) -> TextInputMutation {
    if !value.selection.isCollapsed {
      return delete(range: value.selection.range, in: value)
    }
    guard value.selection.head.rawValue < value.text.count else {
      return TextInputMutation(value: value)
    }
    let upperBound = forwardDeletionBoundary(granularity: granularity, in: value)
    guard value.selection.head < upperBound else {
      return TextInputMutation(value: value)
    }
    let range = TextRange(
      value.selection.head..<upperBound
    )
    return delete(range: range, in: value)
  }

  private func backwardDeletionBoundary(
    granularity: TextGranularity,
    in value: TextInputValue
  ) -> TextOffset {
    switch granularity {
    case .character:
      return TextOffset(value.selection.head.rawValue - 1)
    case .word:
      return TextInputStringMetrics.wordBoundaryBefore(value.selection.head, in: value.text)
    case .line:
      let metric = TextInputStringMetrics.lineMetric(for: value.selection.head, in: value.text)
      if metric.lineStart < value.selection.head {
        return metric.lineStart
      }
      return TextOffset(value.selection.head.rawValue - 1)
    }
  }

  private func forwardDeletionBoundary(
    granularity: TextGranularity,
    in value: TextInputValue
  ) -> TextOffset {
    switch granularity {
    case .character:
      return TextOffset(value.selection.head.rawValue + 1)
    case .word:
      return TextInputStringMetrics.wordBoundaryAfter(value.selection.head, in: value.text)
    case .line:
      let metric = TextInputStringMetrics.lineMetric(for: value.selection.head, in: value.text)
      if value.selection.head < metric.lineEnd {
        return metric.lineEnd
      }
      return TextOffset(value.selection.head.rawValue + 1)
    }
  }

  private func delete(
    range: TextRange,
    in value: TextInputValue
  ) -> TextInputMutation {
    let replacement = TextInputStringMetrics.replacing(
      range: range,
      in: value.text,
      with: ""
    )
    return TextInputMutation(
      value: TextInputValue(
        text: replacement.text,
        selection: .caret(at: replacement.caret)
      ),
      changedRange: range,
      shouldWriteBinding: true,
      shouldRequestFrame: true
    )
  }

  private func copySelection(
    in value: TextInputValue,
    traits: TextInputTraits
  ) -> TextInputMutation {
    guard !traits.isSecure, !value.selection.isCollapsed else {
      return TextInputMutation(value: value)
    }
    return TextInputMutation(
      value: value,
      clipboardText: TextInputStringMetrics.substring(
        range: value.selection.range,
        in: value.text
      )
    )
  }

  private func cutSelection(
    in value: TextInputValue,
    traits: TextInputTraits
  ) -> TextInputMutation {
    guard !traits.isSecure, !value.selection.isCollapsed else {
      return TextInputMutation(value: value)
    }
    let range = value.selection.range
    let clipboardText = TextInputStringMetrics.substring(
      range: range,
      in: value.text
    )
    let replacement = TextInputStringMetrics.replacing(
      range: range,
      in: value.text,
      with: ""
    )
    return TextInputMutation(
      value: TextInputValue(
        text: replacement.text,
        selection: .caret(at: replacement.caret)
      ),
      changedRange: range,
      clipboardText: clipboardText,
      shouldWriteBinding: true,
      shouldRequestFrame: true
    )
  }

  private func move(
    _ movement: TextMovement,
    in value: TextInputValue,
    selecting: Bool,
    layout: TextInputLayoutMap?
  ) -> TextInputMutation {
    let target: TextOffset
    let preferredVisualColumn: Int?
    switch movement {
    case .left:
      target =
        !selecting && !value.selection.isCollapsed
        ? value.selection.range.lowerBound
        : TextOffset(max(0, value.selection.head.rawValue - 1))
      preferredVisualColumn = nil
    case .right:
      target =
        !selecting && !value.selection.isCollapsed
        ? value.selection.range.upperBound
        : TextOffset(min(value.text.count, value.selection.head.rawValue + 1))
      preferredVisualColumn = nil
    case .lineStart:
      target =
        TextInputStringMetrics.lineMetric(
          for: value.selection.head,
          in: value.text
        ).lineStart
      preferredVisualColumn = nil
    case .lineEnd:
      target =
        TextInputStringMetrics.lineMetric(
          for: value.selection.head,
          in: value.text
        ).lineEnd
      preferredVisualColumn = nil
    case .documentStart:
      target = TextOffset(0)
      preferredVisualColumn = nil
    case .documentEnd:
      target = TextOffset(value.text.count)
      preferredVisualColumn = nil
    case .wordBackward:
      target = TextInputStringMetrics.wordBoundaryBefore(value.selection.head, in: value.text)
      preferredVisualColumn = nil
    case .wordForward:
      target = TextInputStringMetrics.wordBoundaryAfter(value.selection.head, in: value.text)
      preferredVisualColumn = nil
    case .up:
      let moved = verticalMove(delta: -1, in: value, layout: layout)
      target = moved.offset
      preferredVisualColumn = moved.preferredVisualColumn
    case .down:
      let moved = verticalMove(delta: 1, in: value, layout: layout)
      target = moved.offset
      preferredVisualColumn = moved.preferredVisualColumn
    }

    var next = value
    next.selection =
      selecting
      ? TextSelection(anchor: value.selection.anchor, head: target)
      : .caret(at: target)
    next.preferredVisualColumn = preferredVisualColumn
    return TextInputMutation(value: next, shouldRequestFrame: next != value)
  }

  private func verticalMove(
    delta: Int,
    in value: TextInputValue,
    layout: TextInputLayoutMap?
  ) -> (offset: TextOffset, preferredVisualColumn: Int?) {
    if let layout {
      return layout.verticalOffset(
        from: value.selection.head,
        delta: delta,
        preferredVisualColumn: value.preferredVisualColumn
      )
    }

    let metric = TextInputStringMetrics.lineMetric(
      for: value.selection.head,
      in: value.text
    )
    let preferredColumn = value.preferredVisualColumn ?? metric.column
    let lineCount = TextInputStringMetrics.lineCount(in: value.text)
    let targetLine = metric.lineIndex + delta
    if targetLine < 0 { return (TextOffset(0), preferredColumn) }
    if targetLine >= lineCount { return (TextOffset(value.text.count), preferredColumn) }
    return (
      TextInputStringMetrics.offset(
        lineIndex: targetLine,
        column: preferredColumn,
        in: value.text
      ),
      preferredColumn
    )
  }

  private func sanitizedInsertion(
    _ text: String,
    traits: TextInputTraits
  ) -> String {
    guard !traits.isMultiline else {
      return text
    }
    return String(text.filter { !$0.isNewline })
  }
}
