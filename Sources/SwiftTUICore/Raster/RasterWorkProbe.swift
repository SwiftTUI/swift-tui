import Synchronization

/// Per-paint raster work tallies (plan 2026-09-24-001 §4A/§4C, STUI-618).
///
/// These separate *less work* from *faster work*: an output-correct fill that
/// still samples every cell of its rectangle reports the same `radialSamples`
/// as the reference walk, however fast each sample became.
package struct RasterWorkCounters: Equatable, Sendable {
  /// Fill commands that reached the cell walk.
  package var fills = 0
  /// Cells the walk considered (the geometry test ran for each).
  package var visitedCells = 0
  /// Radial-gradient samples computed.
  package var radialSamples = 0
  /// Samples whose alpha was zero and therefore wrote nothing.
  package var zeroAlphaSkips = 0
  /// Cell writes issued under a blend mode.
  package var blendedWrites = 0
  /// Rows the support walk derived spans for.
  package var spanRows = 0
  /// Rows the support walk skipped outright (outside the outer radius or the
  /// dirty set).
  package var skippedRows = 0
  /// Whole fills culled before any row was visited.
  package var culledLayers = 0

  package init() {}

  package static func += (lhs: inout RasterWorkCounters, rhs: RasterWorkCounters) {
    lhs.fills += rhs.fills
    lhs.visitedCells += rhs.visitedCells
    lhs.radialSamples += rhs.radialSamples
    lhs.zeroAlphaSkips += rhs.zeroAlphaSkips
    lhs.blendedWrites += rhs.blendedWrites
    lhs.spanRows += rhs.spanRows
    lhs.skippedRows += rhs.skippedRows
    lhs.culledLayers += rhs.culledLayers
  }
}

/// An opt-in accumulator for ``RasterWorkCounters``.
///
/// The rasterizer may run on the frame-tail worker, so a fill tallies into a
/// local value and flushes it once, under the probe's lock, at the end of the
/// fill. A disarmed run touches nothing but one task-local read and one flag
/// read per fill.
///
/// Two ways to arm it:
/// - Bind ``Rasterizer/workProbe`` for a scope (tests; isolated per task).
/// - Arm ``RasterWorkProbe/shared`` process-wide (a diagnostic run).
package final class RasterWorkProbe: Sendable {
  package static let shared = RasterWorkProbe()
  private static let sharedArmed = Mutex(false)
  private let counters = Mutex(RasterWorkCounters())

  package init() {}

  /// Arms or disarms the process-wide probe. Disarming does not reset it.
  package static func setSharedArmed(_ armed: Bool) {
    sharedArmed.withLock { $0 = armed }
  }

  package static var isSharedArmed: Bool {
    sharedArmed.withLock { $0 }
  }

  package func snapshot() -> RasterWorkCounters {
    counters.withLock { $0 }
  }

  package func reset() {
    counters.withLock { $0 = RasterWorkCounters() }
  }

  package func record(_ work: RasterWorkCounters) {
    counters.withLock { $0 += work }
  }

  /// The probe a fill should flush into, or `nil` when none is armed.
  static func active() -> RasterWorkProbe? {
    if let bound = Rasterizer.workProbe {
      return bound
    }
    return isSharedArmed ? shared : nil
  }
}

extension Rasterizer {
  /// A task-scoped work probe. Bound by tests around a rasterization so
  /// parallel suites cannot see each other's tallies.
  @TaskLocal package static var workProbe: RasterWorkProbe?

  /// Forces the reference radial fill walk: every cell of the fill rectangle
  /// is visited and sampled through the unprepared gradient, exactly as before
  /// the prepared sampler and support walk existed. The equivalence tests
  /// render each scene both ways and require identical surfaces and
  /// presentation records.
  @TaskLocal package static var forceReferenceRadialWalk = false
}
