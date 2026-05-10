import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("CalendarHeatmap modifiers")
@MainActor
struct CalendarHeatmapModifierTests {
  @Test("chartLegend(.hidden) clears showsScaleLegend")
  func chartLegendHiddenClearsFlag() {
    let chart = CalendarHeatmap(days: []).chartLegend(.hidden)
    #expect(chart.showsScaleLegend == false)
  }

  @Test("chartLegend(.bottom) keeps showsScaleLegend true")
  func chartLegendBottomKeepsFlag() {
    let chart = CalendarHeatmap(days: []).chartLegend(.bottom)
    #expect(chart.showsScaleLegend == true)
  }
}
