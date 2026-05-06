@_spi(Runners) import SwiftTUI
@_spi(WebHost) import WASISurfaceBridge

package protocol WebHostByteSource: Sendable {
  func chunks() -> AsyncStream<[UInt8]>
}

package final class WebSocketInputReader: TerminalInputReading, Sendable {
  private let source: any WebHostByteSource
  private let controlHandler: @Sendable (WebSurfaceInputControlMessage) -> Void

  init(
    source: any WebHostByteSource,
    controlHandler: @escaping @Sendable (WebSurfaceInputControlMessage) -> Void = { _ in }
  ) {
    self.source = source
    self.controlHandler = controlHandler
  }

  package convenience init(
    source: any WebHostByteSource,
    transport: WebSocketSurfaceTransport
  ) {
    self.init(source: source) { message in
      switch message {
      case .resize(let size, let cellPixelSize):
        transport.updateSurfaceSize(size, cellPixelSize: cellPixelSize)
      case .style(let style):
        transport.updateStyle(style)
      }
    }
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let source = self.source
      let controlHandler = self.controlHandler

      let task = Task {
        var parser = WebSurfaceInputParser()
        for await chunk in source.chunks() {
          let parsed = parser.feed(chunk)
          for controlMessage in parsed.controlMessages {
            controlHandler(controlMessage)
          }
          for event in parsed.events {
            continuation.yield(event)
          }
          await Task.yield()
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
