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
    let axis = LineChartYAxis.values()
    if case .count(let n) = axis.ticks { #expect(n == 5) } else {
      Issue.record("expected .count tick strategy")
    }
    #expect(axis.isHidden == false)
    // FloatingPointFormatStyle is not Equatable, so we can't directly
    // compare against `.number.notation(.compactName)`. Verifying the
    // format produces compact notation on a large number is the next
    // best assertion of the documented default.
    let formatted = axis.format.format(1_000_000)
    #expect(formatted.contains("M") || formatted.contains("K"))
  }

  @Test("Legend config presets")
  func legendPresets() {
    #expect(LineChartLegendConfig.bottom.position == .bottom)
    #expect(LineChartLegendConfig.top.position == .top)
    #expect(LineChartLegendConfig.hidden.position == .hidden)
  }
}

@Suite("LineChart Y axis ticks")
struct LineChartYAxisTickTests {
  @Test("yAxisTickLabels with .count(N) yields N evenly spaced labels")
  func yAxisCountEvenSpacing() {
    let labels = yAxisTickLabels(
      domain: 0...100,
      ticks: .count(5),
      format: .number,
      plotHeight: 10
    )
    #expect(labels.count == 5)
    // First label at the top row, last at the bottom row.
    #expect(labels.first?.row == 0)
    #expect(labels.last?.row == 9)
  }

  @Test("yAxisTickLabels with .automatic falls back to 5 ticks")
  func yAxisAutomatic() {
    let labels = yAxisTickLabels(
      domain: 0...10,
      ticks: .automatic,
      format: .number,
      plotHeight: 8
    )
    #expect(labels.count == 5)
  }

  @Test("yAxisTickLabels formats values with the supplied FormatStyle")
  func yAxisFormat() {
    let labels = yAxisTickLabels(
      domain: 0...1_000_000,
      ticks: .count(2),
      format: .number.notation(.compactName),
      plotHeight: 5
    )
    #expect(labels[0].text.contains("M") || labels[0].text.contains("K"))
  }
}

@Suite("LineChart X axis ticks")
struct LineChartXAxisTickTests {
  @Test("xAxisTickLabels with .count(N) yields N evenly spaced labels")
  func xCountEvenSpacing() {
    let labels = xAxisTickLabels(
      domain: 0...100,
      ticks: .count(3),
      format: .number(.number),
      plotWidth: 20
    )
    #expect(labels.count == 3)
    #expect(labels.first?.col == 0)
    #expect(labels.last?.col == 19)
  }

  @Test("xAxisTickLabels with .dates(every: .month) snaps to month starts")
  func xDateStrideSnapsToMonth() {
    let cal = Calendar(identifier: .gregorian)
    var calUTC = cal
    calUTC.timeZone = TimeZone(identifier: "UTC")!
    // Range: 2024-01-15 ... 2024-04-15.
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    formatter.timeZone = TimeZone(identifier: "UTC")
    let start = formatter.date(from: "2024-01-15")!
    let end   = formatter.date(from: "2024-04-15")!
    let labels = xAxisTickLabels(
      domain: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
      ticks: .dates(every: .month),
      format: .date(.dateTime.month(.abbreviated)),
      plotWidth: 30,
      calendar: calUTC
    )
    // Expect ticks at Feb, Mar, Apr starts (within the range).
    let texts = labels.map(\.text)
    #expect(texts.contains("Feb"))
    #expect(texts.contains("Mar"))
    #expect(texts.contains("Apr"))
  }
}
