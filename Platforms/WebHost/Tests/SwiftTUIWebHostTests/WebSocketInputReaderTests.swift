@_spi(Runners) import SwiftTUI
import Testing

@testable import SwiftTUIWebHost

struct WebSocketInputReaderTests {
  @Test("resize and style input update the transport")
  func resizeAndStyleInputUpdateTransport() async throws {
    let source = InMemoryByteSource()
    let sink = RecordingInputTestSink()
    let transport = WebSocketSurfaceTransport(
      surfaceSize: .init(width: 1, height: 1),
      sink: sink
    )
    let reader = WebSocketInputReader(source: source, transport: transport)
    let events = reader.inputEvents()
    var iterator = events.makeAsyncIterator()
    let style = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: .hex("#102030"),
        backgroundColor: .hex("#405060"),
        tintColor: .hex("#708090"),
        source: .override
      )
    )
    let encodedStyle = try #require(TerminalRenderStyleCodec.encodeBase64(style))

    await source.yield("\u{001E}resize:80:24:9:18\n\u{001E}style:\(encodedStyle)\n")
    await source.finish()

    #expect(await iterator.next() == nil)
    #expect(transport.surfaceSize == .init(width: 80, height: 24))
    #expect(transport.appearance == style.appearance)
    #expect(transport.pointerInputCapabilities.precision.isSubCell)
  }

  @Test("key and paste input yield expected input events")
  func keyAndPasteInputYieldExpectedEvents() async throws {
    let source = InMemoryByteSource()
    let reader = WebSocketInputReader(source: source)
    let events = reader.inputEvents()
    var iterator = events.makeAsyncIterator()

    await source.yield("\u{001E}key:character:A:1\n\u{001E}paste:hello%20web\n")

    #expect(await iterator.next() == .key(.init(.character("A"), modifiers: [.shift])))
    #expect(await iterator.next() == .paste(.init(content: "hello web")))

    await source.finish()
    #expect(await iterator.next() == nil)
  }
}

private actor InMemoryByteSource: WebHostByteSource {
  nonisolated let stream: AsyncStream<[UInt8]>
  private let continuation: AsyncStream<[UInt8]>.Continuation

  init() {
    var continuation: AsyncStream<[UInt8]>.Continuation?
    stream = AsyncStream { continuation = $0 }
    self.continuation = continuation!
  }

  nonisolated func chunks() -> AsyncStream<[UInt8]> {
    stream
  }

  func yield(
    _ text: String
  ) {
    continuation.yield(Array(text.utf8))
  }

  func finish() {
    continuation.finish()
  }
}

private actor RecordingInputTestSink: WebHostByteSink {
  func send(_: [UInt8]) async throws {}
}
