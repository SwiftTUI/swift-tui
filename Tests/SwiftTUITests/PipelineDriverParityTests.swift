import SwiftTUICore
import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

@MainActor
@Suite
struct PipelineDriverParityTests {
  @Test("Sync and async renders of the same view produce equal artifacts")
  func syncAsyncParity() async {
    let proposal = ProposedSize(width: .finite(40), height: .finite(20))
    for entry in RenderDriverCharacterizationTests.matrix {
      let syncRenderer = DefaultRenderer()
      let asyncRenderer = DefaultRenderer()
      let syncArtifacts = syncRenderer.render(entry.view, proposal: proposal)
      let asyncArtifacts = await asyncRenderer.renderAsync(entry.view, proposal: proposal)
      #expect(
        syncArtifacts.rasterSurface == asyncArtifacts.rasterSurface,
        "\(entry.name): sync and async raster must match")
      #expect(
        syncArtifacts.semanticSnapshot == asyncArtifacts.semanticSnapshot,
        "\(entry.name): sync and async semantics must match")
      #expect(
        syncArtifacts.placedTree == asyncArtifacts.placedTree,
        "\(entry.name): sync and async placement must match")
    }
  }
}
