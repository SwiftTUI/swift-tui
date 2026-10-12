import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Opt-in release probe for the cost of retaining styled collection layouts.
/// Reports complete synchronous renderer time, measure time, and work counters;
/// timings are evidence, not machine-dependent pass/fail thresholds.
/// These snapshots use the default focus environment: table selection changes
/// update layout inputs while selection chrome remains hidden when unfocused.
///
/// SWIFTTUI_COLLECTION_MEASURE_BENCH=1 swiftly run swift test -c release \
///   -Xswiftc -enable-testing --filter CollectionMeasurementBenchmarkTests
@MainActor
@Suite(.serialized)
struct CollectionMeasurementBenchmarkTests {
  @Test(
    "collection selection and paint invalidation",
    .enabled(if: ProcessInfo.processInfo.environment["SWIFTTUI_COLLECTION_MEASURE_BENCH"] == "1")
  )
  func invalidationCost() throws {
    let samples = max(
      2, Int(ProcessInfo.processInfo.environment["SWIFTTUI_COLLECTION_BENCH_SAMPLES"] ?? "") ?? 40)
    for rowCount in [100, 1_000] {
      for kind in CollectionMeasurementKind.allCases {
        for change in ["idle", "selection", "paint"] {
          let renderer = DefaultRenderer()
          let context = ResolveContext(
            identity: testIdentity("CollectionMeasurement", kind.rawValue))
          let proposal = ProposedSize(width: .finite(80), height: .finite(28))
          var elapsed: [Double] = []
          var measure: [Double] = []
          var computed = 0
          var reused = 0
          var outputMismatches = 0
          let clock = ContinuousClock()
          // Reference surfaces are computed outside the timed loop. An unsafe
          // cache-relaxation experiment must not masquerade as a valid speedup.
          let references = (0..<2).map { phase in
            DefaultRenderer().render(
              CollectionMeasurementView(
                kind: kind, rowCount: rowCount,
                selection: change == "selection" ? 2 + phase : 2,
                paint: change == "paint" && phase == 1),
              context: context, proposal: proposal
            ).rasterSurface
          }
          let changesPaint =
            change == "paint"
            || (change == "selection" && (kind == .indexedList || kind == .builderList))
          if changesPaint {
            #expect(references[0] != references[1], "the stimulus must change visible output")
          }
          for tick in 0..<(samples + 10) {
            let phase = tick % 2
            let view = CollectionMeasurementView(
              kind: kind, rowCount: rowCount,
              selection: change == "selection" ? 2 + phase : 2,
              paint: change == "paint" && phase == 1)
            let start = clock.now
            let result = renderer.render(view, context: context, proposal: proposal)
            let duration = start.duration(to: clock.now)
            guard tick >= 10 else { continue }
            elapsed.append(milliseconds(duration))
            measure.append(
              milliseconds(try #require(result.diagnostics.timing.phaseTimings).measure))
            computed += result.diagnostics.work.measuredNodesComputed
            reused += result.diagnostics.work.measuredNodesReused
            if result.rasterSurface != references[phase] { outputMismatches += 1 }
          }
          let sorted = elapsed.sorted()
          let record: [String: Any] = [
            "kind": kind.rawValue, "rows": rowCount, "change": change, "samples": samples,
            "frame_median_ms": sorted[sorted.count / 2],
            "frame_p95_ms": sorted[min(sorted.count - 1, sorted.count * 95 / 100)],
            "measure_median_ms": measure.sorted()[measure.count / 2],
            "computed_per_frame": Double(computed) / Double(samples),
            "reused_per_frame": Double(reused) / Double(samples),
            "output_mismatches": outputMismatches,
          ]
          let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
          print("COLLECTION_BENCH " + String(decoding: data, as: UTF8.self))
          // The opt-in diagnostic control records stale output instead of
          // failing; ordinary benchmark runs must remain visually correct.
          if ProcessInfo.processInfo.environment["SWIFTTUI_COLLECTION_BENCH_UNSAFE_CONTROL"] != "1"
          {
            #expect(outputMismatches == 0)
          }
        }
      }
    }
  }

  private func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
  }
}

private enum CollectionMeasurementKind: String, CaseIterable {
  case indexedList, builderList, indexedTable, builderTable
}

@MainActor
private struct CollectionMeasurementView: View {
  let kind: CollectionMeasurementKind
  let rowCount: Int
  let selection: Int
  let paint: Bool

  var body: some View {
    Group {
      switch kind {
      case .indexedList:
        List(0..<rowCount, id: \.self, selection: .constant(selection as Int?)) { row in
          Text("row \(row)").padding(.vertical, row % 3 == 0 ? 1 : 0)
        }
      case .builderList:
        List(selection: .constant(selection as Int?)) {
          ForEach(0..<rowCount, id: \.self) { row in
            Text("row \(row)").padding(.vertical, row % 3 == 0 ? 1 : 0).tag(row)
          }
        }
      case .indexedTable:
        Table(
          0..<rowCount, id: \.self, selection: .constant(selection as Int?),
          columns: [.init("Value", width: 24)]
        ) { row in
          Text("row \(row)").padding(.vertical, row % 3 == 0 ? 1 : 0)
        }
      case .builderTable:
        Table(selection: .constant(selection as Int?), columns: [.init("Value", width: 24)]) {
          ForEach(0..<rowCount, id: \.self) { row in
            TableRow {
              Text("row \(row)").padding(.vertical, row % 3 == 0 ? 1 : 0)
            }.tag(row)
          }
        }
      }
    }
    .foregroundStyle(paint ? Color.red : Color.green)
    .frame(height: 24)
  }
}
