import Testing

@testable import Core
@testable import TerminalUICharts

@Suite("Chart coordinate conversion")
struct ChartCoordinateConversionTests {
  @Test("horizontal chart fraction uses fractional cell-space x")
  func horizontalChartFractionUsesFractionalCellSpaceX() {
    let plotRect = CellRect(origin: .init(x: 10, y: 2), size: .init(width: 9, height: 5))

    #expect(
      chartFraction(
        at: .init(x: 12.5, y: 3),
        in: plotRect,
        axis: .horizontal
      ) == 0.3125
    )
    #expect(
      chartDomainValue(
        at: .init(x: 12.5, y: 3),
        in: plotRect,
        domain: 20...60,
        axis: .horizontal
      ) == 32.5
    )
  }

  @Test("vertical chart fraction uses inverted fractional cell-space y")
  func verticalChartFractionUsesInvertedFractionalCellSpaceY() {
    let plotRect = CellRect(origin: .init(x: 4, y: 20), size: .init(width: 6, height: 9))

    #expect(
      chartFraction(
        at: .init(x: 5, y: 22.5),
        in: plotRect,
        axis: .vertical
      ) == 0.6875
    )
    #expect(
      chartDomainValue(
        at: .init(x: 5, y: 22.5),
        in: plotRect,
        domain: -10...30,
        axis: .vertical
      ) == 17.5
    )
  }

  @Test("chart conversion clamps out-of-bounds and degenerate axes")
  func chartConversionClampsOutOfBoundsAndDegenerateAxes() {
    let plotRect = CellRect(origin: .init(x: 10, y: 20), size: .init(width: 9, height: 9))

    #expect(
      chartFraction(
        at: .init(x: 4, y: 20),
        in: plotRect,
        axis: .horizontal
      ) == 0
    )
    #expect(
      chartFraction(
        at: .init(x: 10, y: 99),
        in: plotRect,
        axis: .vertical
      ) == 0
    )
    #expect(
      chartDomainValue(
        at: .init(x: 40, y: 20),
        in: .init(origin: .zero, size: .init(width: 1, height: 8)),
        domain: 5...9,
        axis: .horizontal
      ) == 5
    )
  }
}
