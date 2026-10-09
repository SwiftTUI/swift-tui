import SwiftTUICore

package struct TerminalReaderEditor {
  var target: String
  var text: String
  var anchor: Int
  var head: Int
  var secure: Bool
  var readOnly: Bool
  var supportsTextEdit: Bool
  var supportsSelection: Bool
  var original: String
}

extension TerminalReaderCommands {
  package mutating func beginEdit() -> TerminalReaderCommandResult {
    guard let node = model.currentChunk?.node, let control = node.control,
      let target = node.actionTarget,
      control.actions.contains(.setValue) || control.actions.contains(.editText)
        || control.actions.contains(.selectText)
    else { return .init(output: "This chunk has no text editor.") }
    let secure = node.role == .secureField
    let text: String
    if secure {
      text = ""
    } else if case .text(let value) = control.value {
      text = value
    } else {
      return .init(output: "This control does not expose editable text.")
    }
    let head = node.textInput?.insertionOffset ?? text.utf16.count
    let selection = node.textInput?.selection
    let anchor = selection.map { head == $0.lowerBound ? $0.upperBound : $0.lowerBound } ?? head
    func characterOffset(_ utf16: Int) -> Int {
      var units = 0
      var count = 0
      for character in text {
        let length = String(character).utf16.count
        if units + length > utf16 { break }
        units += length
        count += 1
      }
      return count
    }
    editor = .init(
      target: target, text: text, anchor: characterOffset(anchor), head: characterOffset(head),
      secure: secure, readOnly: node.properties?.readOnly == true,
      supportsTextEdit: control.actions.contains(.editText),
      supportsSelection: control.actions.contains(.selectText), original: text)
    return .init(
      output: secure
        ? "Protected editor. Input is not echoed. Enter replace TEXT, then save; cancel discards it."
        : "Text editor. Use read, select START END, insert TEXT, replace TEXT, append-line TEXT, delete, save, cancel."
    )
  }

  package mutating func editCommand(_ verb: String, value: String) -> TerminalReaderCommandResult {
    guard var draft = editor else { return .init() }
    guard let node = model.currentChunk?.node, node.actionTarget == draft.target else {
      editor = nil
      return .init(output: "The edited control was removed or review moved. Draft discarded.")
    }
    if !draft.secure, case .text(let live) = node.control?.value, live != draft.original {
      editor = nil
      return .init(
        output:
          "Application text changed during editing. Draft discarded; use edit to review the current value."
      )
    }
    switch verb {
    case "read", "":
      return .init(
        output: draft.secure
          ? "Protected draft."
          : TerminalReaderModel.safe(draft.text, limit: 65_536)
            + "\nSelection \(draft.anchor) to \(draft.head) of \(draft.text.count) characters.")
    case "select":
      let offsets = value.split(separator: " ").compactMap { Int($0) }
      guard offsets.count == 2, offsets.allSatisfy({ $0 >= 0 && $0 <= draft.text.count }) else {
        return .init(output: "Use select START END with character offsets inside the draft.")
      }
      draft.anchor = offsets[0]
      draft.head = offsets[1]
    case "insert", "replace", "append-line", "delete":
      guard !draft.readOnly else {
        return .init(output: "Read-only text permits selection but not edits.")
      }
      var text = Array(draft.text)
      let insertion = verb == "delete" ? "" : value
      guard
        insertion.unicodeScalars.allSatisfy({ $0.value >= 32 && !(127...159).contains($0.value) })
      else {
        return .init(
          output: "Control characters are not accepted. Use append-line for line breaks.")
      }
      let lower = min(draft.anchor, draft.head)
      let upper = max(draft.anchor, draft.head)
      let added: String
      if verb == "replace" {
        text = []
        draft.anchor = 0
        added = insertion
      } else if verb == "append-line" {
        draft.anchor = text.count
        added = "\n" + insertion
      } else {
        text.removeSubrange(lower..<upper)
        draft.anchor = lower
        added = insertion
      }
      text.insert(contentsOf: added, at: draft.anchor)
      let result = String(text)
      draft.text = result
      draft.head = draft.anchor + added.count
      draft.anchor = draft.head
    case "save":
      let anchor = draft.text.prefix(draft.anchor).utf16.count
      let head = draft.text.prefix(draft.head).utf16.count
      let edit = AccessibilityTextEdit(text: draft.text, anchor: anchor, head: head)
      let action: AccessibilityAction
      if draft.text == draft.original && draft.supportsSelection {
        action = .selectText(edit)
      } else if draft.readOnly {
        return .init(output: "Read-only text cannot be changed.")
      } else if draft.supportsTextEdit && !draft.secure {
        action = .editText(edit)
      } else {
        action = .setValue(.text(draft.text))
      }
      let result = request(action, target: draft.target)
      if result.request != nil { editor = nil }
      return result
    default:
      return .init(
        output:
          "Editing commands: read; select START END; insert TEXT; replace TEXT; append-line TEXT; delete; save; cancel."
      )
    }
    editor = draft
    return .init(
      output: draft.secure
        ? "Protected draft changed." : "Draft updated. Selection \(draft.anchor) to \(draft.head).")
  }
}
