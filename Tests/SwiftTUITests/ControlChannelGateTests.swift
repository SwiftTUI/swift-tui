import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// F138: the in-band 0x1E control-message channel is written only by
/// embedded-host transports (WebHost stdin records, hosted-session
/// injection). With the channel unconditionally armed, a typed Ctrl+^ on a
/// real terminal silently diverted ALL input into the control buffer until
/// the next newline. The decoder now gates the channel; `InputReader` turns
/// it off when its descriptor is an interactive TTY and keeps it on for
/// pipes and WASI (the pre-F138 behavior hosted transports rely on).
@MainActor
@Suite
struct ControlChannelGateTests {
  @Test("control records interleaved with a paste delimiter preserve framing")
  func controlRecordInsideSplitPasteDelimiter() {
    var decoder = makeDecoder(controlChannelEnabled: true)
    let batch = decoder.decode(
      Array(
        "\u{001B}[20\u{001E}resize:80:24\n0~a\u{001E}X\nb\u{001B}[201~".utf8))
    #expect(batch.events == [.paste(PasteEvent(content: "a\u{001E}X\nb"))])
    #expect(batch.controlMessages == [.resize(.init(width: 80, height: 24))])
  }

  @Test("STUI-84: armed control framing preserves paste payload at every byte boundary")
  func armedChannelPreservesPaste() {
    let payload = "before\u{001E}X\nY\u{001E}resize:1:2\n\u{001B}[200~tail"
    let bytes = Array(
      "\u{001B}[200~\(payload)\u{001B}[201~\u{001E}resize:80:24\nq".utf8)
    for split in 0...bytes.count {
      var decoder = makeDecoder(controlChannelEnabled: true)
      let first = decoder.decode(Array(bytes[..<split]))
      let last = decoder.decode(Array(bytes[split...]))
      #expect(
        first.events + last.events == [.paste(PasteEvent(content: payload)), .key(.character("q"))])
      #expect(
        first.controlMessages + last.controlMessages == [.resize(.init(width: 80, height: 24))])
    }
    var decoder = makeDecoder(controlChannelEnabled: true)
    var events: [InputEvent] = []
    var messages: [TerminalControlMessage] = []
    for byte in bytes {
      let batch = decoder.decode([byte])
      events += batch.events
      messages += batch.controlMessages
    }
    #expect(events == [.paste(PasteEvent(content: payload)), .key(.character("q"))])
    #expect(messages == [.resize(.init(width: 80, height: 24))])
  }

  private func makeDecoder(
    controlChannelEnabled: Bool
  ) -> TerminalInputEventDecoder<InputEvent> {
    TerminalInputEventDecoder<InputEvent>(
      mouseCoordinateMode: .cells,
      controlChannelEnabled: controlChannelEnabled,
      transform: { parser, input in parser.feed(input) },
      flushTransform: { parser in parser.flush() }
    )
  }

  @Test("with the channel off, Ctrl+^ stays inert and following input types normally")
  func channelOffKeepsTypedInputFlowing() {
    var decoder = makeDecoder(controlChannelEnabled: false)
    // A user types Ctrl+^ (0x1E), then "hi" arrives on the next read. With
    // the channel armed, the armed control parser diverted every following
    // byte into its command buffer until the next newline — the typed text
    // vanished.
    let control = decoder.decode([0x1E])
    #expect(control.controlMessages.isEmpty)
    let typed = decoder.decode(Array("hi".utf8))
    #expect(typed.controlMessages.isEmpty)
    #expect(
      typed.events == [
        .key(KeyPress(.character("h"))),
        .key(KeyPress(.character("i"))),
      ]
    )
  }

  @Test("with the channel on, a typed Ctrl+^ diverts following input (the F138 hazard, pinned)")
  func channelOnDivertsTypedInputAfterIntroducer() {
    var decoder = makeDecoder(controlChannelEnabled: true)
    _ = decoder.decode([0x1E])
    let typed = decoder.decode(Array("hi".utf8))
    #expect(
      typed.events.isEmpty,
      "the armed channel is EXPECTED to buffer post-introducer bytes; this pin documents why the TTY path disables it"
    )
  }

  @Test("with the channel off, a control record is not interpreted")
  func channelOffDoesNotParseControlRecords() {
    var decoder = makeDecoder(controlChannelEnabled: false)
    let batch = decoder.decode(Array("\u{001E}resize:120:40\n".utf8))
    #expect(batch.controlMessages.isEmpty)
  }

  @Test("with the channel on, embedded resize records still parse")
  func channelOnParsesResizeRecords() {
    var decoder = makeDecoder(controlChannelEnabled: true)
    let batch = decoder.decode(Array("\u{001E}resize:120:40\n".utf8))
    #expect(batch.controlMessages == [.resize(.init(width: 120, height: 40))])
    #expect(batch.events.isEmpty)
  }

  @Test("with the channel on, payload around a record still types")
  func channelOnPreservesSurroundingPayload() {
    var decoder = makeDecoder(controlChannelEnabled: true)
    let batch = decoder.decode(Array("a\u{001E}resize:80:24\nb".utf8))
    #expect(batch.controlMessages == [.resize(.init(width: 80, height: 24))])
    #expect(
      batch.events == [
        .key(KeyPress(.character("a"))),
        .key(KeyPress(.character("b"))),
      ]
    )
  }
}
