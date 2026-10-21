import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

#if canImport(Darwin)
  import Darwin
#endif

@MainActor
@Suite(.serialized)
struct BodyChangeCostTests {
  @Test(
    "counter and retained list diagnostic cost and neutrality",
    .enabled(if: ProcessInfo.processInfo.environment["SWIFTTUI_BODY_CHANGE_BENCH"] == "1"))
  func cost() throws {
    for rows in [1, 1_000] {
      var reference: [(Int, Int)] = []
      var bodyCount = 0
      for enabled in [false, true] {
        let probe = BodyCostProbe()
        let renderer = DefaultRenderer()
        let root = testIdentity("BodyCost")
        var samples: [Double] = []
        var work: [(Int, Int)] = []
        var memoryStart = (bytes: UInt64(0), blocks: UInt64(0))
        BodyChangeOutput.$sink.withValue(
          .init { record, format in
            probe.encodedBytes += record.formatted(format).utf8.count
          }
        ) {
          for tick in 0..<60 {
            if tick == 10 { memoryStart = heap() }
            if tick > 0, rows == 1 { probe.binding?.wrappedValue += 1 }
            let result = renderer.render(
              BodyCostRoot(probe: probe, rows: rows, tick: tick, enabled: enabled),
              context: .init(identity: root, invalidatedIdentities: tick == 0 ? [] : [root]),
              proposal: .init(width: .finite(80), height: .finite(30)))
            if tick >= 10 {
              let duration = result.diagnostics.timing.phaseTimings!.resolve.components
              samples.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
              work.append(
                (
                  result.diagnostics.work.resolvedNodesComputed,
                  result.diagnostics.work.resolvedNodesReused
                ))
            }
          }
        }
        let memoryEnd = heap()
        if enabled {
          #expect(work.elementsEqual(reference, by: { $0 == $1 }))
          #expect(probe.bodies == bodyCount)
        } else {
          reference = work
          bodyCount = probe.bodies
        }
        #if DEBUG
          let tracked = renderer.viewGraph.debugBodyChanges.snapshot.histories.count
          #expect(tracked <= BodyChangeTracker.maximumBodies)
          #expect(
            renderer.viewGraph.debugBodyChanges.snapshot.pending.count
              <= BodyChangeTracker.maximumOwners)
        #else
          let tracked = 0
          #expect(probe.encodedBytes == 0)
        #endif
        let sorted = samples.sorted()
        let record: [String: Any] = [
          "rows": rows, "enabled": enabled, "samples": samples.count,
          "resolve_median_ms": sorted[sorted.count / 2],
          "resolve_p95_ms": sorted[sorted.count * 95 / 100],
          "body_calls": probe.bodies, "tracked_bodies": tracked,
          "encoded_bytes": probe.encodedBytes,
          "computed_per_frame": work.first!.0, "reused_per_frame": work.first!.1,
          "process_heap_delta_bytes": Int64(memoryEnd.bytes) - Int64(memoryStart.bytes),
          "process_heap_delta_blocks": Int64(memoryEnd.blocks) - Int64(memoryStart.blocks),
        ]
        print(
          "BODY_CHANGE_COST "
            + String(
              decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              as: UTF8.self))
      }
    }
  }

  private func heap() -> (bytes: UInt64, blocks: UInt64) {
    #if canImport(Darwin)
      var stats = malloc_statistics_t()
      unsafe malloc_zone_statistics(nil, &stats)
      return (UInt64(stats.size_in_use), UInt64(stats.blocks_in_use))
    #else
      return (0, 0)
    #endif
  }
}

@MainActor private final class BodyCostProbe {
  var bodies = 0
  var encodedBytes = 0
  var binding: Binding<Int>?
}
private struct BodyCostRoot: View {
  let probe: BodyCostProbe
  let rows: Int
  let tick: Int
  let enabled: Bool
  var body: some View {
    let _ = enabled ? Self._printChanges() : ()
    VStack {
      Text("tick \(tick)")
      ForEach(0..<rows) { index in BodyCostRow(probe: probe, index: index, enabled: enabled) }
    }
  }
}
private struct BodyCostRow: View, Equatable {
  let probe: BodyCostProbe
  let index: Int
  let enabled: Bool
  @State private var count = 0
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.index == rhs.index }
  var body: some View {
    if enabled {
      Self._printChanges()
      Self._logChanges()
    }
    probe.bodies += 1
    if index == 0 { probe.binding = $count }
    return Text("row \(index) count \(count)")
  }
}
