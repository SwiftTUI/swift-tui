@_spi(Runners) import SwiftTUI

/// Reconstructs per-keystroke text editing in a focused field embedded in a
/// larger static form, without depending on `swift-tui-examples`.
///
/// The field is focused by a click, then driven with a sequence of character,
/// backspace, and caret-move keystrokes. Each keystroke is an interaction frame
/// that (a) holds keyboard focus on the field, (b) mutates the bound `@State`
/// text and re-keys the `TextLayoutCache`, and (c) leaves a large static sibling
/// form reuse-eligible. This is the committed framework-only stand-in for the
/// missing "text editing and focus" coverage called out in the 2026-06-16 perf
/// signal representativeness pass — text fields and editors are heavily used in
/// the gallery and GIF-editor but were previously untimed.
///
/// A `buf:<text>|` mirror line gives the driver a deterministic settle marker
/// that is independent of the field's own cursor/style rendering. The static
/// sibling-form row count is fixed by default (smoke-test friendly) but can be
/// overridden with `TERMUI_PERF_TEXT_EDIT_TREE_ROWS` to show whether per-keystroke
/// cost scales with the surrounding form rather than the edited text.
public struct TextInputEditingScenario: PerfScenario {
  public let name: PerfScenarioName = .textInputEditing
  public let defaultTerminalSize = PerfTerminalSize(columns: 100, rows: 36)
  public let scriptedEvents = [
    "focus a text field, then type / backspace / caret-move keystrokes inside a static form"
  ]
  public let visualMarkers = ["Text editing workload"]
  public let settlingDescription = "first frame that shows the text editing workload"

  private static let defaultTreeRows = 24
  private static let typedWord = "Document"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let treeRows = Self.resolvedTreeRows()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfTextEditingView(treeRows: treeRows)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "Text editing workload")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      // Focus the field by clicking its prompt, then verify focus took by
      // typing the first character and waiting for the mirror to update.
      let fieldCell = try driver.cell(containing: "perf-input")
      driver.sendClick(at: fieldCell)

      var buffer = ""
      @MainActor func type(_ key: KeyEvent, expect: String) async throws {
        driver.inputReader.send(.key(key))
        let frame = try await driver.waitForFrame(
          containing: "buf:\(expect)|",
          afterFrame: lastFrame
        )
        lastFrame = frame.frameNumber
      }

      // Append the word one character at a time.
      for character in Self.typedWord {
        buffer.append(character)
        try await type(.character(character), expect: buffer)
      }

      // Delete the last three characters (Document -> Docum).
      for _ in 0..<3 {
        buffer.removeLast()
        try await type(.backspace, expect: buffer)
      }

      // Retype the suffix (Docum -> Document).
      for character in "ent" {
        buffer.append(character)
        try await type(.character(character), expect: buffer)
      }

      // Move the caret left one and insert mid-string (Document -> DocumenXt).
      driver.inputReader.send(.key(.arrowLeft))
      driver.inputReader.send(.key(.character("X")))
      buffer.insert("X", at: buffer.index(buffer.endIndex, offsetBy: -1))
      let inserted = try await driver.waitForFrame(
        containing: "buf:\(buffer)|",
        afterFrame: lastFrame
      )
      lastFrame = inserted.frameNumber

      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "text-input-editing",
          eventType: "key_editing",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "buf:\(buffer)|",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  private static func resolvedTreeRows() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_TEXT_EDIT_TREE_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultTreeRows
    }
    return parsed
  }
}

private struct PerfTextEditingView: View {
  let treeRows: Int

  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Text editing workload")
        .foregroundStyle(.tint)
      // Deterministic mirror of the bound text — independent of the field's
      // own cursor/style rendering — so the driver can settle on each keystroke.
      Text("buf:\(text)|")
      TextField("perf-input", text: $text)
        .textFieldStyle(.plain)
        .frame(maxWidth: 40, alignment: .leading)
        .border(.separator)
      Divider()
      // Large static sibling form: reuse-eligible across keystrokes.
      ForEach(0..<treeRows, id: \.self) { row in
        HStack(spacing: 1) {
          Text("form field \(row)")
          Spacer(minLength: 1)
          Text("value \(row * 7)")
            .foregroundStyle(.separator)
        }
        .border(.separator)
      }
    }
    .padding(1)
    .panel(id: "perf-text-editing")
  }
}
