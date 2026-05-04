import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct CellPixelMetricsEnvironmentTests {
  @Test("default environment value is .estimated")
  func defaultValue() {
    let values = EnvironmentValues()
    #expect(values.cellPixelMetrics == .estimated)
  }

  @Test("custom environment value round-trips")
  func customValueRoundTrips() {
    var values = EnvironmentValues()
    let metrics = CellPixelMetrics(width: 12, height: 24, source: .reported)
    values.cellPixelMetrics = metrics
    #expect(values.cellPixelMetrics == metrics)
  }
}
