import Observation
@_spi(Runners) import SwiftTUI

/// D70 A/B: incremental raster compute must scale with damage *size*, not
/// damage *spread*.
///
/// The shape is the pathological one for hull-based culling: a one-cell counter
/// pinned to the **top** row and another pinned to the **bottom** row, with a
/// full screen of gradient-styled static text between them. One click bumps
/// both counters, so the exact per-frame damage is `{0, rows - 1}` while the
/// convex hull of that damage is the entire screen.
///
/// Before the span cull, every incremental frame walked the whole hull: the
/// static body re-ran `layoutText` and the per-cluster `resolveTextStyle` loop
/// — including the gradient sampling the body's `foregroundStyle` forces — and
/// only the exact-set clamp in `write` stopped the cells from landing. All that
/// compute produced two changed cells. With `DirtyRowSpans` the body's subtree
/// misses the exact set and is skipped before any of it runs.
///
/// Metric: `worker_raster_compute_ms` (and total CPU per committed frame).
/// A/B: HEAD vs the span-culling change. The gradient style is deliberate — it
/// makes the avoided per-cluster work large enough to read above frame noise.
///
/// **Was dormant; live since 2026-07-30.** For the whole of this lane's
/// existence it reported *no* difference across the span-cull A/B, because the
/// runtime never reached the incremental rasterizer at all: every frame of
/// every scenario barriered out of damage production, so
/// `FrameTailPresentationDamageResolver` returned `damage: nil` and the tail
/// took the fresh-raster path. Two things were wrong — `placedPath` climbed the
/// purely lexical `Identity.parent` chain and so ran off the top of any real
/// app's placed tree, and the damage model itself keyed on the subtree extents
/// of `directlyInvalidated`, which is the invalidation *seed* set rather than
/// the set of identities whose painted output changed. Damage is now derived by
/// diffing the previous committed draw tree against the current one.
///
/// Measured on this lane the day that landed (release, `--iterations 1`,
/// 80x40, 36 body rows), `worker_raster_compute_ms` p50:
///
/// | | before | after |
/// | --- | --- | --- |
/// | `synthetic-disjoint-damage` | 6.29 ms | **0.57 ms** |
/// | `synthetic-narrow-invalidation` | 1.08 ms | **0.54 ms** |
///
/// with 16 of 17 committed frames rasterizing incrementally (the one exception
/// is the first frame, which has no previous surface) and zero frames repaired
/// by the F13 verification oracle. `summary.json` reports
/// `incremental_raster_frame_count`, `repaired_incremental_raster_frame_count`,
/// and `raster_reuse_barrier_counts` so this lane can never silently go dormant
/// again.
///
/// The static-body row count follows the terminal, but
/// `SWIFTTUI_PERF_DISJOINT_DAMAGE_BODY_ROWS` overrides it to sweep the spread
/// independently of the damage size, which is the actual claim under test.
public struct SyntheticDisjointDamageScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticDisjointDamage
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 40)
  public let scriptedEvents = [
    "click bump; change only the top and bottom rows of a full-screen static body"
  ]
  public let visualMarkers = ["top 0"]
  public let settlingDescription = "first frame that shows top 0"

  private static let defaultBodyRowCount = 36
  private static let clickCount = 8

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let bodyRowCount = Self.resolvedBodyRowCount()
    let model = PerfDisjointDamageModel()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfDisjointDamageProbeView(model: model, bodyRowCount: bodyRowCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "top 0")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      for click in 1...Self.clickCount {
        let cell = try driver.cell(containing: "bump")
        driver.sendClick(at: cell)
        let matching = try await driver.waitForFrame(
          containing: "bottom \(click)",
          afterFrame: lastFrame
        )
        lastFrame = matching.frameNumber
      }
      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "synthetic-disjoint-damage",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "bottom \(Self.clickCount)",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  private static func resolvedBodyRowCount() -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_DISJOINT_DAMAGE_BODY_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultBodyRowCount
    }
    return parsed
  }
}

/// The tick must be read by two *separate* leaf views, not by a common
/// ancestor.
///
/// Damage production keys on the **subtree extent of each directly-invalidated
/// identity** (`FrameTailPresentationDamageResolver`). A `@State` hoisted above
/// both counters invalidates that ancestor, whose subtree spans the whole
/// screen — one screen-wide damage region with no clean gap, and nothing for
/// any cull to skip. Observing the same value from two independent leaves makes
/// the invalidation set `{topRow, bottomRow}`, whose extents are one row each.
@Observable
private final class PerfDisjointDamageModel {
  var tick = 0
}

private struct PerfDisjointDamageProbeView: View {
  let model: PerfDisjointDamageModel
  let bodyRowCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DisjointDamageEdgeRow(model: model, label: "top")
      // The static body between the two damaged rows. Gradient-styled so each
      // cluster costs a colour sample, which is exactly the compute the span
      // cull is meant to skip. It reads nothing from the model, so it is never
      // invalidated and never enters the exact dirty set.
      Text(Self.bodyText(rowCount: bodyRowCount))
        .foregroundStyle(
          LinearGradient(
            colors: [.blue, .white, .red],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      DisjointDamageEdgeRow(model: model, label: "bottom")
      Button("bump") {
        model.tick += 1
      }
    }
  }

  private static func bodyText(rowCount: Int) -> String {
    let line = String(repeating: "disjoint ", count: 8)
    return Array(repeating: line, count: max(1, rowCount)).joined(separator: "\n")
  }
}

/// A one-row leaf whose only dependency is `model.tick`, so its invalidation
/// damages exactly its own row.
private struct DisjointDamageEdgeRow: View {
  let model: PerfDisjointDamageModel
  let label: String

  var body: some View {
    Text("\(label) \(model.tick)")
  }
}
