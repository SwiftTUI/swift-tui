import Dispatch
@_spi(Runners) import SwiftTUI

public struct PerfPresentedFrame {
  public var frameNumber: Int
  public var timestampSeconds: Double
  public var surface: RasterSurface
  public var text: String
  public var metrics: TerminalPresentationMetrics
}

public final class PerfTerminalHost: TerminalHosting {
  public let surfaceSize: CellSize
  public let capabilityProfile: TerminalCapabilityProfile
  public let appearance: TerminalAppearance
  public let graphicsCapabilities: TerminalGraphicsCapabilities
  public let pointerInputCapabilities: PointerInputCapabilities
  public private(set) var presentedFrames: [PerfPresentedFrame] = []

  public init(
    size: PerfTerminalSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback,
    graphicsCapabilities: TerminalGraphicsCapabilities = .none,
    pointerInputCapabilities: PointerInputCapabilities = .cellOnly
  ) {
    self.surfaceSize = CellSize(width: size.columns, height: size.rows)
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
    self.graphicsCapabilities = graphicsCapabilities
    self.pointerInputCapabilities = pointerInputCapabilities
  }

  public func enableRawMode() throws {}
  public func disableRawMode() throws {}
  public func write(_: String) throws {}
  public func clearScreen() throws {}
  public func moveCursor(to _: CellPoint) throws {}
  public func setPointerHoverEnabled(_: Bool) throws {}

  @discardableResult
  public func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let metrics = TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint,
      graphicsReplayScope: surface.imageAttachments.isEmpty ? .none : .full,
      graphicsAttachmentsReplayed: surface.imageAttachments.count
    )
    presentedFrames.append(
      PerfPresentedFrame(
        frameNumber: presentedFrames.count + 1,
        timestampSeconds: Self.monotonicSeconds(),
        surface: surface,
        text: surface.lines.joined(separator: "\n"),
        metrics: metrics
      ))
    return metrics
  }

  public func latestFrame(containing marker: String) -> PerfPresentedFrame? {
    presentedFrames.last { $0.text.contains(marker) }
  }

  public func firstCell(containing marker: String) -> CellPoint? {
    guard let latestFrame = presentedFrames.last else {
      return nil
    }

    for (row, line) in latestFrame.surface.lines.enumerated() {
      guard let range = line.range(of: marker) else {
        continue
      }
      return CellPoint(x: line[..<range.lowerBound].count, y: row)
    }
    return nil
  }

  public var frameRecords: [PerfFrameRecord] {
    presentedFrames.map { frame in
      PerfFrameRecord(
        frameNumber: frame.frameNumber,
        presentedAtSeconds: frame.timestampSeconds,
        presentationDurationMs: 0,
        tailJobState: "completed",
        dropDecision: "commit_ordered"
      )
    }
  }

  private static func monotonicSeconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
  }
}
