import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("LineChart domain helpers")
struct LineChartDomainTests {
  @Test("LineChartPoint stores raw x and y")
  func storesRawCoords() {
    let point = LineChartPoint(x: 3.5, y: 12)
    #expect(point.x == 3.5)
    #expect(point.y == 12)
  }

  @Test("LineChartPoint date initializer maps to reference interval")
  func dateInitializerMapsToReferenceInterval() {
    let date = Date(timeIntervalSinceReferenceDate: 123_456)
    let point = LineChartPoint(date: date, value: 9)
    #expect(point.x == 123_456)
    #expect(point.y == 9)
  }

  @Test("LineChartSeries stores label, points, style, and tone")
  func seriesStoresInputs() {
    let series = LineChartSeries(
      "Opus",
      points: [.init(x: 0, y: 1), .init(x: 1, y: 2)],
      style: .area,
      tone: .info
    )
    #expect(series.label == "Opus")
    #expect(series.points.count == 2)
    #expect(series.style == .area)
    #expect(series.tone == .info)
  }

  @Test("LineChartSeries defaults to .line / .automatic")
  func seriesDefaults() {
    let series = LineChartSeries("X", points: [])
    #expect(series.style == .line)
    #expect(series.tone == .automatic)
  }

  @Test("plotDomain spans min..max across series for X and Y")
  func plotDomainSpansAllSeries() {
    let s1 = LineChartSeries("A", points: [.init(x: 0, y: 1), .init(x: 5, y: 10)])
    let s2 = LineChartSeries("B", points: [.init(x: 2, y: -3), .init(x: 6, y: 4)])
    let domain = plotDomain(series: [s1, s2])
    #expect(domain?.x.lowerBound == 0)
    #expect(domain?.x.upperBound == 6)
    #expect(domain?.y.lowerBound == -3)
    #expect(domain?.y.upperBound == 10)
  }

  @Test("plotDomain is nil when no series contains points")
  func plotDomainNilWhenEmpty() {
    let s = LineChartSeries("A", points: [])
    #expect(plotDomain(series: [s]) == nil)
    #expect(plotDomain(series: []) == nil)
  }

  @Test("plotDomain degenerates to a 1-wide range when all values equal")
  func plotDomainDegenerate() {
    let s = LineChartSeries("A", points: [.init(x: 5, y: 5)])
    let domain = plotDomain(series: [s])
    #expect(domain?.x == 5...5)
    #expect(domain?.y == 5...5)
  }
}
