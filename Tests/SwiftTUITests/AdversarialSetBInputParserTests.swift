// Adversarial set B, pass 2: terminal input decoding (161–170).
//
// The parser's own comments state the contract: an escape envelope is
// consumed whole and never leaks as text or a stray Escape, an incomplete
// prefix resolves at the idle flush, and a chord never types text the user
// did not intend. These probes feed the byte shapes that sit between the
// recognized envelopes: a lone CSI introducer at flush, X10 mouse reports,
// xterm's modifyOtherKeys form, the C0 bytes the legacy table skips, a typed
// replacement character, out-of-range legacy modifier parameters, Alt with a
// non-ASCII letter, 8-bit CSI, and a paste that never ends.
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@Suite("Adversarial set B: input parser")
struct AdversarialSetBInputParserTests {
  private func bytes(_ text: String) -> [UInt8] {
    Array(text.utf8)
  }

  private func keys(_ events: [InputEvent]) -> [KeyPress] {
    events.compactMap {
      if case .key(let key) = $0 { return key }
      return nil
    }
  }

  // An incomplete `ESC [` resolves at the idle flush like `ESC O` does: it is
  // Alt+[, and the byte that follows later is an ordinary key.
  @Test func setB161LoneCSIIntroducerResolvesAtFlushAsAltBracket() {
    var parser = TerminalInputParser()
    #expect(parser.feed([0x1B, 0x5B]).isEmpty)
    let flushed = parser.flush()
    let next = parser.feed([0x61])
    do {
      #expect(flushed == [.key(KeyPress(.character("["), modifiers: .alt))], "\(flushed)")
      #expect(next == [.key(KeyPress(.character("a")))], "\(next)")
    }

    var ss3 = TerminalInputParser()
    #expect(ss3.feed([0x1B, 0x4F]).isEmpty)
    let flushedSS3 = ss3.flush()
    #expect(flushedSS3 == [.key(KeyPress(.character("O"), modifiers: .alt))], "\(flushedSS3)")
  }

  // An X10 mouse report (`ESC [ M Cb Cx Cy`) is an envelope: it is consumed
  // whole, never delivered as Space and two punctuation keys.
  @Test func setB162X10MouseReportsNeverLeakAsKeys() {
    var parser = TerminalInputParser()
    let press = parser.feed([0x1B, 0x5B, 0x4D, 0x20, 0x21, 0x21])
    let release = parser.feed([0x1B, 0x5B, 0x4D, 0x23, 0x21, 0x21])
    let wheel = parser.feed([0x1B, 0x5B, 0x4D, 0x60, 0x25, 0x25])
    do {
      #expect(keys(press).isEmpty, "\(press)")
      #expect(keys(release).isEmpty, "\(release)")
      #expect(keys(wheel).isEmpty, "\(wheel)")
    }
    #expect(parser.flush().isEmpty)
    let after = parser.feed([0x7A])
    #expect(after == [.key(KeyPress(.character("z")))], "\(after)")
  }

  // xterm's modifyOtherKeys envelope (`CSI 27 ; mod ; code ~`) carries the
  // same keys the kitty `CSI code ; mod u` form does.
  @Test func setB163ModifyOtherKeysEnvelopeDeliversTheKey() {
    var parser = TerminalInputParser()
    let ctrlEnter = parser.feed(bytes("\u{1B}[27;5;13~"))
    let kittyCtrlEnter = parser.feed(bytes("\u{1B}[13;5u"))
    #expect(kittyCtrlEnter == [.key(KeyPress(.return, modifiers: .ctrl))], "\(kittyCtrlEnter)")
    let shiftTab = parser.feed(bytes("\u{1B}[27;2;9~"))
    let legacyShiftTab = parser.feed(bytes("\u{1B}[Z"))
    #expect(legacyShiftTab == [.key(KeyPress(.tab, modifiers: .shift))], "\(legacyShiftTab)")
    let altA = parser.feed(bytes("\u{1B}[27;3;97~"))
    do {
      #expect(ctrlEnter == [.key(KeyPress(.return, modifiers: .ctrl))], "\(ctrlEnter)")
      #expect(shiftTab == [.key(KeyPress(.tab, modifiers: .shift))], "\(shiftTab)")
      #expect(altA == [.key(KeyPress(.character("a"), modifiers: .alt))], "\(altA)")
    }
  }

  // The C0 bytes outside 0x01–0x1A are chords too: NUL is Ctrl+Space and
  // 0x1C, 0x1D and 0x1F are Ctrl with a punctuation key, as the kitty forms
  // already deliver.
  @Test func setB164RemainingC0BytesAreDeliveredAsControlChords() {
    var parser = TerminalInputParser()
    let nul = parser.feed([0x00])
    let kittyNul = parser.feed(bytes("\u{1B}[32;5u"))
    #expect(kittyNul == [.key(KeyPress(.space, modifiers: .ctrl))], "\(kittyNul)")
    do {
      #expect(nul == [.key(KeyPress(.space, modifiers: .ctrl))], "\(nul)")
      for (byte, character) in [(UInt8(0x1C), Character("\\")), (0x1D, "]"), (0x1F, "_")] {
        let events = parser.feed([byte])
        let delivered = keys(events)
        #expect(delivered.count == 1, "0x\(String(byte, radix: 16)): \(events)")
        #expect(
          delivered.first?.modifiers.contains(.ctrl) == true,
          "0x\(String(byte, radix: 16)): \(events)")
        if case .character(let typed)? = delivered.first?.key {
          #expect(typed == character, "0x\(String(byte, radix: 16)) typed \(typed)")
        }
      }
    }
    // The ordinary letters keep their chords.
    #expect(parser.feed([0x01]) == [.key(KeyPress(.character("a"), modifiers: .ctrl))])
    #expect(parser.feed([0x1A]) == [.key(KeyPress(.character("z"), modifiers: .ctrl))])
  }

  // A genuinely typed U+FFFD is a character like any other; only decoding
  // failures are dropped.
  @Test func setB165TypedReplacementCharacterIsDelivered() {
    var parser = TerminalInputParser()
    let typed = parser.feed([0xEF, 0xBF, 0xBD])
    do {
      #expect(typed == [.key(KeyPress(.character("\u{FFFD}")))], "\(typed)")
    }
    let invalid = parser.feed([0xFF])
    #expect(keys(invalid).allSatisfy { $0.key != .character("\u{FFFD}") }, "\(invalid)")
    let afterInvalid = parser.feed([0x62])
    #expect(afterInvalid.contains(.key(KeyPress(.character("b")))), "\(afterInvalid)")
    let overlong = parser.feed([0xC0, 0x80])
    #expect(!overlong.contains(.key(KeyPress(.character("\0")))), "\(overlong)")
  }

  // Legacy modifier parameters outside 2...16 do not synthesize modifiers:
  // `;0` is unmodified, and `;9` (meta) agrees with the kitty form.
  @Test func setB166OutOfRangeLegacyModifierParametersDoNotInventModifiers() {
    var parser = TerminalInputParser()
    let zero = parser.feed(bytes("\u{1B}[1;0A"))
    let one = parser.feed(bytes("\u{1B}[1;1A"))
    #expect(one == [.key(KeyPress(.arrowUp))], "\(one)")
    let five = parser.feed(bytes("\u{1B}[1;5A"))
    #expect(five == [.key(KeyPress(.arrowUp, modifiers: .ctrl))], "\(five)")
    let legacyMeta = parser.feed(bytes("\u{1B}[1;9A"))
    let kittyMeta = parser.feed(bytes("\u{1B}[57352;9u"))
    #expect(keys(legacyMeta).allSatisfy { $0.key == .arrowUp }, "\(legacyMeta)")
    do {
      #expect(zero == [.key(KeyPress(.arrowUp))], "\(zero)")
      #expect(legacyMeta.isEmpty == kittyMeta.isEmpty, "legacy \(legacyMeta) kitty \(kittyMeta)")
    }
  }

  // Alt with a non-ASCII letter arrives as ESC followed by a UTF-8 sequence;
  // it is one chord, never an Escape plus a literal.
  @Test func setB167AltWithNonASCIILetterIsOneChord() {
    var parser = TerminalInputParser()
    let altE = parser.feed([0x1B, 0xC3, 0xA9])
    let kittyAltE = parser.feed(bytes("\u{1B}[233;3u"))
    #expect(kittyAltE == [.key(KeyPress(.character("é"), modifiers: .alt))], "\(kittyAltE)")
    let altEmoji = parser.feed([0x1B, 0xF0, 0x9F, 0x98, 0x80])
    do {
      #expect(altE == [.key(KeyPress(.character("é"), modifiers: .alt))], "\(altE)")
      #expect(!altEmoji.contains(.key(KeyPress(.escape))), "\(altEmoji)")
    }
    let altASCII = parser.feed([0x1B, 0x78])
    #expect(altASCII == [.key(KeyPress(.character("x"), modifiers: .alt))], "\(altASCII)")
  }

  // An 8-bit CSI (0x9B) is the same envelope as `ESC [`: its final byte is
  // never typed.
  @Test func setB168EightBitCSIFinalBytesNeverLeak() {
    var parser = TerminalInputParser()
    let up = parser.feed([0x9B, 0x41])
    let shiftTab = parser.feed([0x9B, 0x5A])
    let reply = parser.feed([0x9B, 0x3F, 0x31, 0x3B, 0x32, 0x63])
    #expect(reply.isEmpty, "\(reply)")
    let tilde = parser.feed([0x9B, 0x33, 0x7E])
    do {
      #expect(up == [.key(KeyPress(.arrowUp))] || up.isEmpty, "\(up)")
      #expect(!up.contains(.key(KeyPress(.character("A")))), "\(up)")
      #expect(!shiftTab.contains(.key(KeyPress(.character("Z")))), "\(shiftTab)")
      #expect(!tilde.contains(.key(KeyPress(.character("3")))), "\(tilde)")
    }
  }

  // A paste whose end marker never arrives still resolves at the idle flush,
  // and input after the flush is delivered again. (Bounding the buffer is
  // STUI-831; this is the recovery semantics.)
  @Test func setB169UnterminatedPasteResolvesAtFlush() {
    var parser = TerminalInputParser()
    let opened = parser.feed(bytes("\u{1B}[200~abc"))
    #expect(opened.isEmpty, "\(opened)")
    let flushed = parser.flush()
    let recovered =
      flushed.contains(.paste(PasteEvent(content: "abc")))
      || keys(flushed).map(\.key) == [.character("a"), .character("b"), .character("c")]
    let after = parser.feed([0x71])
    do {
      #expect(!flushed.isEmpty, "the flush recovers the pending paste")
      #expect(recovered, "\(flushed)")
      #expect(after == [.key(KeyPress(.character("q")))], "\(after)")
    }
  }

  // Terminal replies and degenerate envelopes never leak: device attributes,
  // mode reports, window reports, a doubled Escape, and a paste whose end
  // marker is split across reads.
  @Test func setB170RepliesAndSplitEnvelopesNeverLeakAsKeys() {
    for reply in [
      "\u{1B}[?1;2c", "\u{1B}[>0;276;0c", "\u{1B}[?2026;2$y", "\u{1B}[?1016;0$y", "\u{1B}[8;24;80t",
      "\u{1B}]11;rgb:1e1e/1e1e/1e1e\u{07}",
    ] {
      var parser = TerminalInputParser()
      let events = parser.feed(bytes(reply))
      #expect(events.isEmpty, "\(reply.debugDescription): \(events)")
      #expect(parser.flush().isEmpty, "\(reply.debugDescription)")
    }
    var doubled = TerminalInputParser()
    let first = doubled.feed([0x1B, 0x1B])
    let rest = doubled.flush()
    #expect(first + rest == [.key(KeyPress(.escape)), .key(KeyPress(.escape))], "\(first + rest)")

    var split = TerminalInputParser()
    let head = split.feed(bytes("\u{1B}[200~x\u{1B}[20"))
    let tail = split.feed(bytes("1~q"))
    #expect(
      head + tail == [.paste(PasteEvent(content: "x")), .key(KeyPress(.character("q")))],
      "\(head + tail)")
  }
}
