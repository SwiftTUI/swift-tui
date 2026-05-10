import Foundation

/// Returns the minimum-to-maximum date range covered by `days`, or `nil`
/// when the input is empty.
func inferDateRange(_ days: [DateValue]) -> ClosedRange<Date>? {
  guard let first = days.first else { return nil }
  var lower = first.date
  var upper = first.date
  for entry in days.dropFirst() {
    if entry.date < lower { lower = entry.date }
    if entry.date > upper { upper = entry.date }
  }
  return lower...upper
}
