import Foundation

struct AxisTickLabel: Equatable, Sendable {
  var row: Int
  var col: Int
  var text: String
}

extension AxisTickLabel {
  init(row: Int, text: String) { self.init(row: row, col: 0, text: text) }
  init(col: Int, text: String) { self.init(row: 0, col: col, text: text) }
}

/// Computes X-axis tick labels for `LineChart`, snapping to calendar
/// boundaries when `ticks` is `.dates(...)` and pinning the calendar's
/// timezone onto the format style for deterministic rendering.
func xAxisTickLabels(
  domain: ClosedRange<Double>,
  ticks: LineChartXAxis.Ticks,
  format: LineChartXAxis.Format,
  plotWidth: Int,
  calendar: Calendar = defaultGregorianUTC
) -> [AxisTickLabel] {
  let width = max(1, plotWidth)
  let span = domain.upperBound - domain.lowerBound
  guard span > 0 else {
    return [AxisTickLabel(col: 0, text: formatX(value: domain.lowerBound, using: format))]
  }

  switch ticks {
  case .automatic:
    return evenlySpacedXTicks(count: 5, domain: domain, plotWidth: width, format: format)
  case .count(let n):
    return evenlySpacedXTicks(count: max(2, n), domain: domain, plotWidth: width, format: format)
  case .every(let stride):
    let count = max(2, Int(span / max(stride, .leastNonzeroMagnitude)))
    return evenlySpacedXTicks(count: count, domain: domain, plotWidth: width, format: format)
  case .dates(let stride):
    return dateStrideXTicks(
      stride: stride,
      domain: domain,
      plotWidth: width,
      format: format,
      calendar: calendar
    )
  }
}

private let defaultGregorianUTC: Calendar = {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "UTC")!
  return cal
}()

private func evenlySpacedXTicks(
  count: Int,
  domain: ClosedRange<Double>,
  plotWidth: Int,
  format: LineChartXAxis.Format
) -> [AxisTickLabel] {
  let span = domain.upperBound - domain.lowerBound
  var out: [AxisTickLabel] = []
  for i in 0..<count {
    let fraction = Double(i) / Double(count - 1)
    let value = domain.lowerBound + fraction * span
    let col = Int((fraction * Double(plotWidth - 1)).rounded())
    out.append(AxisTickLabel(col: col, text: formatX(value: value, using: format)))
  }
  return out
}

private func dateStrideXTicks(
  stride: DateAxisStride,
  domain: ClosedRange<Double>,
  plotWidth: Int,
  format: LineChartXAxis.Format,
  calendar: Calendar
) -> [AxisTickLabel] {
  let startDate = Date(timeIntervalSinceReferenceDate: domain.lowerBound)
  let endDate = Date(timeIntervalSinceReferenceDate: domain.upperBound)
  let span = domain.upperBound - domain.lowerBound

  let component: Calendar.Component
  switch stride {
  case .day: component = .day
  case .week: component = .weekOfYear
  case .month: component = .month
  case .quarter: component = .quarter
  case .year: component = .year
  }

  var current = nextStrideBoundary(after: startDate, component: component, calendar: calendar)
  var out: [AxisTickLabel] = []
  let tzPinnedFormat = pinTimezone(calendar.timeZone, to: format)
  while current <= endDate {
    let value = current.timeIntervalSinceReferenceDate
    let fraction = (value - domain.lowerBound) / span
    let col = Int((fraction * Double(plotWidth - 1)).rounded())
    out.append(AxisTickLabel(col: col, text: formatX(value: value, using: tzPinnedFormat)))
    guard let next = calendar.date(byAdding: component, value: 1, to: current) else { break }
    current = next
  }
  return out
}

private func pinTimezone(
  _ timeZone: TimeZone,
  to format: LineChartXAxis.Format
) -> LineChartXAxis.Format {
  switch format {
  case .date(var style):
    style.timeZone = timeZone
    return .date(style)
  default:
    return format
  }
}

private func nextStrideBoundary(
  after date: Date,
  component: Calendar.Component,
  calendar: Calendar
) -> Date {
  var truncated = date
  switch component {
  case .day:
    truncated = calendar.startOfDay(for: date)
  case .weekOfYear:
    truncated = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
  case .month:
    truncated = calendar.dateInterval(of: .month, for: date)?.start ?? date
  case .quarter:
    truncated = calendar.dateInterval(of: .quarter, for: date)?.start ?? date
  case .year:
    truncated = calendar.dateInterval(of: .year, for: date)?.start ?? date
  default:
    break
  }
  if truncated < date, let next = calendar.date(byAdding: component, value: 1, to: truncated) {
    return next
  }
  return truncated
}

private func formatX(value: Double, using format: LineChartXAxis.Format) -> String {
  switch format {
  case .automatic, .number:
    let style: FloatingPointFormatStyle<Double>
    if case .number(let s) = format { style = s } else { style = .number }
    return style.format(value)
  case .date(let style):
    return Date(timeIntervalSinceReferenceDate: value).formatted(style)
  }
}

func yAxisTickLabels(
  domain: ClosedRange<Double>,
  ticks: LineChartYAxis.Ticks,
  format: FloatingPointFormatStyle<Double>,
  plotHeight: Int
) -> [AxisTickLabel] {
  let height = max(1, plotHeight)
  let span = domain.upperBound - domain.lowerBound

  let count: Int
  switch ticks {
  case .automatic:
    count = 5
  case .count(let n):
    count = max(2, n)
  case .every(let stride):
    count = max(2, Int(span / max(stride, .leastNonzeroMagnitude)))
  }

  guard span > 0 else {
    return [AxisTickLabel(row: 0, text: format.format(domain.lowerBound))]
  }

  var out: [AxisTickLabel] = []
  for i in 0..<count {
    let fraction = Double(i) / Double(count - 1)
    let value = domain.upperBound - fraction * span
    let row = Int((fraction * Double(height - 1)).rounded())
    out.append(AxisTickLabel(row: row, text: format.format(value)))
  }
  return out
}
