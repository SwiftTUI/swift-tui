import SwiftTUICore
import Synchronization

/// Raster and semantic presentation surface for retained non-terminal hosts.
public final class HostedRasterSurface:
  PresentationSurfaceMetricsProvider, RasterPresentationSurface,
  ClipboardWritingPresentationSurface, Sendable
{
  private static let frameHistoryLimit = 256
  private let state: Mutex<HostedRasterSurfaceState>
  private let frameHandler: @Sendable (SemanticHostFrame) -> Void
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
    onFrame: @escaping @MainActor @Sendable (SemanticHostFrame) -> Void,
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
      HostedRasterSurfaceState(
        surfaceSize: surfaceSize,
        renderStyle: .init(
          appearance: appearance,
          theme: theme
        ),
        graphicsCapabilities: .none,
        pointerInputCapabilities: .cellOnly,
        nextFrameSequence: 0
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

  @discardableResult
  @MainActor
  public func writeClipboard(_ text: String) throws -> Bool {
    clipboardWriter?(text) ?? false
  }

  @_spi(Runners) public func waitForFrame(
    matching predicate: @escaping @Sendable (SemanticHostFrame) -> Bool = { _ in true }
  ) async -> SemanticHostFrame {
    if let frame = state.withLock({ state in state.frames.first(where: predicate) }) {
      return frame
    }

    return await withCheckedContinuation { continuation in
      let immediate = state.withLock { state -> SemanticHostFrame? in
        if let frame = state.frames.first(where: predicate) {
          return frame
        }
        state.frameWaiters.append(
          HostedFrameWaiter(
            predicate: predicate,
            continuation: continuation
          )
        )
        return nil
      }
      if let immediate {
        continuation.resume(returning: immediate)
      }
    }
  }

  @_spi(Runners) public func waitForSurface(
    matching predicate: @escaping @Sendable (RasterSurface) -> Bool = { _ in true }
  ) async -> RasterSurface {
    let frame = await waitForFrame { frame in
      predicate(frame.raster)
    }
    return frame.raster
  }

  @_spi(Runners) public func waitForFrames(
    matching predicate: @escaping @Sendable ([SemanticHostFrame]) -> Bool
  ) async -> [SemanticHostFrame] {
    if let frames = state.withLock({ state -> [SemanticHostFrame]? in
      predicate(state.frames) ? state.frames : nil
    }) {
      return frames
    }

    return await withCheckedContinuation { continuation in
      let immediate = state.withLock { state -> [SemanticHostFrame]? in
        if predicate(state.frames) {
          return state.frames
        }
        state.frameSequenceWaiters.append(
          HostedFrameSequenceWaiter(
            predicate: predicate,
            continuation: continuation
          )
        )
        return nil
      }
      if let immediate {
        continuation.resume(returning: immediate)
      }
    }
  }

  @discardableResult
  public func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    let sequence = state.withLock { state in
      let sequence = state.nextFrameSequence
      state.nextFrameSequence &+= 1
      return sequence
    }
    return try present(
      SemanticHostFrame(
        sequence: sequence,
        raster: surface,
        semantics: .init(),
        focusedIdentity: nil
      )
    )
  }

  private func submit(
    _ frame: SemanticHostFrame
  ) {
    let (frameContinuations, sequenceContinuations, framesSnapshot) = state.withLock { state in
      if frame.sequence >= state.nextFrameSequence {
        state.nextFrameSequence = frame.sequence &+ 1
      }
      state.frames.append(frame)
      if state.frames.count > Self.frameHistoryLimit {
        state.frames.removeFirst(state.frames.count - Self.frameHistoryLimit)
      }

      var frameContinuations: [CheckedContinuation<SemanticHostFrame, Never>] = []
      var sequenceContinuations: [CheckedContinuation<[SemanticHostFrame], Never>] = []
      state.frameWaiters.removeAll { waiter in
        guard waiter.predicate(frame) else {
          return false
        }
        frameContinuations.append(waiter.continuation)
        return true
      }
      state.frameSequenceWaiters.removeAll { waiter in
        guard waiter.predicate(state.frames) else {
          return false
        }
        sequenceContinuations.append(waiter.continuation)
        return true
      }
      return (frameContinuations, sequenceContinuations, state.frames)
    }
    for continuation in frameContinuations {
      continuation.resume(returning: frame)
    }
    for continuation in sequenceContinuations {
      continuation.resume(returning: framesSnapshot)
    }
    frameHandler(frame)
  }
}

@_spi(Runners)
extension HostedRasterSurface: SemanticHostFramePresentationSurface {
  @discardableResult
  public func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    submit(frame)
    return TerminalPresentationMetrics.rasterHostMetrics(
      for: frame.raster,
      damage: frame.rasterDamage
    )
  }
}
