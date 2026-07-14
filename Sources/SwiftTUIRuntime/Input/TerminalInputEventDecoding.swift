struct TerminalInputDecodedBatch<Event: Sendable> {
  var controlMessages: [TerminalControlMessage]
  var events: [Event]
}

struct TerminalInputEventDecoder<Event: Sendable> {
  private var parser: TerminalInputParser
  private var controlParser = ControlMessageParser()
  private let controlChannelEnabled: Bool
  private let transform: @Sendable (inout TerminalInputParser, [UInt8]) -> [Event]
  private let flushTransform: @Sendable (inout TerminalInputParser) -> [Event]

  /// `controlChannelEnabled` gates the in-band 0x1E control-message channel
  /// (F138). The only writers are embedded-host transports (the WebHost
  /// browser transport's stdin records, hosted-session injection) — a real
  /// interactive terminal never emits the introducer, but leaving the parser
  /// armed there lets a typed Ctrl+^ silently divert ALL input into the
  /// control buffer until the next newline. Off, bytes flow straight to the
  /// key/mouse parser.
  init(
    mouseCoordinateMode: MouseCoordinateMode,
    controlChannelEnabled: Bool = true,
    transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event],
    flushTransform: @escaping @Sendable (inout TerminalInputParser) -> [Event]
  ) {
    parser = TerminalInputParser(mouseCoordinateMode: mouseCoordinateMode)
    self.controlChannelEnabled = controlChannelEnabled
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
    guard controlChannelEnabled else {
      return TerminalInputDecodedBatch(
        controlMessages: [],
        events: transform(&parser, bytes)
      )
    }
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
