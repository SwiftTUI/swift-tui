import Testing
@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
@_spi(Runners) @testable import TermUIPerf

struct PerfTerminalHostTests {
  @Test("raster presentation records full repaint metrics")
  func rasterPresentationRecordsFullRepaintMetrics() throws {
    let host = PerfTerminalHost(size: PerfTerminalSize(columns: 6, rows: 2))
    let surface = RasterSurface(
      size: CellSize(width: 6, height: 2),
      lines: ["ABCDEF", "stable"]
    )

    let metrics = try host.present(surface)

    #expect(metrics.strategy == .fullRepaint)
    #expect(metrics.linesTouched == 2)
    #expect(metrics.cellsChanged == 12)
    #expect(host.presentedFrames.last?.metrics == metrics)
  }

  @Test("semantic host presentation records incremental damage metrics")
  func semanticHostPresentationRecordsIncrementalDamageMetrics() throws {
    let host = PerfTerminalHost(size: PerfTerminalSize(columns: 6, rows: 2))
    let surface = RasterSurface(
      size: CellSize(width: 6, height: 2),
      lines: ["ABCDEF", "stable"]
    )
    let damage = PresentationDamage(
      textRows: [
        PresentationDamage.TextRow(row: 0, columnRanges: [2..<4]),
        PresentationDamage.TextRow(row: 1),
      ]
    )

    let metrics = try host.present(
      SemanticHostFrame(
        sequence: 1,
        raster: surface,
        semantics: SemanticSnapshot(),
        focusedIdentity: nil,
        rasterDamage: damage
      ))

    #expect(host.semanticHostFrameCapabilities == [.rasterDamage])
    #expect(metrics.strategy == .incremental)
    #expect(metrics.linesTouched == 2)
    #expect(metrics.cellsChanged == 8)
    #expect(host.presentedFrames.last?.metrics == metrics)
  }
}
