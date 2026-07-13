import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite("SwiftTUI terminal protocol boundary stress behavior", .serialized)
struct FrameworkStressTerminalProtocolBoundaryTests {
  @Test("stress terminal protocol 001 kitty associated text stays inside its envelope")
  func terminalProtocol001KittyAssociatedTextStaysInsideEnvelope() {
    // Hypothesis: associated-text subparameters can leak their decimal bytes as typed input.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[97;1;98:99uZ".utf8))

    #expect(
      events == [
        .key(KeyPress(.character("a"))),
        .key(KeyPress(.character("Z"))),
      ])
  }

  @Test("stress terminal protocol 002 kitty releases discard associated text atomically")
  func terminalProtocol002KittyReleasesDiscardAssociatedTextAtomically() {
    // Hypothesis: swallowing a release can strand its associated-text section in the input buffer.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[97;1:3;120uZ".utf8))

    #expect(events == [.key(KeyPress(.character("Z")))])
  }

  @Test("stress terminal protocol 003 kitty zero modifier values are rejected atomically")
  func terminalProtocol003KittyZeroModifierValuesAreRejectedAtomically() {
    // Hypothesis: subtracting kitty's one-based modifier offset can underflow or emit a plain key.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[97;0uZ".utf8))

    #expect(events == [.key(KeyPress(.character("Z")))])
  }

  @Test("stress terminal protocol 004 overflowing kitty key codes preserve following input")
  func terminalProtocol004OverflowingKittyKeyCodesPreserveFollowingInput() {
    // Hypothesis: an adversarial key-code integer can trap or leave its terminator undrained.
    var parser = TerminalInputParser()
    let overlongKeyCode = String(repeating: "9", count: 40)

    let events = parser.feed(Array("\u{001B}[\(overlongKeyCode)uZ".utf8))

    #expect(events == [.key(KeyPress(.character("Z")))])
  }

  @Test("stress terminal protocol 005 overflowing kitty modifiers preserve following input")
  func terminalProtocol005OverflowingKittyModifiersPreserveFollowingInput() {
    // Hypothesis: an overflowing modifier field can trap before the envelope is consumed.
    var parser = TerminalInputParser()
    let overlongModifier = String(repeating: "9", count: 40)

    let events = parser.feed(Array("\u{001B}[97;\(overlongModifier)uZ".utf8))

    #expect(events == [.key(KeyPress(.character("Z")))])
  }

  @Test("stress terminal protocol 006 kitty code points above Unicode are swallowed")
  func terminalProtocol006KittyCodePointsAboveUnicodeAreSwallowed() {
    // Hypothesis: constructing a scalar above U+10FFFF can trap or synthesize replacement input.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[1114112uZ".utf8))

    #expect(events == [.key(KeyPress(.character("Z")))])
  }

  @Test("stress terminal protocol 007 kitty surrogate code points are swallowed")
  func terminalProtocol007KittySurrogateCodePointsAreSwallowed() {
    // Hypothesis: a UTF-16 surrogate value can escape kitty scalar validation.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[55296uZ".utf8))

    #expect(events == [.key(KeyPress(.character("Z")))])
  }

  @Test("stress terminal protocol 008 kitty lock bits preserve representable control")
  func terminalProtocol008KittyLockBitsPreserveRepresentableControl() {
    // Hypothesis: clearing both lock-state bits can accidentally clear an adjacent ctrl bit.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[97;197u".utf8))

    #expect(events == [.key(KeyPress(.character("a"), modifiers: .ctrl))])
  }

  @Test("stress terminal protocol 009 kitty super remains rejected beside lock bits")
  func terminalProtocol009KittySuperRemainsRejectedBesideLockBits() {
    // Hypothesis: dropping lock bits can also hide an unrepresentable super modifier.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[97;201uZ".utf8))

    #expect(events == [.key(KeyPress(.character("Z")))])
  }

  @Test("stress terminal protocol 010 malformed kitty event types never synthesize presses")
  func terminalProtocol010MalformedKittyEventTypesNeverSynthesizePresses() {
    // Hypothesis: a nonnumeric event type can default to press and fire an unintended action.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[97;1:xuZ".utf8))

    withKnownIssue(
      "Nonnumeric kitty event types break envelope recognition and leak as literal key input"
    ) {
      #expect(events == [.key(KeyPress(.character("Z")))])
    }
  }

  @Test("stress terminal protocol 011 unknown kitty event types never synthesize presses")
  func terminalProtocol011UnknownKittyEventTypesNeverSynthesizePresses() {
    // Hypothesis: a future or invalid event-type value can be misclassified as a key press.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[97;1:4uZ".utf8))

    withKnownIssue(
      "Unknown kitty event types are currently treated as key presses"
    ) {
      #expect(events == [.key(KeyPress(.character("Z")))])
    }
  }

  @Test("stress terminal protocol 012 VT220 tilde keys retain all representable modifiers")
  func terminalProtocol012VT220TildeKeysRetainAllRepresentableModifiers() {
    // Hypothesis: the three modifier bits can interfere when decoded together.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[5;8~".utf8))

    #expect(
      events == [
        .key(KeyPress(.pageUp, modifiers: [.shift, .alt, .ctrl]))
      ])
  }

  @Test("stress terminal protocol 013 modified unassigned VT220 slots stay atomic")
  func terminalProtocol013ModifiedUnassignedVT220SlotsStayAtomic() {
    // Hypothesis: rejecting an unassigned slot can leak its modifier suffix before Unicode input.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[16;5~é".utf8))

    #expect(events == [.key(KeyPress(.character("é")))])
  }

  @Test("stress terminal protocol 014 overflowing VT220 modifiers degrade without trapping")
  func terminalProtocol014OverflowingVT220ModifiersDegradeWithoutTrapping() {
    // Hypothesis: a valid key paired with an overflowing modifier can trap numeric accumulation.
    var parser = TerminalInputParser()
    let overlongModifier = String(repeating: "9", count: 40)

    let events = parser.feed(Array("\u{001B}[6;\(overlongModifier)~Z".utf8))

    #expect(
      events == [
        .key(KeyPress(.pageDown)),
        .key(KeyPress(.character("Z"))),
      ])
  }

  @Test("stress terminal protocol 015 extra VT220 parameter groups reject the envelope")
  func terminalProtocol015ExtraVT220ParameterGroupsRejectEnvelope() {
    // Hypothesis: silently ignoring a third parameter can turn malformed bytes into a real action.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[3;5;9~Z".utf8))

    withKnownIssue(
      "VT220 decoding currently ignores parameter groups after the modifier field"
    ) {
      #expect(events == [.key(KeyPress(.character("Z")))])
    }
  }

  @Test("stress terminal protocol 016 unknown modified CSI finals never synthesize Escape")
  func terminalProtocol016UnknownModifiedCSIFinalsNeverSynthesizeEscape() {
    // Hypothesis: an unknown final can become a modal-dismissing Escape with carried modifiers.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[1;5XZ".utf8))

    withKnownIssue(
      "Unknown modified CSI finals currently synthesize an Escape key press"
    ) {
      #expect(events == [.key(KeyPress(.character("Z")))])
    }
  }

  @Test("stress terminal protocol 017 VT220 sequences survive a split after Escape")
  func terminalProtocol017VT220SequencesSurviveSplitAfterEscape() {
    // Hypothesis: the escape timeout boundary can commit Escape before the tilde envelope resumes.
    var parser = TerminalInputParser()

    let prefix = parser.feed([0x1B])
    let completed = parser.feed(Array("[34~Z".utf8))

    #expect(prefix.isEmpty)
    #expect(
      completed == [
        .key(KeyPress(.functionKey(20))),
        .key(KeyPress(.character("Z"))),
      ])
  }

  @Test("stress terminal protocol 018 SS3 sequences survive a split after Escape")
  func terminalProtocol018SS3SequencesSurviveSplitAfterEscape() {
    // Hypothesis: a split SS3 prefix can degrade into Escape plus literal O and final bytes.
    var parser = TerminalInputParser()

    let prefix = parser.feed([0x1B])
    let completed = parser.feed(Array("OSZ".utf8))

    #expect(prefix.isEmpty)
    #expect(
      completed == [
        .key(KeyPress(.functionKey(4))),
        .key(KeyPress(.character("Z"))),
      ])
  }

  @Test("stress terminal protocol 019 private CSI intermediates are consumed atomically")
  func terminalProtocol019PrivateCSIIntermediatesAreConsumedAtomically() {
    // Hypothesis: multiple intermediate bytes can terminate private-CSI suppression too early.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[?25;1$ yZ".utf8))

    #expect(events == [.key(KeyPress(.character("Z")))])
  }

  @Test("stress terminal protocol 020 DEL cells cannot inject terminal control")
  func terminalProtocol020DELCellsCannotInjectTerminalControl() {
    // Hypothesis: DEL can bypass the renderer's C0-only sanitization path.
    let rendered = TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(
      RasterSurface(size: .init(width: 1, height: 1), lines: ["\u{007F}"])
    )

    #expect(rendered == "�")
  }

  @Test("stress terminal protocol 021 C1 OSC cells cannot inject terminal control")
  func terminalProtocol021C1OSCCellsCannotInjectTerminalControl() {
    // Hypothesis: an eight-bit OSC scalar can reach the terminal without an ESC introducer.
    let rendered = TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(
      RasterSurface(size: .init(width: 1, height: 1), lines: ["\u{009D}"])
    )

    #expect(rendered == "�")
  }

  @Test("stress terminal protocol 022 OSC 8 destinations strip eight-bit terminators")
  func terminalProtocol022OSC8DestinationsStripEightBitTerminators() {
    // Hypothesis: C1 ST can close an OSC 8 destination early and expose a terminal injection.
    let rendered = TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(
      RasterSurface(
        size: .init(width: 1, height: 1),
        cells: [[RasterCell(character: "X", hyperlink: "https://safe/\u{009C}ok")]]
      )
    )

    #expect(
      rendered
        == "\u{001B}]8;;https://safe/ok\u{001B}\\X\u{001B}]8;;\u{001B}\\"
    )
  }

  @Test("stress terminal protocol 023 OSC 8 destinations preserve ordinary backslashes")
  func terminalProtocol023OSC8DestinationsPreserveOrdinaryBackslashes() {
    // Hypothesis: sanitizing ST can accidentally erase harmless unpaired backslashes.
    let rendered = TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(
      RasterSurface(
        size: .init(width: 1, height: 1),
        cells: [[RasterCell(character: "X", hyperlink: "https://safe/a\\b")]]
      )
    )

    #expect(
      rendered
        == "\u{001B}]8;;https://safe/a\\b\u{001B}\\X\u{001B}]8;;\u{001B}\\"
    )
  }

  @Test("stress terminal protocol 024 OSC 8 sanitization keeps text after a lone Escape")
  func terminalProtocol024OSC8SanitizationKeepsTextAfterLoneEscape() {
    // Hypothesis: dropping a bare Escape can also consume the next safe destination scalar.
    let rendered = TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(
      RasterSurface(
        size: .init(width: 1, height: 1),
        cells: [[RasterCell(character: "X", hyperlink: "https://safe/\u{001B}Xok")]]
      )
    )

    #expect(
      rendered
        == "\u{001B}]8;;https://safe/Xok\u{001B}\\X\u{001B}]8;;\u{001B}\\"
    )
  }

  @Test("stress terminal protocol 025 ASCII rendering degrades C1 controls safely")
  func terminalProtocol025ASCIIRenderingDegradesC1ControlsSafely() {
    // Hypothesis: ASCII degradation can run before C1 sanitization and emit a raw control byte.
    let rendered = TerminalSurfaceRenderer(capabilityProfile: .previewASCII).render(
      RasterSurface(size: .init(width: 1, height: 1), lines: ["\u{009B}"])
    )

    #expect(rendered == "?")
  }
}
