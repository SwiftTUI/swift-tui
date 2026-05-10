import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("CalendarHeatmap modifiers")
struct CalendarHeatmapModifierTests {
  @Test("chartLegend(.hidden) clears showsScaleLegend")
  @MainActor
  func chartLegendHiddenClearsFlag() {
    let chart = CalendarHeatmap(days: []).chartLegend(.hidden)
    #expect(chart.showsScaleLegend == false)
  }

  @Test("chartLegend(.bottom) keeps showsScaleLegend true")
  @MainActor
  func chartLegendBottomKeepsFlag() {
    let chart = CalendarHeatmap(days: []).chartLegend(.bottom)
    #expect(chart.showsScaleLegend == true)
  }
}
