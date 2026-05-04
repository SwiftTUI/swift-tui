import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("Pointer input environment")
struct PointerInputEnvironmentTests {
  @Test("pointer capabilities default to cell-only")
  func pointerCapabilitiesDefaultToCellOnly() {
    let values = EnvironmentValues()

    #expect(values.pointerInputCapabilities == .cellOnly)
  }

  @Test("pointer capabilities round-trip through environment")
  func pointerCapabilitiesRoundTrip() {
    var values = EnvironmentValues()
    let metrics = CellPixelMetrics(width: 12, height: 24, source: .reported)
    let capabilities = PointerInputCapabilities(
      precision: .subCell(source: .nativePixels, metrics: metrics),
      supportsHover: true,
      supportsPreciseScroll: true
    )

    values.pointerInputCapabilities = capabilities

    #expect(values.pointerInputCapabilities == capabilities)
  }
}
