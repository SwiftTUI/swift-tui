import SwiftTUICore
import Synchronization

/// Raster and semantic presentation surface for retained non-terminal hosts.
public final class HostedRasterSurface:
  PresentationSurface, ClipboardWritingPresentationSurface, Sendable
{
  private struct State: Sendable {
    var surfaceSize: CellSize
    var renderStyle: TerminalRenderStyle
    var graphicsCapabilities: TerminalGraphicsCapabilities
    var pointerInputCapabilities: PointerInputCapabilities
  }

  private let state: Mutex<State>
  private let frameHandler: @Sendable (SemanticPresentationFrame) -> Void
  private let clipboardWriter: (@MainActor @Sendable (String) -> Bool)?

  public let capabilityProfile: TerminalCapabilityProfile

  public var surfaceSize: CellSize {
    state.withLock(\.surfaceSize)
  }

  public var appearance: TerminalAppearance {
    state.withLock(\.renderStyle.appearance)
  }

  public var theme: Theme? {
    state.withLock(\.renderStyle.theme)
  }

  public var graphicsCapabilities: TerminalGraphicsCapabilities {
    state.withLock(\.graphicsCapabilities)
  }

  public var pointerInputCapabilities: PointerInputCapabilities {
    state.withLock(\.pointerInputCapabilities)
  }

  public init(
    surfaceSize: CellSize,
    appearance: TerminalAppearance,
    theme: Theme? = nil,
    capabilityProfile: TerminalCapabilityProfile = .trueColor,
    onFrame: @escaping @MainActor @Sendable (SemanticPresentationFrame) -> Void,
    onClipboardWrite: (@MainActor @Sendable (String) -> Bool)? = nil
  ) {
    self.capabilityProfile = capabilityProfile
    frameHandler = { frame in
      Task { @MainActor in
        onFrame(frame)
      }
    }
    clipboardWriter = onClipboardWrite
    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        renderStyle: .init(
          appearance: appearance,
          theme: theme
        ),
        graphicsCapabilities: .none,
        pointerInputCapabilities: .cellOnly
      )
    )
  }

  public func updateSurfaceSize(
    _ surfaceSize: CellSize
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
    }
  }

  public func updateAppearance(
    _ appearance: TerminalAppearance
  ) {
    state.withLock { state in
      state.renderStyle.appearance = appearance
    }
  }

  public func updateTheme(
    _ theme: Theme?
  ) {
    state.withLock { state in
      state.renderStyle.theme = theme
    }
  }

  public func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
    }
  }

  public func updateSurfaceCapabilities(
    cellPixelSize: PixelSize?,
    pointerInputCapabilities: PointerInputCapabilities
  ) {
    state.withLock { state in
      state.graphicsCapabilities.cellPixelSize = cellPixelSize
      state.pointerInputCapabilities = pointerInputCapabilities
    }
  }

  public func enableRawMode() throws {}

  public func disableRawMode() throws {}

  public func write(_: String) throws {}

  public func clearScreen() throws {}

  public func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  @MainActor
  public func writeClipboard(_ text: String) throws -> Bool {
    clipboardWriter?(text) ?? false
  }

  @discardableResult
  public func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    try present(
      SemanticPresentationFrame(
        surface: surface,
        semanticSnapshot: .init(),
        focusedIdentity: nil
      )
    )
  }

  private func submit(
    _ frame: SemanticPresentationFrame
  ) {
    frameHandler(frame)
  }
}

@_spi(Runners)
extension HostedRasterSurface: DamageAwareSemanticPresentationSurface {
  @discardableResult
  public func present(_ frame: SemanticPresentationFrame) throws -> TerminalPresentationMetrics {
    submit(frame)
    return TerminalPresentationMetrics.rasterHostMetrics(
      for: frame.surface,
      damage: frame.rasterDamage
    )
  }
}
