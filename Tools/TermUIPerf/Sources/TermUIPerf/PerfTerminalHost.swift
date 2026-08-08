import Dispatch
@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime

public struct PerfPresentedFrame {
  public var frameNumber: Int
  public var timestampSeconds: Double
  public var surface: RasterSurface
  public var text: String
  public var metrics: TerminalPresentationMetrics
}

/// The emission-visible perf lane (R2.4a), armed by `SWIFTTUI_PERF_EMISSION=1`.
///
/// Lane ON swaps the scenario's presentation surface from the semantic-host
/// perf path — where the terminal planner and emission builder never run and
/// `present_bytes` is structurally 0 — to `TerminalEmissionSimulationHost`,
/// which runs the REAL planner + emission builder against a byte-counting
/// sink under a fixed capability profile (unicode/truecolor, synchronized
/// output ON, kitty graphics OFF, CSI-K lowering ON; see
/// `TerminalEmissionSimulationHost.laneCapabilityProfile`).
///
/// The lane ADDS planner/emission cost to `present_ms`/`total_ms` and is
/// recorded in `run.json`, `summary.json`, and the aggregate, so `compare`
/// refuses a lane-on vs lane-off comparison instead of certifying one.
public enum PerfEmissionLane {
  public static let environmentVariableName = "SWIFTTUI_PERF_EMISSION"

  public static var isEnabled: Bool {
    guard let raw = environmentValue(environmentVariableName) else {
      return false
    }
    return !raw.isEmpty && raw != "0"
  }
}

public final class PerfTerminalHost: PresentationSurface {
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
    recordPresentedFrame(
      surface: surface,
      metrics: TerminalPresentationMetrics.rasterHostMetrics(
        for: surface,
        damage: nil
      )
    )
  }

  /// Records a frame presented by an external surface (the emission lane's
  /// simulation host) with the metrics that surface computed, keeping this
  /// host the single presented-frame log the drivers and readers consume.
  @discardableResult
  public func recordFrame(
    surface: RasterSurface,
    metrics: TerminalPresentationMetrics
  ) -> TerminalPresentationMetrics {
    recordPresentedFrame(surface: surface, metrics: metrics)
  }

  @discardableResult
  private func recordPresentedFrame(
    surface: RasterSurface,
    metrics: TerminalPresentationMetrics
  ) -> TerminalPresentationMetrics {
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

@_spi(Runners)
extension PerfTerminalHost: SemanticHostFramePresentationSurface {
  public var semanticHostFrameCapabilities: SemanticHostFrameCapabilities { [.rasterDamage] }

  @discardableResult
  public func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    recordPresentedFrame(
      surface: frame.raster,
      metrics: TerminalPresentationMetrics.rasterHostMetrics(
        for: frame.raster,
        damage: frame.rasterDamage
      )
    )
  }
}
