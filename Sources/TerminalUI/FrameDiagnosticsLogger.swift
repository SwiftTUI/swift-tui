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
  public var renderGenerations: FrameRenderGenerations
  public var desiredGeneration: UInt64
  public var coalescedEventBatches: Int
  public var coalescedWakeCauses: String
  public var workerTimings: FrameWorkerTimings?
  public var mainActorTimings: FrameMainActorTimings?
  public var customLayoutFallbackCount: Int
  public var firstCustomLayoutFallbackIdentity: String?
  public var staleFramePolicy: String
  public var inputEventsQueuedDuringRenderSuspension: Int
  public var presentationStrategy: String
  public var presentationBytesWritten: Int
  public var presentationLinesTouched: Int
  public var presentationCellsChanged: Int
  public var presentationDuration: Duration
  public var damageRowCount: Int?
  public var damageRangeAwareRowCount: Int?
  public var damageTextSpanCount: Int?
  public var damageTextCellCount: Int?
  public var damageGraphicsInvalidationCount: Int?
  public var damageRequiresFullTextRepaint: Bool
  public var damageRequiresFullGraphicsReplay: Bool
  public var presentationUsedSynchronizedOutput: Bool
  public var presentationGraphicsReplayScope: String
  public var presentationGraphicsAttachmentsReplayed: Int
  public var presentationEditOperationLowering: String
  public var presentationEditOperationCount: Int
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
    #if !canImport(WASILibc)
      let fd = unsafe open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
      guard fd >= 0 else {
        return nil
      }
      fileDescriptor = fd
      ownsDescriptor = true
    #else
      // WASI builds have no POSIX file I/O exposed; the logger is unavailable.
      fileDescriptor = -1
      ownsDescriptor = false
      return nil
    #endif
  }

  deinit {
    #if !canImport(WASILibc)
      if ownsDescriptor {
        close(fileDescriptor)
      }
    #endif
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
    let workerTimings = record.workerTimings
    let renderGenerations = record.renderGenerations
    let layoutEnqueueMs = formatMs(workerTimings?.layoutEnqueueToStart)
    let layoutComputeMs = formatMs(workerTimings?.layoutCompute)
    let rasterEnqueueMs = formatMs(workerTimings?.rasterEnqueueToStart)
    let rasterComputeMs = formatMs(workerTimings?.rasterCompute)
    let workerCompletionToCommitMs = formatMs(workerTimings?.completionToMainCommit)
    let mainActorTimings = record.mainActorTimings
    let mainActorBlockedMs = formatMs(mainActorTimings?.blocked)
    let mainActorSuspendedMs = formatMs(mainActorTimings?.suspended)
    let presentMs = formatMs(record.presentationDuration)
    let totalMs = formatMs(record.totalFrameDuration)
    let cacheHit =
      record.measurementCacheHitRate.map { rate in
        let pct = Int(rate * 1000)  // tenths of a percent
        return "\(pct / 10).\(pct % 10)%"
      } ?? "-"
    let damageRows = record.damageRowCount.map(String.init) ?? "full"
    let damageRangeAwareRows = record.damageRangeAwareRowCount.map(String.init) ?? "-"
    let damageSpans = record.damageTextSpanCount.map(String.init) ?? "-"
    let damageCells = record.damageTextCellCount.map(String.init) ?? "-"
    let damageGraphics = record.damageGraphicsInvalidationCount.map(String.init) ?? "-"

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
      String(record.desiredGeneration),
      String(renderGenerations.render.rawValue),
      formatGeneration(renderGenerations.layoutInput),
      formatGeneration(renderGenerations.layoutOutput),
      formatGeneration(renderGenerations.rasterInput),
      formatGeneration(renderGenerations.rasterOutput),
      String(record.coalescedEventBatches),
      record.coalescedWakeCauses,
      layoutEnqueueMs,
      layoutComputeMs,
      rasterEnqueueMs,
      rasterComputeMs,
      workerCompletionToCommitMs,
      mainActorBlockedMs,
      mainActorSuspendedMs,
      String(record.customLayoutFallbackCount),
      record.firstCustomLayoutFallbackIdentity ?? "-",
      record.staleFramePolicy,
      String(record.inputEventsQueuedDuringRenderSuspension),
      // presentation
      record.presentationStrategy,
      presentMs,
      String(record.presentationBytesWritten),
      String(record.presentationLinesTouched),
      String(record.presentationCellsChanged),
      damageRows,
      damageRangeAwareRows,
      damageSpans,
      damageCells,
      damageGraphics,
      record.damageRequiresFullTextRepaint ? "1" : "0",
      record.damageRequiresFullGraphicsReplay ? "1" : "0",
      record.presentationUsedSynchronizedOutput ? "1" : "0",
      record.presentationGraphicsReplayScope,
      String(record.presentationGraphicsAttachmentsReplayed),
      record.presentationEditOperationLowering,
      String(record.presentationEditOperationCount),
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
      "desired_generation",
      "render_generation",
      "layout_input_generation",
      "layout_output_generation",
      "raster_input_generation",
      "raster_output_generation",
      "coalesced_event_batches",
      "coalesced_wake_causes",
      "worker_layout_enqueue_ms",
      "worker_layout_compute_ms",
      "worker_raster_enqueue_ms",
      "worker_raster_compute_ms",
      "worker_completion_to_commit_ms",
      "main_actor_blocked_ms",
      "main_actor_suspended_ms",
      "custom_layout_fallbacks",
      "first_custom_layout_fallback",
      "stale_frame_policy",
      "input_events_during_render_suspension",
      "present_strategy",
      "present_ms",
      "present_bytes",
      "present_lines",
      "present_cells",
      "damage_rows",
      "damage_range_rows",
      "damage_spans",
      "damage_cells",
      "damage_graphics",
      "damage_full_text",
      "damage_full_graphics",
      "present_sync",
      "present_graphics_scope",
      "present_graphics_attachments",
      "present_edit_op",
      "present_edit_ops",
      "cache_hit",
      "total_ms",
    ]
    writeLine(headers.joined(separator: "\t"))
  }

  private func writeLine(_ line: String) {
    #if !canImport(WASILibc)
      var data = line + "\n"
      data.withUTF8 { buffer in
        _ = unsafe write(fileDescriptor, buffer.baseAddress, buffer.count)
      }
    #endif
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

  private func formatGeneration(_ generation: RenderGeneration?) -> String {
    generation.map { String($0.rawValue) } ?? "-"
  }
}
