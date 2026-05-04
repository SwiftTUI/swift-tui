import Testing

@testable import SwiftTUICore

@Suite("Pointer locations")
struct PointerLocationTests {
  @Test("cell fallback uses center of cell and records cell precision")
  func cellFallbackCentersReportedCell() {
    let pointer = PointerLocation.cellFallback(CellPoint(x: 4, y: 6))

    #expect(pointer.cell == CellPoint(x: 4, y: 6))
    #expect(pointer.location == Point(x: 4.5, y: 6.5))
    #expect(pointer.precision == .cell)
    #expect(pointer.rawPixel == nil)
    #expect(!pointer.precision.isSubCell)
  }

  @Test("sub-cell construction derives containing cell")
  func subCellDerivesContainingCell() {
    let metrics = CellPixelMetrics(width: 10, height: 20, source: .reported)
    let pointer = PointerLocation.subCell(
      location: Point(x: 2.7, y: 1.2),
      source: .nativePixels,
      metrics: metrics,
      rawPixel: PixelPoint(x: 27, y: 24)
    )

    #expect(pointer.cell == CellPoint(x: 2, y: 1))
    #expect(pointer.location == Point(x: 2.7, y: 1.2))
    #expect(pointer.precision == .subCell(source: .nativePixels, metrics: metrics))
    #expect(pointer.precision.isSubCell)
    #expect(pointer.rawPixel == PixelPoint(x: 27, y: 24))
  }

  @Test("cell-only capabilities are the default")
  func cellOnlyCapabilitiesAreDefault() {
    let capabilities = PointerInputCapabilities.cellOnly

    #expect(capabilities.precision == .cell)
    #expect(!capabilities.supportsSubCellLocation)
    #expect(!capabilities.supportsHover)
    #expect(!capabilities.supportsPreciseScroll)
  }

  @Test("sub-cell capabilities derive sub-cell support from precision")
  func subCellCapabilitiesDeriveSupportFromPrecision() {
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    let capabilities = PointerInputCapabilities(
      precision: .subCell(source: .webPixels, metrics: metrics),
      supportsHover: true,
      supportsPreciseScroll: true
    )

    #expect(capabilities.precision == .subCell(source: .webPixels, metrics: metrics))
    #expect(capabilities.supportsSubCellLocation)
    #expect(capabilities.supportsHover)
    #expect(capabilities.supportsPreciseScroll)
  }

  @Test("sub-cell support follows precision mutations")
  func subCellSupportFollowsPrecisionMutations() {
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    var capabilities = PointerInputCapabilities.cellOnly

    capabilities.precision = .subCell(source: .terminalPixels, metrics: metrics)

    #expect(capabilities.supportsSubCellLocation)
  }
}
