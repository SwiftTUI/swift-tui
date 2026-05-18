struct TerminalInputDecodedBatch<Event: Sendable> {
  var controlMessages: [TerminalControlMessage]
  var events: [Event]
}

struct TerminalInputEventDecoder<Event: Sendable> {
  private var parser: TerminalInputParser
  private var controlParser = ControlMessageParser()
  private let transform: @Sendable (inout TerminalInputParser, [UInt8]) -> [Event]

  init(
    mouseCoordinateMode: MouseCoordinateMode,
    transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event]
  ) {
    parser = TerminalInputParser(mouseCoordinateMode: mouseCoordinateMode)
    self.transform = transform
  }

  mutating func decode(
    _ bytes: [UInt8]
  ) -> TerminalInputDecodedBatch<Event> {
    let filtered = controlParser.feed(bytes)
    return TerminalInputDecodedBatch(
      controlMessages: filtered.messages,
      events: transform(&parser, filtered.payload)
    )
  }
}
