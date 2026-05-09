@unsafe @preconcurrency import Dispatch
@_spi(Runners) import SwiftTUI
import Synchronization
@_spi(WebHost) import WASISurfaceBridge

package protocol WebHostByteSink: Sendable {
  func send(_ bytes: [UInt8]) async throws
}

package enum WebHostByteSinkError: Error, Equatable, Sendable, CustomStringConvertible {
  case sendFailed(String)
  case sendDidNotComplete

  package var description: String {
    switch self {
    case .sendFailed(let message):
      return "WebHost byte sink failed: \(message)"
    case .sendDidNotComplete:
      return "WebHost byte sink did not complete."
    }
  }
}

package final class WebSocketSurfaceTransport: PresentationSurface,
  ClipboardWritingPresentationSurface,
  SemanticPresentationSurface, Sendable
{
  private struct State: Sendable {
    var surfaceSize: CellSize
    var renderStyle: TerminalRenderStyle
    var graphicsCapabilities: TerminalGraphicsCapabilities
    var pointerInputCapabilities: PointerInputCapabilities
    var transmittedImageIDs: Set<String>
  }

  private let state: Mutex<State>
  private let sink: any WebHostByteSink
  private let sendLock = Mutex(())

  package let capabilityProfile = TerminalCapabilityProfile(
    glyphLevel: .unicode,
    colorLevel: .trueColor,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: true,
    supportsMouseReporting: true,
    supportsSynchronizedOutput: false
  )

  package init(
    surfaceSize: CellSize,
    sink: any WebHostByteSink,
    renderStyle: TerminalRenderStyle = .init(appearance: .fallback)
  ) {
    self.sink = sink
    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        renderStyle: renderStyle,
        graphicsCapabilities: .none,
        pointerInputCapabilities: .cellOnly,
        transmittedImageIDs: []
      )
    )
  }

  package var surfaceSize: CellSize {
    state.withLock(\.surfaceSize)
  }

  package var appearance: TerminalAppearance {
    state.withLock(\.renderStyle.appearance)
  }

  package var theme: Theme? {
    state.withLock(\.renderStyle.theme)
  }

  package var graphicsCapabilities: TerminalGraphicsCapabilities {
    state.withLock(\.graphicsCapabilities)
  }

  package var pointerInputCapabilities: PointerInputCapabilities {
    state.withLock(\.pointerInputCapabilities)
  }

  package func updateSurfaceSize(
    _ surfaceSize: CellSize,
    cellPixelSize: PixelSize? = nil
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
      state.graphicsCapabilities.cellPixelSize = cellPixelSize
      state.pointerInputCapabilities = Self.pointerInputCapabilities(for: cellPixelSize)
    }
  }

  package func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
    }
  }

  package func enableRawMode() throws {}

  package func disableRawMode() throws {}

  package func write(_: String) throws {}

  package func clearScreen() throws {}

  package func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  @MainActor
  package func writeClipboard(_ text: String) throws -> Bool {
    try sendBytes(Array(WebSurfaceFrameEncoder.encodeClipboard(text).utf8))
    return true
  }

  @discardableResult
  package func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    let bytes = state.withLock { state in
      Array(
        WebSurfaceFrameEncoder.encode(
          surface,
          knownImageIDs: &state.transmittedImageIDs
        ).utf8
      )
    }
    try sendBytes(bytes)
    return metrics(for: surface, byteCount: bytes.count)
  }

  @discardableResult
  package func present(
    _ surface: RasterSurface,
    semanticSnapshot: SemanticSnapshot,
    focusedIdentity: Identity?
  ) throws -> TerminalPresentationMetrics {
    let bytes = state.withLock { state in
      Array(
        WebSurfaceFrameEncoder.encode(
          surface,
          semanticSnapshot: semanticSnapshot,
          focusedIdentity: focusedIdentity,
          knownImageIDs: &state.transmittedImageIDs
        ).utf8
      )
    }
    try sendBytes(bytes)
    return metrics(for: surface, byteCount: bytes.count)
  }

  private static func pointerInputCapabilities(
    for cellPixelSize: PixelSize?
  ) -> PointerInputCapabilities {
    guard let cellPixelSize else {
      return .cellOnly
    }
    return PointerInputCapabilities(
      precision: .subCell(
        source: .webPixels,
        metrics: CellPixelMetrics(
          width: cellPixelSize.width,
          height: cellPixelSize.height,
          source: .reported
        )
      ),
      supportsHover: true
    )
  }

  private func sendBytes(
    _ bytes: [UInt8]
  ) throws {
    guard !bytes.isEmpty else {
      return
    }

    try sendLock.withLock { _ in
      let semaphore = DispatchSemaphore(value: 0)
      let result = Mutex<Result<Void, WebHostByteSinkError>?>(nil)
      let sink = self.sink

      Task {
        do {
          try await sink.send(bytes)
          result.withLock { result in
            result = .success(())
          }
        } catch {
          result.withLock { result in
            result = .failure(.sendFailed(String(describing: error)))
          }
        }
        semaphore.signal()
      }

      semaphore.wait()
      try result.withLock { result in
        result ?? .failure(.sendDidNotComplete)
      }.get()
    }
  }

  private func metrics(
    for surface: RasterSurface,
    byteCount: Int
  ) -> TerminalPresentationMetrics {
    TerminalPresentationMetrics(
      bytesWritten: byteCount,
      linesTouched: max(0, surface.size.height),
      cellsChanged: max(0, surface.size.width) * max(0, surface.size.height),
      strategy: .fullRepaint,
      graphicsReplayScope: surface.imageAttachments.isEmpty ? .none : .full,
      graphicsAttachmentsReplayed: surface.imageAttachments.count
    )
  }
}
