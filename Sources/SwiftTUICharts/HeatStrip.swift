import SwiftTUICore
import SwiftTUIViews

/// A compact strip of heat-style cells for relative intensity data.
public struct HeatStrip<Label: View, Summary: View>: PrimitiveView, ResolvableView {
  public var entries: [BarChartEntry]
  public var cellWidth: Int
  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    entries: [BarChartEntry],
    cellWidth: Int = 2,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      entries: entries,
      cellWidth: cellWidth,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    entries: [BarChartEntry],
    cellWidth: Int,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.cellWidth = cellWidth
    self.label = label()
    self.summary = summary()
    self.accessibilitySummary = accessibilitySummary
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let maximumValue = max(1, entries.map { abs($0.value) }.max() ?? 1)

    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          heatStripBody(
            entries: entries,
            maximumValue: maximumValue,
            cellWidth: cellWidth
          )
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "HeatStrip",
            label: accessibilitySummary
          )
        ),
        in: context
      )
    ]
  }
}

extension HeatStrip where Label == EmptyView, Summary == Text {
  public init(
    entries: [BarChartEntry],
    cellWidth: Int = 2
  ) {
    let summary = heatStripSummaryText(entries)
    self.init(
      entries: entries,
      cellWidth: cellWidth,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension HeatStrip where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    cellWidth: Int = 2
  ) {
    let title = String(title)
    let summary = heatStripSummaryText(entries)
    self.init(
      entries: entries,
      cellWidth: cellWidth,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
