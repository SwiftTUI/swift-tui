import Testing

@testable import SwiftTUIRuntime

@Suite(.serialized)
struct FrameworkStressTerminalInputCapabilityResponseTests {
  @Test("stress terminal input capability 001 kitty flags survive leading device attributes")
  func inputCapability001KittyFlagsSurviveLeadingDeviceAttributes() {
    // Hypothesis: the guaranteed DA terminator can hide a flags report arriving later in the buffer.
    let bytes = Array("\u{001B}[?62;4c\u{001B}[?5u".utf8)

    #expect(parseKittyKeyboardFlagsReport(from: bytes) == 5)
  }

  @Test("stress terminal input capability 002 kitty flags ignore ordinary CSI u replies")
  func inputCapability002KittyFlagsIgnoreOrdinaryCSIUReplies() {
    // Hypothesis: an ordinary enhanced key response can be mistaken for a capability report.
    let bytes = Array("\u{001B}[106;5u\u{001B}[?62;4c".utf8)

    #expect(parseKittyKeyboardFlagsReport(from: bytes) == nil)
  }

  @Test("stress terminal input capability 003 empty kitty flag fields are rejected")
  func inputCapability003EmptyKittyFlagFieldsAreRejected() {
    // Hypothesis: an empty numeric field can default to zero and claim protocol support.
    let bytes = Array("\u{001B}[?u\u{001B}[?62;4c".utf8)

    #expect(parseKittyKeyboardFlagsReport(from: bytes) == nil)
  }

  @Test("stress terminal input capability 004 invalid UTF8 invalidates the whole flag buffer")
  func inputCapability004InvalidUTF8InvalidatesWholeFlagBuffer() {
    // Hypothesis: lossy decoding can manufacture a valid flags envelope around corrupt input.
    let bytes = Array("\u{001B}[?5u".utf8) + [0xFF]

    #expect(parseKittyKeyboardFlagsReport(from: bytes) == nil)
  }

  @Test("stress terminal input capability 005 DEC mode selection uses the exact mode")
  func inputCapability005DECModeSelectionUsesExactMode() {
    // Hypothesis: a neighboring DEC report can satisfy the requested mode by shared suffix.
    let bytes = Array("\u{001B}[?1006;1$y\u{001B}[?1016;2$y".utf8)

    #expect(parseDECPrivateModeReport(from: bytes, mode: 1016) == .reset)
  }

  @Test("stress terminal input capability 006 incomplete DEC reports remain indeterminate")
  func inputCapability006IncompleteDECReportsRemainIndeterminate() {
    // Hypothesis: a split report ending before `y` can still enable the queried mode.
    let bytes = Array("\u{001B}[?1016;2$".utf8)

    #expect(parseDECPrivateModeReport(from: bytes, mode: 1016) == nil)
  }

  @Test("stress terminal input capability 007 multi token DEC states are rejected")
  func inputCapability007MultiTokenDECStatesAreRejected() {
    // Hypothesis: an extra state token can be compacted into a valid leading state.
    let bytes = Array("\u{001B}[?1016;2;1$y".utf8)

    #expect(parseDECPrivateModeReport(from: bytes, mode: 1016) == nil)
  }

  @Test("stress terminal input capability 008 DEC reports cannot borrow a later terminator")
  func inputCapability008DECReportsCannotBorrowLaterTerminator() {
    // Hypothesis: an unterminated target report can borrow `$y` from an adjacent mode report.
    let bytes = Array("\u{001B}[?1016;2\u{001B}[?1006;1$y".utf8)

    #expect(parseDECPrivateModeReport(from: bytes, mode: 1016) == nil)
  }
}
