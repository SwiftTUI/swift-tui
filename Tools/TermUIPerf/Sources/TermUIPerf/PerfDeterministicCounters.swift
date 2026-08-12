import Foundation

/// Per-frame deterministic work counters parsed from `frames.tsv` (plan
/// 2026-08-11-005 Stage 0).
///
/// Every field is optional because absence is information: an artifact
/// recorded before a column existed must reduce to "not recorded", never to a
/// fabricated zero — the same rule `realized_rows` established. The
/// `resolved_computed`/`resolved_reused`/`measured_computed` columns are
/// written as `computed/total` fractions; only the numerator is a work count,
/// so only the numerator is parsed.
public struct PerfFrameWorkCounters: Equatable, Sendable {
  public var resolvedComputed: Int?
  public var resolvedReused: Int?
  public var measuredComputed: Int?
  public var drawNodes: Int?
  public var builtinContainerMeasures: Int?
  public var builtinChildMeasureRequests: Int?
  public var builtinChildMeasureRequestsProbe: Int?
  public var customContainerMeasures: Int?
  public var customChildMeasureRequests: Int?
  public var customChildMeasureRequestsProbe: Int?
  public var customPlacementChildMeasureRequests: Int?

  public init(
    resolvedComputed: Int? = nil,
    resolvedReused: Int? = nil,
    measuredComputed: Int? = nil,
    drawNodes: Int? = nil,
    builtinContainerMeasures: Int? = nil,
    builtinChildMeasureRequests: Int? = nil,
    builtinChildMeasureRequestsProbe: Int? = nil,
    customContainerMeasures: Int? = nil,
    customChildMeasureRequests: Int? = nil,
    customChildMeasureRequestsProbe: Int? = nil,
    customPlacementChildMeasureRequests: Int? = nil
  ) {
    self.resolvedComputed = resolvedComputed
    self.resolvedReused = resolvedReused
    self.measuredComputed = measuredComputed
    self.drawNodes = drawNodes
    self.builtinContainerMeasures = builtinContainerMeasures
    self.builtinChildMeasureRequests = builtinChildMeasureRequests
    self.builtinChildMeasureRequestsProbe = builtinChildMeasureRequestsProbe
    self.customContainerMeasures = customContainerMeasures
    self.customChildMeasureRequests = customChildMeasureRequests
    self.customChildMeasureRequestsProbe = customChildMeasureRequestsProbe
    self.customPlacementChildMeasureRequests = customPlacementChildMeasureRequests
  }
}

/// Run-total deterministic work counters (plan 2026-08-11-005 D4): the
/// regression currency that can hard-gate across machines, unlike any
/// wall-clock number. Summed over **every** diagnostic frame — dropped and
/// cancelled frames did their resolve/measure work before being discarded, so
/// a work census that skipped them would under-count exactly the frames a
/// scheduling regression adds.
///
/// Counter names in `orderedEntries` are the `frames.tsv` column names, so a
/// baseline entry, a compare line, and a raw trace row all speak one
/// vocabulary.
public struct PerfDeterministicCounters: Codable, Equatable, Sendable {
  /// Committed frames in the run — the frame census closed-loop drives pin
  /// (one per awaited input).
  public var committedFrames: Int
  /// Input events answered across all frames.
  public var answeredInputs: Int
  public var resolvedComputed: Int?
  public var resolvedReused: Int?
  public var measuredComputed: Int?
  public var drawNodes: Int?
  /// UTF-8 bytes presented. Meaningful as a wire number only when the
  /// emission lane was armed; the in-process host's byte count is still
  /// deterministic and still ratchets. `nil` in the cold lane — the one-shot
  /// path has no presentation writer, so there are no bytes to miscount.
  public var presentBytes: Int?
  /// Cells presented (warm) or non-empty cells the raster produced (cold) —
  /// both are the "rasterized cells" census of D4, each lane's honest form.
  public var presentCells: Int?
  /// Damaged text cells over frames that reported a bounded count; `nil`
  /// when no frame carried the column.
  public var damageCells: Int?
  /// Damage rows summed over bounded frames only. Full-surface repaints are
  /// counted in `fullRepaintFrames` instead of being folded in as zero.
  public var boundedDamageRows: Int?
  public var fullRepaintFrames: Int
  /// Collection-probe totals; `nil` when the probes were disarmed.
  public var realizedRows: Int?
  public var listLayoutDerivations: Int?
  public var builtinContainerMeasures: Int?
  public var builtinChildMeasureRequests: Int?
  public var builtinChildMeasureRequestsProbe: Int?
  public var customContainerMeasures: Int?
  public var customChildMeasureRequests: Int?
  public var customChildMeasureRequestsProbe: Int?
  public var customPlacementChildMeasureRequests: Int?

  public init(
    committedFrames: Int = 0,
    answeredInputs: Int = 0,
    resolvedComputed: Int? = nil,
    resolvedReused: Int? = nil,
    measuredComputed: Int? = nil,
    drawNodes: Int? = nil,
    presentBytes: Int? = nil,
    presentCells: Int? = nil,
    damageCells: Int? = nil,
    boundedDamageRows: Int? = nil,
    fullRepaintFrames: Int = 0,
    realizedRows: Int? = nil,
    listLayoutDerivations: Int? = nil,
    builtinContainerMeasures: Int? = nil,
    builtinChildMeasureRequests: Int? = nil,
    builtinChildMeasureRequestsProbe: Int? = nil,
    customContainerMeasures: Int? = nil,
    customChildMeasureRequests: Int? = nil,
    customChildMeasureRequestsProbe: Int? = nil,
    customPlacementChildMeasureRequests: Int? = nil
  ) {
    self.committedFrames = committedFrames
    self.answeredInputs = answeredInputs
    self.resolvedComputed = resolvedComputed
    self.resolvedReused = resolvedReused
    self.measuredComputed = measuredComputed
    self.drawNodes = drawNodes
    self.presentBytes = presentBytes
    self.presentCells = presentCells
    self.damageCells = damageCells
    self.boundedDamageRows = boundedDamageRows
    self.fullRepaintFrames = fullRepaintFrames
    self.realizedRows = realizedRows
    self.listLayoutDerivations = listLayoutDerivations
    self.builtinContainerMeasures = builtinContainerMeasures
    self.builtinChildMeasureRequests = builtinChildMeasureRequests
    self.builtinChildMeasureRequestsProbe = builtinChildMeasureRequestsProbe
    self.customContainerMeasures = customContainerMeasures
    self.customChildMeasureRequests = customChildMeasureRequests
    self.customChildMeasureRequestsProbe = customChildMeasureRequestsProbe
    self.customPlacementChildMeasureRequests = customPlacementChildMeasureRequests
  }

  private enum CodingKeys: String, CodingKey {
    case committedFrames = "committed_frames"
    case answeredInputs = "answered_inputs"
    case resolvedComputed = "resolved_computed"
    case resolvedReused = "resolved_reused"
    case measuredComputed = "measured_computed"
    case drawNodes = "draw_nodes"
    case presentBytes = "present_bytes"
    case presentCells = "present_cells"
    case damageCells = "damage_cells"
    case boundedDamageRows = "bounded_damage_rows"
    case fullRepaintFrames = "full_repaint_frames"
    case realizedRows = "realized_rows"
    case listLayoutDerivations = "list_layout_derivations"
    case builtinContainerMeasures = "builtin_container_measures"
    case builtinChildMeasureRequests = "builtin_child_measure_requests"
    case builtinChildMeasureRequestsProbe = "builtin_child_measure_requests_probe"
    case customContainerMeasures = "custom_container_measures"
    case customChildMeasureRequests = "custom_child_measure_requests"
    case customChildMeasureRequestsProbe = "custom_child_measure_requests_probe"
    case customPlacementChildMeasureRequests = "custom_placement_child_measure_requests"
  }
}

extension PerfDeterministicCounters {
  /// Sums the parsed per-frame counters into run totals.
  ///
  /// An optional counter's total is `nil` only when NO frame carried the
  /// column — one frame reporting it is a recorded (partial) measurement,
  /// and partiality in a deterministic run is itself a drift signal the
  /// ratchet should see rather than have hidden.
  public static func reduce(
    frames: [PerfFrameRecord],
    committedFrameCount: Int
  ) -> PerfDeterministicCounters {
    PerfDeterministicCounters(
      committedFrames: committedFrameCount,
      answeredInputs: frames.reduce(0) { $0 + $1.answeredInputCount },
      resolvedComputed: sumIfAnyPresent(frames, \.workCounters.resolvedComputed),
      resolvedReused: sumIfAnyPresent(frames, \.workCounters.resolvedReused),
      measuredComputed: sumIfAnyPresent(frames, \.workCounters.measuredComputed),
      drawNodes: sumIfAnyPresent(frames, \.workCounters.drawNodes),
      presentBytes: frames.reduce(0) { $0 + $1.emission.presentBytes },
      presentCells: frames.reduce(0) { $0 + $1.emission.presentCells },
      damageCells: sumIfAnyPresent(frames, \.emission.damageCells),
      boundedDamageRows: sumIfAnyPresent(frames, \.emission.damageRows.count),
      fullRepaintFrames: frames.count { $0.emission.damageRows.isFullRepaint },
      realizedRows: sumIfAnyPresent(frames, \.realizedRows),
      listLayoutDerivations: sumIfAnyPresent(frames, \.listLayoutDerivations),
      builtinContainerMeasures: sumIfAnyPresent(
        frames, \.workCounters.builtinContainerMeasures),
      builtinChildMeasureRequests: sumIfAnyPresent(
        frames, \.workCounters.builtinChildMeasureRequests),
      builtinChildMeasureRequestsProbe: sumIfAnyPresent(
        frames, \.workCounters.builtinChildMeasureRequestsProbe),
      customContainerMeasures: sumIfAnyPresent(
        frames, \.workCounters.customContainerMeasures),
      customChildMeasureRequests: sumIfAnyPresent(
        frames, \.workCounters.customChildMeasureRequests),
      customChildMeasureRequestsProbe: sumIfAnyPresent(
        frames, \.workCounters.customChildMeasureRequestsProbe),
      customPlacementChildMeasureRequests: sumIfAnyPresent(
        frames, \.workCounters.customPlacementChildMeasureRequests)
    )
  }

  /// The recorded counters as `(column name, total)` pairs in declaration
  /// order. Absent optionals are omitted, so a consumer (aggregate reducer,
  /// compare printer, the Stage-3 ratchet) never invents a zero for a
  /// counter this run did not measure.
  public var orderedEntries: [(name: String, value: Int)] {
    var entries: [(String, Int)] = [
      ("committed_frames", committedFrames),
      ("answered_inputs", answeredInputs),
    ]
    func append(_ name: String, _ value: Int?) {
      if let value {
        entries.append((name, value))
      }
    }
    append("resolved_computed", resolvedComputed)
    append("resolved_reused", resolvedReused)
    append("measured_computed", measuredComputed)
    append("draw_nodes", drawNodes)
    append("present_bytes", presentBytes)
    append("present_cells", presentCells)
    append("damage_cells", damageCells)
    append("bounded_damage_rows", boundedDamageRows)
    entries.append(("full_repaint_frames", fullRepaintFrames))
    append("realized_rows", realizedRows)
    append("list_layout_derivations", listLayoutDerivations)
    append("builtin_container_measures", builtinContainerMeasures)
    append("builtin_child_measure_requests", builtinChildMeasureRequests)
    append("builtin_child_measure_requests_probe", builtinChildMeasureRequestsProbe)
    append("custom_container_measures", customContainerMeasures)
    append("custom_child_measure_requests", customChildMeasureRequests)
    append("custom_child_measure_requests_probe", customChildMeasureRequestsProbe)
    append("custom_placement_child_measure_requests", customPlacementChildMeasureRequests)
    return entries
  }

  /// The recorded counters keyed by column name.
  public var valuesByName: [String: Int] {
    Dictionary(uniqueKeysWithValues: orderedEntries)
  }

  private static func sumIfAnyPresent(
    _ frames: [PerfFrameRecord],
    _ value: (PerfFrameRecord) -> Int?
  ) -> Int? {
    let present = frames.compactMap(value)
    guard !present.isEmpty else {
      return nil
    }
    return present.reduce(0, +)
  }
}
