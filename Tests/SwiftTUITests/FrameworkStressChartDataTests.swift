import Foundation
import Testing

@testable import SwiftTUICharts
@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI chart and live-data stress behavior", .serialized)
struct FrameworkStressChartDataTests {}

@MainActor
private func chartDataExercise<Root: View>(
  attempt: String,
  generations: ClosedRange<Int> = 0...16,
  proposal: ProposedSize = .init(width: 64, height: 16),
  makeRoot: (Int) -> Root,
  verify: (Int, RenderSnapshot) -> Void
) {
  let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
  let identity = testIdentity("ChartData", attempt)

  for generation in generations {
    let root = makeRoot(generation)
    let retained = renderer.render(
      root,
      context: .init(
        identity: identity,
        invalidatedIdentities: generation == generations.lowerBound ? [] : [identity]
      ),
      proposal: proposal
    )
    let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
      root,
      context: .init(identity: identity),
      proposal: proposal
    )

    #expect(
      retained.rasterSurface == fresh.rasterSurface,
      "retained raster diverged in chart attempt \(attempt), generation \(generation)"
    )
    #expect(
      retained.semanticSnapshot == fresh.semanticSnapshot,
      "retained semantics diverged in chart attempt \(attempt), generation \(generation)"
    )
    verify(generation, retained)
  }
}

private func chartDataText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

private func chartDataAccessibilityLabels(_ snapshot: RenderSnapshot) -> [String] {
  snapshot.semanticSnapshot.accessibilityNodes.compactMap(\.label)
}

// MARK: - Attempt 001: bar data reorder and live extrema

extension FrameworkStressChartDataTests {
  @Test("stress chart data 001 bar rows retarget after reorder and extrema replacement")
  func chartData001BarRowsRetargetAfterReorderAndExtremaReplacement() {
    // Hypothesis: BarChart's index-keyed rows can retain an earlier entry's
    // label or normalized width when order and the maximum owner change together.
    struct Root: View {
      let generation: Int

      var body: some View {
        let entries = [
          BarChartEntry("A\(generation)", value: Double(generation + 1), tone: .success),
          BarChartEntry("B\(generation)", value: Double(30 - generation), tone: .warning),
          BarChartEntry("C\(generation)", value: Double((generation * 7) % 19), tone: .info),
        ]
        BarChart(
          "Bars \(generation)",
          entries: generation.isMultiple(of: 2) ? entries : Array(entries.reversed()),
          barWidth: 15,
          labelWidth: 6
        )
      }
    }

    chartDataExercise(attempt: "001", proposal: .init(width: 48, height: 8)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Bars \(generation)"))
      #expect(text.contains("A\(generation)"))
      #expect(text.contains("B\(generation)"))
      #expect(
        chartDataAccessibilityLabels(snapshot).contains { $0.contains("Bars \(generation):") })
    }
  }
}
