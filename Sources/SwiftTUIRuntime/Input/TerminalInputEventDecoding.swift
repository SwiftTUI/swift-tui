struct TerminalInputDecodedBatch<Event: Sendable> {
  var controlMessages: [TerminalControlMessage]
  var events: [Event]
}

struct TerminalInputEventDecoder<Event: Sendable> {
  private var parser: TerminalInputParser
  private var controlParser = ControlMessageParser()
  private let transform: @Sendable (inout TerminalInputParser, [UInt8]) -> [Event]
  private let flushTransform: @Sendable (inout TerminalInputParser) -> [Event]

  init(
    mouseCoordinateMode: MouseCoordinateMode,
    transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event],
    flushTransform: @escaping @Sendable (inout TerminalInputParser) -> [Event]
  ) {
    parser = TerminalInputParser(mouseCoordinateMode: mouseCoordinateMode)
    self.transform = transform
    self.flushTransform = flushTransform
  }

  /// True when the parser is holding a lone ESC awaiting the run loop's idle
  /// escape-timeout. See ``TerminalInputParser/isAwaitingEscapeDisambiguation``.
  var isAwaitingEscapeDisambiguation: Bool {
    parser.isAwaitingEscapeDisambiguation
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

  /// Drains a lingering lone ESC as an Escape event, mapped through the same
  /// projection as ``decode(_:)`` so keyboard-only and full input streams both
  /// receive it. Returns an empty array when no lone ESC is pending.
  mutating func flushEscape() -> [Event] {
    flushTransform(&parser)
  }
}
