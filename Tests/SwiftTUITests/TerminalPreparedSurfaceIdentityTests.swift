import SwiftTUICore
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// R3.2c prerequisite pin — G10: for image-free surfaces,
/// `TerminalImageRenderer.preparedSurface` is the identity function, so
/// row-buffer identity established in the raster tier (the R3.2b blit)
/// survives into the writer's baseline. The scroll-region planner's O(1)
/// row-identity verification rests on exactly this; if preparation ever
/// starts copying image-free surfaces, this pin fails before the planner
/// can mis-trust a pointer compare.
@Suite
struct TerminalPreparedSurfaceIdentityTests {
  @Test("preparedSurface keeps row-buffer identity for image-free surfaces")
  func imageFreeSurfaceKeepsRowBufferIdentity() {
    let renderer = TerminalImageRenderer(repository: sharedImageAssetRepository)
    let surface = RasterSurface(
      size: CellSize(width: 6, height: 3),
      lines: ["abcdef", "ghijkl", "mnopqr"]
    )

    let prepared = renderer.preparedSurface(
      for: surface,
      capabilityProfile: TerminalEmissionSimulationHost.laneCapabilityProfile,
      graphicsCapabilities: .none,
      fallbackBackground: TerminalAppearance.fallback.backgroundColor
    )

    #expect(prepared.cells.count == surface.cells.count)
    for row in surface.cells.indices {
      let sharesStorage = unsafe surface.cells[row].withUnsafeBufferPointer { original in
        unsafe prepared.cells[row].withUnsafeBufferPointer { preparedRow in
          unsafe original.baseAddress == preparedRow.baseAddress
        }
      }
      #expect(sharesStorage, "row \(row) must keep its buffer identity (G10)")
    }
  }
}
