import Foundation
import Testing

@testable import SwiftTUICharts

private let utcGregorian: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}()

@Suite("CalendarHeatmap modifiers")
@MainActor
struct CalendarHeatmapModifierTests {
  @Test("chartLegend(.hidden) clears showsScaleLegend")
  func chartLegendHiddenClearsFlag() {
    let chart = CalendarHeatmap(days: [], calendar: utcGregorian).chartLegend(.hidden)
    #expect(chart.showsScaleLegend == false)
  }

  @Test("chartLegend(.bottom) keeps showsScaleLegend true")
  func chartLegendBottomKeepsFlag() {
    let chart = CalendarHeatmap(days: [], calendar: utcGregorian).chartLegend(.bottom)
    #expect(chart.showsScaleLegend == true)
  }
}
