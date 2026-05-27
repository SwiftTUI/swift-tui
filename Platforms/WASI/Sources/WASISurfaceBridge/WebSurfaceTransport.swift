@_spi(Runners) package import SwiftTUIRuntime
import Synchronization

package final class WebSurfaceTransport: PresentationSurfaceMetricsProvider,
  RasterPresentationSurface, ClipboardWritingPresentationSurface,
  SemanticHostFramePresentationSurface,
  Sendable
{
  private struct State: Sendable {
    var surfaceSize: CellSize
    var renderStyle: TerminalRenderStyle
    var graphicsCapabilities: TerminalGraphicsCapabilities
    var pointerInputCapabilities: PointerInputCapabilities
    var encodingState: WebSurfaceFrameEncodingState
  }

  private let state: Mutex<State>
  private let outputFileDescriptor: Int32
  private let writeLock = Mutex(())

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
    outputFileDescriptor: Int32 = webSurfaceStandardOutputFileDescriptor,
    renderStyle: TerminalRenderStyle,
    deltaEncodingEnabled: Bool = false
  ) {
    self.outputFileDescriptor = outputFileDescriptor
    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        renderStyle: renderStyle,
        graphicsCapabilities: .none,
        pointerInputCapabilities: Self.pointerInputCapabilities(for: nil),
        encodingState: WebSurfaceFrameEncodingState(deltaEnabled: deltaEncodingEnabled)
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
      state.pointerInputCapabilities = Self.pointerInputCapabilities(
        for: cellPixelSize
      )
    }
  }

  private static func pointerInputCapabilities(
    for cellPixelSize: PixelSize?
  ) -> PointerInputCapabilities {
    let metrics =
      if let cellPixelSize {
        CellPixelMetrics(
          width: cellPixelSize.width,
          height: cellPixelSize.height,
          source: .reported
        )
      } else {
        CellPixelMetrics.estimated
      }
    return PointerInputCapabilities(
      precision: .subCell(source: .webPixels, metrics: metrics),
      supportsHover: true
    )
  }

  package func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
    }
  }

  @discardableResult
  @MainActor
  package func writeClipboard(_ text: String) throws -> Bool {
    let bytes = Array(WebSurfaceFrameEncoder.encodeClipboard(text).utf8)
    try writeBytes(bytes)
    return true
  }

  package func notifyRuntimeIssue(_ issue: RuntimeIssue) throws {
    try writeBytes(Array(WebSurfaceFrameEncoder.encodeRuntimeIssue(issue).utf8))
  }

  package func notifyFrameDiagnostic(_ record: FrameDiagnosticRecord) throws {
    try writeBytes(Array(WebSurfaceFrameEncoder.encodeFrameDiagnostic(record).utf8))
  }

  @discardableResult
  package func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    let bytes = state.withLock { state in
      Array(
        WebSurfaceFrameEncoder.encode(
          surface,
          damage: nil,
          state: &state.encodingState
        ).utf8
      )
    }
    try writeBytes(bytes)
    return .rasterHostMetrics(
      for: surface,
      damage: nil,
      bytesWritten: bytes.count
    )
  }

  @discardableResult
  package func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    let bytes = state.withLock { state in
      Array(
        WebSurfaceFrameEncoder.encode(
          frame,
          state: &state.encodingState
        ).utf8
      )
    }
    try writeBytes(bytes)
    return .rasterHostMetrics(
      for: frame.raster,
      damage: frame.rasterDamage,
      bytesWritten: bytes.count
    )
  }

  private func writeBytes(
    _ bytes: [UInt8]
  ) throws {
    guard !bytes.isEmpty else {
      return
    }

    try writeLock.withLock { _ in
      var written = 0
      while written < bytes.count {
        let result = unsafe bytes.withUnsafeBytes { rawBuffer in
          let baseAddress = unsafe rawBuffer.baseAddress?.advanced(by: written)
          return unsafe webSurfaceWrite(
            outputFileDescriptor,
            baseAddress,
            bytes.count - written
          )
        }

        if result < 0 {
          throw TerminalHostError.failedToWrite(errno: webSurfaceErrno)
        }

        written += result
      }
    }
  }
}
