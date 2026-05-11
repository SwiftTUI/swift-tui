import Foundation
import SwiftTUICore
import SwiftTUIViews

/// A multi-series continuous plot supporting `.line`, `.area`, and
/// `.step` series styles, with Date- or numeric-aware axis modifiers.
public struct LineChart<Label: View, Summary: View>: PrimitiveView, ResolvableView {
  public var series: [LineChartSeries]
  public var height: Int
  public var width: Int?
  public var xAxis: LineChartXAxis
  public var yAxis: LineChartYAxis
  public var legend: LineChartLegendConfig
  public var baseline: LineChartBaseline

  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    series: [LineChartSeries],
    height: Int = 8,
    width: Int? = nil,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      series: series,
      height: height,
      width: width,
      xAxis: .automatic,
      yAxis: .automatic,
      legend: .bottom,
      baseline: .auto,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    series: [LineChartSeries],
    height: Int,
    width: Int?,
    xAxis: LineChartXAxis,
    yAxis: LineChartYAxis,
    legend: LineChartLegendConfig,
    baseline: LineChartBaseline,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.series = series
    self.height = height
    self.width = width
    self.xAxis = xAxis
    self.yAxis = yAxis
    self.legend = legend
    self.baseline = baseline
    self.accessibilitySummary = accessibilitySummary
    self.label = label()
    self.summary = summary()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let effectiveWidth = max(20, width ?? 60)   // assume an 80-col terminal minus padding
    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          lineChartBody(
            series: series,
            height: height,
            width: effectiveWidth,
            xAxis: xAxis,
            yAxis: yAxis,
            legend: legend,
            baseline: baseline
          )
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "LineChart",
            label: accessibilitySummary
          )
        ),
        in: context
      )
    ]
  }
}

// MARK: - Modifiers

extension LineChart {
  public func chartXAxis(_ axis: LineChartXAxis) -> Self {
    var copy = self; copy.xAxis = axis; return copy
  }
  public func chartYAxis(_ axis: LineChartYAxis) -> Self {
    var copy = self; copy.yAxis = axis; return copy
  }
  public func chartLegend(_ config: LineChartLegendConfig) -> Self {
    var copy = self; copy.legend = config; return copy
  }
  public func chartBaseline(_ baseline: LineChartBaseline) -> Self {
    var copy = self; copy.baseline = baseline; return copy
  }
}

// MARK: - Convenience inits

extension LineChart where Label == EmptyView, Summary == Text {
  public init(
    series: [LineChartSeries],
    height: Int = 8,
    width: Int? = nil
  ) {
    let summary = "\(series.count) series"
    self.init(
      series: series,
      height: height,
      width: width,
      xAxis: .automatic,
      yAxis: .automatic,
      legend: .bottom,
      baseline: .auto,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension LineChart where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    series: [LineChartSeries],
    height: Int = 8,
    width: Int? = nil
  ) {
    let title = String(title)
    let summary = "\(series.count) series"
    self.init(
      series: series,
      height: height,
      width: width,
      xAxis: .automatic,
      yAxis: .automatic,
      legend: .bottom,
      baseline: .auto,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
