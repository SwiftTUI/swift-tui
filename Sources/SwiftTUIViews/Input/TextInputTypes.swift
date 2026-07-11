/// A grapheme-cluster offset into a text input value.
package struct TextOffset: Comparable, Hashable, Sendable {
  package var rawValue: Int

  package init(_ rawValue: Int) {
    self.rawValue = max(0, rawValue)
  }

  package static func < (lhs: TextOffset, rhs: TextOffset) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// A half-open grapheme-cluster range in a text input value.
package struct TextRange: Equatable, Hashable, Sendable {
  package var lowerBound: TextOffset
  package var upperBound: TextOffset

  package init(
    lowerBound: TextOffset,
    upperBound: TextOffset
  ) {
    self.lowerBound = min(lowerBound, upperBound)
    self.upperBound = max(lowerBound, upperBound)
  }

  package init(_ range: Range<TextOffset>) {
    self.init(
      lowerBound: range.lowerBound,
      upperBound: range.upperBound
    )
  }

  package var isEmpty: Bool {
    lowerBound == upperBound
  }
}

/// A text selection stored as anchor/head so selection direction is preserved.
package struct TextSelection: Equatable, Hashable, Sendable {
  package var anchor: TextOffset
  package var head: TextOffset

  package init(
    anchor: TextOffset,
    head: TextOffset
  ) {
    self.anchor = anchor
    self.head = head
  }

  package static func caret(at offset: TextOffset) -> TextSelection {
    TextSelection(anchor: offset, head: offset)
  }

  package var range: TextRange {
    TextRange(lowerBound: anchor, upperBound: head)
  }

  package var isCollapsed: Bool {
    anchor == head
  }
}

/// Text and editing state owned by text input controls.
package struct TextInputValue: Equatable, Sendable {
  package var text: String
  package var selection: TextSelection
  package var composingRange: TextRange?
  package var preferredVisualColumn: Int?

  package init(
    text: String = "",
    selection: TextSelection? = nil,
    composingRange: TextRange? = nil,
    preferredVisualColumn: Int? = nil
  ) {
    self.text = text
    self.selection = selection ?? .caret(at: TextOffset(text.count))
    self.composingRange = composingRange
    self.preferredVisualColumn = preferredVisualColumn
  }

  package func synchronized(with externalText: String) -> TextInputValue {
    guard externalText != text else {
      return clampingSelection()
    }

    // The external text diverged from the control's own editing state: the
    // binding was written programmatically or retargeted to a different
    // source. The retained caret describes an offset into the OLD text, so
    // carrying it over lands mid-string in unrelated content — start fresh
    // with the caret at the end, exactly as an initial bind does.
    return TextInputValue(text: externalText)
  }

  package func clampingSelection() -> TextInputValue {
    let upperBound = TextOffset(text.count)
    let clampedRange = selection.range.clamped(to: upperBound)
    var copy = self
    copy.selection = TextSelection(
      anchor: min(selection.anchor, clampedRange.upperBound),
      head: min(selection.head, clampedRange.upperBound)
    )
    return copy
  }
}

package enum TextInputSubmitBehavior: Equatable, Sendable {
  case submit
  case newline
}

/// Static behavior for a text input control.
package struct TextInputTraits: Equatable, Sendable {
  package var isMultiline: Bool
  package var isSecure: Bool
  package var acceptsTab: Bool
  package var submitBehavior: TextInputSubmitBehavior
  package var lineLimit: Int?

  package init(
    isMultiline: Bool,
    isSecure: Bool = false,
    acceptsTab: Bool = false,
    submitBehavior: TextInputSubmitBehavior = .submit,
    lineLimit: Int? = nil
  ) {
    self.isMultiline = isMultiline
    self.isSecure = isSecure
    self.acceptsTab = acceptsTab
    self.submitBehavior = submitBehavior
    self.lineLimit = lineLimit
  }

  package static let singleLine = TextInputTraits(isMultiline: false)
  package static let multiline = TextInputTraits(
    isMultiline: true,
    submitBehavior: .newline
  )
  package static let secureField = TextInputTraits(
    isMultiline: false,
    isSecure: true
  )
}

package enum TextGranularity: Equatable, Sendable {
  case character
  case word
  case line
}

package enum TextMovement: Equatable, Sendable {
  case left
  case right
  case up
  case down
  case lineStart
  case lineEnd
  case documentStart
  case documentEnd
  case wordBackward
  case wordForward
}

package enum TextInputCommand: Equatable, Sendable {
  case insertText(String)
  case deleteBackward(granularity: TextGranularity)
  case deleteForward(granularity: TextGranularity)
  case move(TextMovement, selecting: Bool)
  case replaceSelection(String)
  case setSelection(TextSelection)
  case selectAll
  case copySelection
  case cutSelection
  case pasteClipboard
}

package struct TextInputMutation: Equatable, Sendable {
  package var value: TextInputValue
  package var changedRange: TextRange?
  package var insertedText: String
  package var clipboardText: String?
  package var shouldWriteBinding: Bool
  package var shouldRequestFrame: Bool

  package init(
    value: TextInputValue,
    changedRange: TextRange? = nil,
    insertedText: String = "",
    clipboardText: String? = nil,
    shouldWriteBinding: Bool = false,
    shouldRequestFrame: Bool = false
  ) {
    self.value = value
    self.changedRange = changedRange
    self.insertedText = insertedText
    self.clipboardText = clipboardText
    self.shouldWriteBinding = shouldWriteBinding
    self.shouldRequestFrame = shouldRequestFrame
  }
}

extension TextRange {
  package func clamped(to upperBound: TextOffset) -> TextRange {
    TextRange(
      lowerBound: min(lowerBound, upperBound),
      upperBound: min(self.upperBound, upperBound)
    )
  }

  package func intersects(_ other: TextRange) -> Bool {
    lowerBound < other.upperBound && other.lowerBound < upperBound
  }
}
