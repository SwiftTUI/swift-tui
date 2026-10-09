import Foundation
import SwiftTUICore

package struct TerminalReaderCommandResult {
  package var output: String = ""
  package var request: AccessibilityActionRequest?
  package var exit = false
  package var grid = false
}

/// Command parsing never evaluates shell commands or fabricates keyboard events for controls.
package struct TerminalReaderCommands {
  package var model = TerminalReaderModel()
  package var editor: TerminalReaderEditor?
  package private(set) var pendingRequest: AccessibilityActionRequest?
  private var nextRequest: UInt64 = 1 << 63

  package var protectsInput: Bool {
    editor?.secure == true || model.currentChunk?.node.role == .secureField
  }

  package mutating func acknowledge(_ response: AccessibilityActionResponse) -> String? {
    guard let pendingRequest, response.requestID == pendingRequest.requestID,
      response.target == pendingRequest.target
    else { return nil }
    self.pendingRequest = nil
    return "Action \(response.result.rawValue). Use read for current state."
  }

  package mutating func command(_ line: String) -> TerminalReaderCommandResult {
    let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
    let verb = String(parts.first ?? "").lowercased()
    let value = parts.count > 1 ? String(parts[1]) : ""
    if verb == "quit" || verb == "q" {
      editor = nil
      return .init(output: "Return to shell.", exit: true)
    }
    if verb == "cancel" || verb == "escape" {
      editor = nil
      return .init(output: "Editing canceled.")
    }
    if editor != nil { return editCommand(verb, value: value) }
    switch verb {
    case "", "read", "r": return .init(output: model.read())
    case "next", "n": return .init(output: model.navigate(1))
    case "previous", "p": return .init(output: model.navigate(-1))
    case "up": return .init(output: model.hierarchy(up: true))
    case "down": return .init(output: model.hierarchy(up: false))
    case "find": return .init(output: model.find(value))
    case "categories":
      return .init(output: TerminalReaderModel.safe(model.categories.joined(separator: "\n")))
    case "category": return .init(output: model.category(value))
    case "text":
      guard value.isEmpty || Int(value) != nil else {
        return .init(output: "Usage: text CHARACTER-OFFSET")
      }
      return .init(output: model.textPage(from: Int(value) ?? 0))
    case "history":
      return .init(
        output: (model.historyEvicted ? "Older review entries were evicted.\n" : "")
          + model.history.enumerated().map { "Review \($0.offset + 1): \($0.element)" }.joined(
            separator: "\n\n"))
    case "updates":
      let updates = model.takeUpdates()
      return .init(
        output: updates.isEmpty ? "No pending updates." : updates.joined(separator: "\n"))
    case "pause":
      model.paused = true
      return .init(output: "Update notices paused. Updates remain available.")
    case "resume":
      model.paused = false
      return .init(output: "Update notices resumed. Use updates for pending content.")
    case "policy":
      guard value == "quiet" || value == "announce" else {
        return .init(output: "Usage: policy quiet|announce")
      }
      model.announcesUpdates = value == "announce"
      return .init(output: "Update policy: \(value).")
    case "chunks":
      guard value == "element" || value == "section" else {
        return .init(output: "Usage: chunks element|section")
      }
      model.sections = value == "section"
      return .init(output: model.read())
    case "grid": return .init(output: "Visual mode. Press F12 to return to the reader.", grid: true)
    case "help", "h": return .init(output: Self.help)
    case "actions": return .init(output: actions())
    case "options": return .init(output: options(from: Int(value) ?? 1))
    case "edit": return beginEdit()
    case "activate": return request(.activate)
    case "increment", "+": return request(.increment)
    case "decrement", "-": return request(.decrement)
    case "focus": return request(.focus)
    case "choose":
      guard let index = Int(value), index > 0,
        let options = model.currentChunk?.node.control?.selection?.options,
        index <= options.count
      else { return .init(output: "Use options, then choose NUMBER.") }
      guard options[index - 1].isEnabled else { return .init(output: "That option is disabled.") }
      return request(.setValue(.text(options[index - 1].id)))
    case "do":
      guard let actions = model.currentChunk?.node.control?.customActions else {
        return .init(output: "No named actions.")
      }
      let name: String
      if let index = Int(value), index > 0, index <= actions.count {
        name = actions[index - 1]
      } else if actions.contains(value) {
        name = value
      } else {
        return .init(output: "Use actions, then do NUMBER or do EXACT NAME.")
      }
      return request(.custom(name))
    case "set":
      guard let node = model.currentChunk?.node, node.role != .secureField else {
        return .init(output: "Use edit for protected entry.")
      }
      switch node.control?.value {
      case .number:
        guard let number = Double(value), number.isFinite else {
          return .init(output: "Enter a finite number.")
        }
        return request(.setValue(.number(number)))
      case .boolean:
        guard ["on", "off", "true", "false"].contains(value.lowercased()) else {
          return .init(output: "Use set on or set off.")
        }
        return request(.setValue(.boolean(["on", "true"].contains(value.lowercased()))))
      case .text: return request(.setValue(.text(value)))
      default: return .init(output: "This chunk has no settable value. Use actions.")
      }
    default: return .init(output: "Unknown command. Use help.")
    }
  }

  private func actions() -> String {
    guard let node = model.currentChunk?.node, let control = node.control else {
      return "No actions on this chunk."
    }
    var lines = [
      node.isEnabled ? "Available actions:" : "Disabled control; actions cannot mutate it."
    ]
    for action in control.actions {
      switch action {
      case .custom, .accessibilityBlur, .accessibilityFocus: break
      case .editText, .selectText: lines.append("edit — text and selection review")
      case .setValue:
        lines.append(
          control.selection == nil ? "set VALUE; edit for text" : "options; choose NUMBER")
      default: lines.append(action.rawValue)
      }
    }
    lines += control.customActions.enumerated().map {
      "do \($0.offset + 1): \(TerminalReaderModel.safe($0.element))"
    }
    return lines.joined(separator: "\n")
  }

  private func options(from start: Int) -> String {
    guard let options = model.currentChunk?.node.control?.selection?.options else {
      return "No selection options."
    }
    guard start > 0, start <= options.count else {
      return "Options start at 1; this control has \(options.count) options."
    }
    let end = min(options.count, start + 49)
    return options.enumerated().dropFirst(start - 1).prefix(50).map {
      "\($0.offset + 1): \(TerminalReaderModel.safe($0.element.label))\($0.element.isEnabled ? "" : " (disabled)")"
    }.joined(separator: "\n") + "\nOptions \(start) to \(end) of \(options.count)."
      + (end < options.count ? " Use options \(end + 1) for more." : "")
  }

  package mutating func request(_ action: AccessibilityAction, target: String? = nil)
    -> TerminalReaderCommandResult
  {
    guard pendingRequest == nil else {
      return .init(
        output:
          "An action is awaiting acknowledgement. Review current state before issuing another mutation."
      )
    }
    guard let node = model.currentChunk?.node, let liveTarget = node.actionTarget,
      target == nil || liveTarget == target
    else {
      return .init(output: "The original control is no longer current. Read the current chunk.")
    }
    guard node.isEnabled else { return .init(output: "Control is disabled.") }
    guard node.control?.actions.contains(action.kind) == true else {
      return .init(output: "Action not supported by this control.")
    }
    guard nextRequest < UInt64.max else {
      return .init(output: "Session request limit reached. Exit and restart.")
    }
    let request = AccessibilityActionRequest(
      target: liveTarget, action: action, requestID: nextRequest)
    nextRequest += 1
    // Retain only correlation metadata: secure values must not enter review or pending state.
    pendingRequest = .init(target: liveTarget, action: .focus, requestID: request.requestID)
    return .init(output: "Action submitted.", request: request)
  }

  package static let help = """
    Terminal reader commands (type then Enter):
    next/n; previous/p; read/r; text CHARACTER-OFFSET; up; down; find TEXT; history; updates;
    categories; category NAME (next heading, control, link or authored group);
    actions; activate; increment; decrement; set VALUE; options [START]; choose NUMBER;
    do NUMBER (named action); focus; edit; chunks element|section;
    policy quiet|announce; pause; resume; scenes; scene ID; grid; help; quit/q.
    Editing: read; select START END; insert TEXT; replace TEXT; append-line TEXT;
    delete; save; cancel. Positions count characters from zero, preserving Unicode graphemes.
    Protected editing never echoes or stores draft text in review history.
    Escape cancels the current command or edit. Ctrl-C exits; Ctrl-D exits at an empty prompt.
    F12 switches between the visual grid and reader without restarting application state.
    Persist your launch choice with SWIFTTUI_READER=1, or pass --reader.
    """
}
