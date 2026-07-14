import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F164: pasted content must never activate controls. The bracketed-paste
/// fall-through re-synthesized every pasted character as a key event —
/// `\n`→`.return`, `\t`→`.tab`, `" "`→`.space` — so a multi-line paste with
/// a destructive button focused fired it once per newline, defeating the
/// point of bracketed paste. Synthesis is now gated on a focused consumer
/// that can treat the keys as text (an editing region or a key handler on
/// the focus bubble path), and `.return`/`.tab` are never forgeable from
/// pasted bytes.
@MainActor
@Suite
struct PasteActivationGuardTests {
  @Test("a multi-line paste with a focused button fires nothing")
  func multiLinePasteWithFocusedButtonFiresNothing() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PasteButtonGuardRoot"),
      size: .init(width: 60, height: 6)
    ) {
      PasteGuardButtonFixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Delete")
    let frame = try harness.paste("rm -rf /\nyes\n final answer\n")
    #expect(
      frame.contains("activations 0"),
      "pasted newlines/spaces activated the focused button; frame:\n\(frame)"
    )
  }

  @Test("a paste with nothing focused fires nothing and types nothing")
  func pasteWithNoFocusIsDropped() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PasteNoFocusRoot"),
      size: .init(width: 60, height: 6)
    ) {
      PasteGuardKeyLogFixture(requiresFocus: false)
    }
    defer { harness.shutdown() }

    // The fixture's key handler is NOT on the focus path (nothing is
    // focusable), so the paste has no text-capable consumer.
    let frame = try harness.paste("abc\n")
    #expect(
      frame.contains("log []"),
      "an unfocused paste synthesized key events; frame:\n\(frame)"
    )
  }

  @Test("a paste into a focused key-handler view still delivers text characters")
  func pasteIntoKeyHandlerViewDeliversCharacters() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PasteKeyHandlerRoot"),
      size: .init(width: 60, height: 6)
    ) {
      PasteGuardKeyLogFixture(requiresFocus: true)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("console")
    // Characters and spaces still arrive (REPL-style compat); the newline
    // and tab must NOT synthesize `.return`/`.tab`.
    let frame = try harness.paste("ab c\td\n")
    #expect(
      frame.contains("log [a, b, space, c, d]"),
      "paste into a key-handler view lost its text compat path; frame:\n\(frame)"
    )
  }
}

@MainActor
private struct PasteGuardButtonFixture: View {
  @State private var activations = 0

  var body: some View {
    VStack {
      Button("Delete") {
        activations += 1
      }
      Text("activations \(activations)")
    }
  }
}

@MainActor
private struct PasteGuardKeyLogFixture: View {
  let requiresFocus: Bool
  @State private var log: [String] = []

  var body: some View {
    VStack {
      if requiresFocus {
        Text("console")
          .focusable()
          .onKeyPress { keyPress in
            record(keyPress)
            return .handled
          }
      } else {
        Text("console")
          .onKeyPress { keyPress in
            record(keyPress)
            return .handled
          }
      }
      Text("log [\(log.joined(separator: ", "))]")
    }
  }

  private func record(_ keyPress: KeyPress) {
    switch keyPress.key {
    case .character(let character):
      log.append(String(character))
    case .space:
      log.append("space")
    case .return:
      log.append("return")
    case .tab:
      log.append("tab")
    default:
      log.append("other")
    }
  }
}
