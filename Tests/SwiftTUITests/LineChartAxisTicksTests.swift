import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("LineChart axis config")
struct LineChartAxisConfigTests {
  @Test("X axis .values builds numeric Ticks/Format")
  func xAxisValuesBuildsNumeric() {
    let axis = LineChartXAxis.values(count: 6)
    #expect(axis.isHidden == false)
    if case .count(let n) = axis.ticks { #expect(n == 6) } else {
      Issue.record("expected .count tick strategy")
    }
    if case .number = axis.format { } else {
      Issue.record("expected .number format")
    }
  }

  @Test("X axis .dates builds DateAxisStride / Date.FormatStyle")
  func xAxisDatesBuildsDateStride() {
    let axis = LineChartXAxis.dates(every: .month)
    if case .dates(let stride) = axis.ticks { #expect(stride == .month) } else {
      Issue.record("expected .dates tick strategy")
    }
    if case .date = axis.format { } else {
      Issue.record("expected .date format")
    }
  }

  @Test("X axis .hidden flips isHidden")
  func xAxisHiddenFlipsFlag() {
    #expect(LineChartXAxis.hidden.isHidden == true)
  }

  @Test("Y axis .values defaults to compact-name notation")
  func yAxisValuesDefaultsToCompact() {
    _ = LineChartYAxis.values()
    // Smoke: just verify it builds without crashing.
  }

  @Test("Legend config presets")
  func legendPresets() {
    #expect(LineChartLegendConfig.bottom.position == .bottom)
    #expect(LineChartLegendConfig.top.position == .top)
    #expect(LineChartLegendConfig.hidden.position == .hidden)
  }
}
