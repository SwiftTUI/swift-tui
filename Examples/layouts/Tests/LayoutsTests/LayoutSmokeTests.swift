import SwiftTUI
import Testing

@testable import Layouts

/// Every catalog entry must resolve, rasterise to a non-empty
/// surface, and paint its ``LayoutEntry/marker`` string somewhere
/// in the viewport. Replicates the pattern used by
/// `BordersAndShapesTabTests.rendersNonEmptySurface`.
@MainActor
@Suite
struct LayoutSmokeTests {
  @Test(
    "Every catalog entry resolves and paints its marker",
    arguments: LayoutCatalog.all
  )
  func rasterisesAndShowsMarker(entry: LayoutEntry) {
    let size = CellSize(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = size
    let artifacts = DefaultRenderer().render(
      entry.makeView(),
      context: ResolveContext(
        identity: Identity(components: ["layouts.smoke.\(entry.id)"]),
        environmentValues: env
      ),
      proposal: ProposedSize(width: size.width, height: size.height)
    )
    #expect(
      artifacts.rasterSurface.cells.count > 0,
      "\(entry.id) produced zero raster rows"
    )
    #expect(
      artifacts.rasterSurface.lines.contains { !$0.isEmpty },
      "\(entry.id) produced only empty lines"
    )
    let joined = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(
      joined.contains(entry.marker),
      "\(entry.id) did not paint marker '\(entry.marker)'\n\(joined)"
    )
  }
}
