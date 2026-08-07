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
    /// The page's last `pointer:panning=` declaration. Held separately from
    /// `pointerInputCapabilities` because the two are refreshed by different
    /// events — a resize recomputes precision from fresh cell metrics and must
    /// not discard a paradigm the page declared earlier.
    var supportsScrollPanning: Bool
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

  /// The host's declared wire capabilities.
  ///
  /// Ingress lifecycle: environment keys, resolved once at construction.
  /// There is no runtime declaration channel here — a browser reload
  /// re-instantiates the in-process transport rather than reconnecting, so a
  /// `caps:` record arriving on stdin is deliberately dropped by the runner.
  ///
  /// Emission is negotiated from this value and nothing else. It previously
  /// sat beside an independently-resolved `deltaEncodingEnabled` flag, which
  /// let the transport enable delta records the declaration had not asked
  /// for; the two answers are now one.
  package let wireCapabilities: HostWireCapabilities

  package init(
    surfaceSize: CellSize,
    outputFileDescriptor: Int32 = webSurfaceStandardOutputFileDescriptor,
    renderStyle: TerminalRenderStyle,
    wireCapabilities: HostWireCapabilities = HostWireCapabilities()
  ) {
    self.outputFileDescriptor = outputFileDescriptor
    self.wireCapabilities = wireCapabilities
    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        renderStyle: renderStyle,
        graphicsCapabilities: .none,
        pointerInputCapabilities: Self.pointerInputCapabilities(
          for: nil,
          supportsScrollPanning: false
        ),
        encodingState: wireCapabilities.negotiatedEncodingState(),
        supportsScrollPanning: false
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
        for: cellPixelSize,
        supportsScrollPanning: state.supportsScrollPanning
      )
    }
  }

  /// Applies the page's `pointer:` paradigm declaration.
  ///
  /// A browser serves both paradigms from one build, so this cannot be
  /// resolved from the WASI environment the way the wire capabilities are: the
  /// page reports what it sees (a coarse pointer, a touch-first device) and
  /// may report it again when that changes.
  package func updatePointerCapabilities(
    supportsScrollPanning: Bool
  ) {
    state.withLock { state in
      state.supportsScrollPanning = supportsScrollPanning
      state.pointerInputCapabilities = Self.pointerInputCapabilities(
        for: state.graphicsCapabilities.cellPixelSize,
        supportsScrollPanning: supportsScrollPanning
      )
    }
  }

  private static func pointerInputCapabilities(
    for cellPixelSize: PixelSize?,
    supportsScrollPanning: Bool
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
      supportsHover: true,
      supportsScrollPanning: supportsScrollPanning
    )
  }

  package func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
    }
  }

  package func requestResync(
    _ request: HostWireResyncRequest
  ) {
    state.withLock { state in
      state.encodingState.requestResync(request)
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
          fallbackBackground: state.renderStyle.appearance.backgroundColor,
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
          fallbackBackground: state.renderStyle.appearance.backgroundColor,
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
