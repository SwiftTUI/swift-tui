import SwiftTUI
import SwiftTUICharts

/// Thin chrome wrapping every gitviz subcommand's output: a title, an
/// optional subtitle, the chart, and an optional footer.
struct ChartCard<Body: View>: View {
  let title: String
  let subtitle: String?
  let footer: String?
  let chart: Body

  init(
    title: String,
    subtitle: String? = nil,
    footer: String? = nil,
    @ViewBuilder chart: () -> Body
  ) {
    self.title = title
    self.subtitle = subtitle
    self.footer = footer
    self.chart = chart()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).bold()
      if let subtitle, !subtitle.isEmpty {
        Text(subtitle).foregroundStyle(.muted)
      }
      Divider()
      chart
      if let footer, !footer.isEmpty {
        Divider()
        Text(footer).foregroundStyle(.muted)
      }
    }
  }
}
