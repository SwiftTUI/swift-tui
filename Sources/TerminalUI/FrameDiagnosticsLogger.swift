import Core

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A single diagnostic record capturing one rendered frame's performance data.
public struct FrameDiagnosticRecord: Sendable {
  public var frameNumber: Int
  public var causeSummary: String
  public var focusSyncRerenders: Int
  public var invalidatedIdentityCount: Int
  public var resolvedNodeCount: Int
  public var resolvedNodesComputed: Int
  public var resolvedNodesReused: Int
  public var measuredNodeCount: Int
  public var measuredNodesComputed: Int
  public var measuredNodesReused: Int
  public var placedNodeCount: Int
  public var drawNodeCount: Int
  public var interactionRegionCount: Int
  public var focusRegionCount: Int
  public var phaseTimings: FramePhaseTimings?
  public var presentationStrategy: String
  public var presentationBytesWritten: Int
  public var presentationLinesTouched: Int
  public var presentationCellsChanged: Int
  public var presentationDuration: Duration
  public var damageRowCount: Int?
  public var measurementCacheHitRate: Double?
  public var totalFrameDuration: Duration
}

/// Writes per-frame diagnostic records to a file as tab-separated values.
///
/// Activate by setting a `FrameDiagnosticsLogger` on the run loop before
/// calling `run()`. Records are flushed immediately so the file is always
/// up-to-date even if the process is killed.
@MainActor
public final class FrameDiagnosticsLogger {
  private let fileDescriptor: Int32
  private let ownsDescriptor: Bool
  private var headerWritten = false

  /// Creates a logger that writes to the given file path.
  /// The file is created (or truncated) immediately.
  public init?(path: String) {
    let fd = unsafe open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard fd >= 0 else {
      return nil
    }
    fileDescriptor = fd
    ownsDescriptor = true
  }

  deinit {
    if ownsDescriptor {
      close(fileDescriptor)
    }
  }

  /// Records a single frame's diagnostics.
  public func log(_ record: FrameDiagnosticRecord) {
    if !headerWritten {
      writeHeader()
      headerWritten = true
    }

    let timings = record.phaseTimings
    let resolveMs = formatMs(timings?.resolve)
    let measureMs = formatMs(timings?.measure)
    let placeMs = formatMs(timings?.place)
    let semanticsMs = formatMs(timings?.semantics)
    let drawMs = formatMs(timings?.draw)
    let rasterMs = formatMs(timings?.raster)
    let commitMs = formatMs(timings?.commit)
    let pipelineMs = formatMs(timings?.total)
    let presentMs = formatMs(record.presentationDuration)
    let totalMs = formatMs(record.totalFrameDuration)
    let cacheHit =
      record.measurementCacheHitRate.map { rate in
        let pct = Int(rate * 1000) // tenths of a percent
        return "\(pct / 10).\(pct % 10)%"
      } ?? "-"
    let damageRows = record.damageRowCount.map(String.init) ?? "full"

    let fields: [String] = [
      String(record.frameNumber),
      record.causeSummary,
      String(record.focusSyncRerenders),
      String(record.invalidatedIdentityCount),
      // resolve
      "\(record.resolvedNodesComputed)/\(record.resolvedNodeCount)",
      "\(record.resolvedNodesReused)/\(record.resolvedNodeCount)",
      // measure
      "\(record.measuredNodesComputed)/\(record.measuredNodeCount)",
      // layout
      "\(record.drawNodeCount)",
      "\(record.interactionRegionCount)",
      "\(record.focusRegionCount)",
      // timings
      resolveMs,
      measureMs,
      placeMs,
      semanticsMs,
      drawMs,
      rasterMs,
      commitMs,
      pipelineMs,
      // presentation
      record.presentationStrategy,
      presentMs,
      String(record.presentationBytesWritten),
      String(record.presentationLinesTouched),
      String(record.presentationCellsChanged),
      damageRows,
      // cache
      cacheHit,
      // total
      totalMs,
    ]

    writeLine(fields.joined(separator: "\t"))
  }

  private func writeHeader() {
    let headers = [
      "frame",
      "causes",
      "focus_syncs",
      "invalidated",
      "resolved_computed",
      "resolved_reused",
      "measured_computed",
      "draw_nodes",
      "interactions",
      "focus_regions",
      "resolve_ms",
      "measure_ms",
      "place_ms",
      "semantics_ms",
      "draw_ms",
      "raster_ms",
      "commit_ms",
      "pipeline_ms",
      "present_strategy",
      "present_ms",
      "present_bytes",
      "present_lines",
      "present_cells",
      "damage_rows",
      "cache_hit",
      "total_ms",
    ]
    writeLine(headers.joined(separator: "\t"))
  }

  private func writeLine(_ line: String) {
    var data = line + "\n"
    data.withUTF8 { buffer in
      _ = unsafe write(fileDescriptor, buffer.baseAddress, buffer.count)
    }
  }

  private func formatMs(_ duration: Duration?) -> String {
    guard let duration else {
      return "-"
    }
    let totalMicroseconds =
      duration.components.seconds * 1_000_000
      + duration.components.attoseconds / 1_000_000_000_000
    let ms = totalMicroseconds / 1000
    let frac = (totalMicroseconds % 1000) / 10
    return "\(ms).\(frac < 10 ? "0" : "")\(frac)"
  }
}
