import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

@Suite("SwiftTUI terminal boundary stress behavior", .serialized)
struct FrameworkStressTerminalBoundaryTests {
  @Test("stress terminal boundary 001 split resize framing preserves the command boundary")
  func terminalBoundary001SplitResizeFramingPreservesCommandBoundary() {
    // Hypothesis: a transport read ending inside a resize frame can leak its prefix as key input.
    var parser = ControlMessageParser()

    let introducer = parser.feed([0x1E])
    let command = parser.feed(Array("resize:120".utf8))
    let dimensions = parser.feed(Array(":40".utf8))
    let terminator = parser.feed(Array("\nq".utf8))

    #expect(introducer.payload.isEmpty)
    #expect(introducer.messages.isEmpty)
    #expect(command.payload.isEmpty)
    #expect(command.messages.isEmpty)
    #expect(dimensions.payload.isEmpty)
    #expect(dimensions.messages.isEmpty)
    #expect(terminator.payload == Array("q".utf8))
    #expect(terminator.messages == [.resize(.init(width: 120, height: 40))])
  }

  @Test("stress terminal boundary 002 adjacent resize frames retain both messages")
  func terminalBoundary002AdjacentResizeFramesRetainBothMessages() {
    // Hypothesis: completing one frame can skip an immediately adjacent record separator.
    var parser = ControlMessageParser()

    let result = parser.feed(Array("\u{001E}resize:80:24\n\u{001E}resize:132:43\n".utf8))

    #expect(result.payload.isEmpty)
    #expect(
      result.messages == [
        .resize(.init(width: 80, height: 24)),
        .resize(.init(width: 132, height: 43)),
      ])
  }

  @Test("stress terminal boundary 003 malformed control frame does not poison the next frame")
  func terminalBoundary003MalformedControlFrameDoesNotPoisonNextFrame() {
    // Hypothesis: rejecting one command can leave framing state active across its newline.
    var parser = ControlMessageParser()

    let result = parser.feed(
      Array("\u{001E}resize:not-a-width:24\n\u{001E}resize:90:30\nq".utf8)
    )

    #expect(result.payload == Array("q".utf8))
    #expect(result.messages == [.resize(.init(width: 90, height: 30))])
  }

  @Test("stress terminal boundary 004 zero resize dimensions clamp independently")
  func terminalBoundary004ZeroResizeDimensionsClampIndependently() {
    // Hypothesis: a zero-sized host frame can escape normalization at the transport boundary.
    var parser = ControlMessageParser()

    let result = parser.feed(Array("\u{001E}resize:0:0\n".utf8))

    #expect(result.payload.isEmpty)
    #expect(result.messages == [.resize(.init(width: 1, height: 1))])
  }

  @Test("stress terminal boundary 005 negative resize dimensions clamp independently")
  func terminalBoundary005NegativeResizeDimensionsClampIndependently() {
    // Hypothesis: signed transport dimensions can enter runtime geometry below its minimum size.
    var parser = ControlMessageParser()

    let result = parser.feed(Array("\u{001E}resize:-7:-11\n".utf8))

    #expect(result.payload.isEmpty)
    #expect(result.messages == [.resize(.init(width: 1, height: 1))])
  }

  @Test("stress terminal boundary 006 extra resize fields reject only their own frame")
  func terminalBoundary006ExtraResizeFieldsRejectOnlyTheirOwnFrame() {
    // Hypothesis: accepting a valid three-field prefix can shift the next field into payload input.
    var parser = ControlMessageParser()

    let result = parser.feed(
      Array("\u{001E}resize:80:24:ignored\n\u{001E}resize:81:25\nx".utf8)
    )

    #expect(result.payload == Array("x".utf8))
    #expect(result.messages == [.resize(.init(width: 81, height: 25))])
  }

  @Test("stress terminal boundary 007 invalid UTF8 command bytes preserve later framing")
  func terminalBoundary007InvalidUTF8CommandBytesPreserveLaterFraming() {
    // Hypothesis: lossy command decoding can strand the parser after a malformed transport frame.
    var parser = ControlMessageParser()
    let bytes =
      [0x1E] + Array("resize:8:".utf8) + [0xFF, 0x0A]
      + Array("\u{001E}resize:82:26\ny".utf8)

    let result = parser.feed(bytes)

    #expect(result.payload == Array("y".utf8))
    #expect(result.messages == [.resize(.init(width: 82, height: 26))])
  }

  @Test("stress terminal boundary 008 payload order survives an embedded control frame")
  func terminalBoundary008PayloadOrderSurvivesEmbeddedControlFrame() {
    // Hypothesis: extracting a control frame can reorder payload bytes that surround it.
    var parser = ControlMessageParser()

    let result = parser.feed(Array("ab\u{001E}resize:100:31\ncd".utf8))

    #expect(result.payload == Array("abcd".utf8))
    #expect(result.messages == [.resize(.init(width: 100, height: 31))])
  }

  @Test("stress terminal boundary 009 ordinary newlines remain terminal payload")
  func terminalBoundary009OrdinaryNewlinesRemainTerminalPayload() {
    // Hypothesis: a command terminator outside a control frame can be dropped as framing residue.
    var parser = ControlMessageParser()

    let result = parser.feed(Array("a\nb\r\nc".utf8))

    #expect(result.payload == Array("a\nb\r\nc".utf8))
    #expect(result.messages.isEmpty)
  }

  @Test("stress terminal boundary 010 repeated introducer resynchronizes the command frame")
  func terminalBoundary010RepeatedIntroducerResynchronizesCommandFrame() {
    // Hypothesis: a damaged command prefix can swallow the next complete frame instead of resyncing.
    var parser = ControlMessageParser()

    let result = parser.feed(
      Array("\u{001E}truncated\u{001E}resize:84:28\nq".utf8)
    )

    #expect(result.payload == Array("q".utf8))
    #expect(result.messages == [.resize(.init(width: 84, height: 28))])
  }

  @Test("stress terminal boundary 011 BEL terminated OSC reply is inert keyboard input")
  func terminalBoundary011BELTerminatedOSCReplyIsInertKeyboardInput() {
    // Hypothesis: an appearance reply racing live input can type its OSC payload into a control.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}]10;rgb:ffff/ffff/ffff\u{0007}q".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 012 ST terminated OSC reply is inert keyboard input")
  func terminalBoundary012STTerminatedOSCReplyIsInertKeyboardInput() {
    // Hypothesis: the two-byte OSC terminator can leak both the reply and a synthetic Escape.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}]11;rgb:0/0/0\u{001B}\\q".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 013 primary device attributes reply is inert keyboard input")
  func terminalBoundary013PrimaryDeviceAttributesReplyIsInertKeyboardInput() {
    // Hypothesis: a delayed DA response can become Escape plus literal parameter keystrokes.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[?62;4;22cq".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 014 DEC private mode reply is inert keyboard input")
  func terminalBoundary014DECPrivateModeReplyIsInertKeyboardInput() {
    // Hypothesis: a delayed mode report can inject its numeric state into focused text.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[?1016;2$yq".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 015 window size reply is inert keyboard input")
  func terminalBoundary015WindowSizeReplyIsInertKeyboardInput() {
    // Hypothesis: an asynchronous pixel-size reply can be mistaken for ordinary key presses.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[4;720;1280tq".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 016 XTSM graphics reply is inert keyboard input")
  func terminalBoundary016XTSMGraphicsReplyIsInertKeyboardInput() {
    // Hypothesis: a late graphics-capability response can leak its dimensions through key routing.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[?2;0;800;600Sq".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 017 kitty flags report is inert keyboard input")
  func terminalBoundary017KittyFlagsReportIsInertKeyboardInput() {
    // Hypothesis: the capability form of CSI u can be confused with a deliverable key envelope.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}[?5uq".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 018 kitty graphics APC reply is inert keyboard input")
  func terminalBoundary018KittyGraphicsAPCReplyIsInertKeyboardInput() {
    // Hypothesis: a delayed Kitty APC response can leak its control body as typed characters.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}_Gi=42;OK\u{001B}\\q".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 019 DCS response is inert keyboard input")
  func terminalBoundary019DCSResponseIsInertKeyboardInput() {
    // Hypothesis: a DCS capability response can escape its string envelope into key routing.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}P1+r5463=31\u{001B}\\q".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 020 privacy message is inert keyboard input")
  func terminalBoundary020PrivacyMessageIsInertKeyboardInput() {
    // Hypothesis: a PM string from the host can be decomposed into Alt plus printable key presses.
    var parser = TerminalInputParser()

    let events = parser.feed(Array("\u{001B}^host-message\u{001B}\\q".utf8))

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 021 split OSC reply waits for its terminator")
  func terminalBoundary021SplitOSCReplyWaitsForTerminator() {
    // Hypothesis: a read boundary inside OSC can expose a partial response as immediate key input.
    var parser = TerminalInputParser()

    let partial = parser.feed(Array("\u{001B}]10;rgb:ff/".utf8))
    let completed = parser.feed(Array("ff/ff\u{0007}q".utf8))

    #expect(partial.isEmpty)
    #expect(completed == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 022 eight bit CSI reply is inert keyboard input")
  func terminalBoundary022EightBitCSIReplyIsInertKeyboardInput() {
    // Hypothesis: the C1 CSI introducer can be dropped while its reply body is typed literally.
    var parser = TerminalInputParser()
    let bytes = [0x9B] + Array("?62;4cq".utf8)

    let events = parser.feed(bytes)

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 023 eight bit OSC reply is inert keyboard input")
  func terminalBoundary023EightBitOSCReplyIsInertKeyboardInput() {
    // Hypothesis: the C1 OSC introducer can be discarded without suppressing its string payload.
    var parser = TerminalInputParser()
    let bytes = [0x9D] + Array("10;rgb:f/f/f".utf8) + [0x07] + Array("q".utf8)

    let events = parser.feed(bytes)

    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 024 incomplete CSI reply remains buffered")
  func terminalBoundary024IncompleteCSIReplyRemainsBuffered() {
    // Hypothesis: an incomplete terminal reply can emit Escape before its final byte arrives.
    var parser = TerminalInputParser()

    let partial = parser.feed(Array("\u{001B}[?62;4".utf8))
    let completed = parser.feed(Array("cq".utf8))

    #expect(partial.isEmpty)
    #expect(completed == [.key(KeyPress(.character("q")))])
  }

  @Test("stress terminal boundary 025 adjacent replies preserve trailing Unicode input")
  func terminalBoundary025AdjacentRepliesPreserveTrailingUnicodeInput() {
    // Hypothesis: suppressing adjacent OSC and CSI replies can consume the first real UTF-8 scalar.
    var parser = TerminalInputParser()
    let bytes = Array(
      "\u{001B}]10;rgb:f/f/f\u{0007}\u{001B}[?62;4c\u{1F642}".utf8
    )

    let events = parser.feed(bytes)

    #expect(events == [.key(KeyPress(.character("\u{1F642}")))])
  }
}
