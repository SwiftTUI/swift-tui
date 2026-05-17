import SwiftTUICore
import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

@MainActor
@Suite
struct RenderDriverCharacterizationTests {
  static let matrix: [(name: String, view: AnyView)] = [
    ("empty", AnyView(EmptyView())),
    ("text", AnyView(Text("hello"))),
    (
      "vstack",
      AnyView(
        VStack {
          Text("a")
          Text("b")
        })
    ),
    (
      "nested",
      AnyView(
        VStack {
          HStack {
            Text("x")
            Text("y")
          }
          Text("z")
        })
    ),
    ("frame", AnyView(Text("f").frame(width: 10, height: 3))),
    ("conditional", AnyView(Group { if true { Text("on") } else { Text("off") } })),
    ("forEach", AnyView(VStack { ForEach(0..<3) { Text("\($0)") } })),
  ]

  @Test("Driver produces non-degenerate artifacts for every matrix case")
  func driverProducesArtifactsForMatrix() {
    let proposal = ProposedSize(width: .finite(40), height: .finite(20))
    for entry in Self.matrix {
      let renderer = DefaultRenderer()
      let artifacts = renderer.render(entry.view, proposal: proposal)
      #expect(artifacts.rasterSurface.size.width >= 0, "\(entry.name): raster surface must exist")
      #expect(
        artifacts.diagnostics.counts.resolvedNodes > 0,
        "\(entry.name): resolved tree must be non-empty")
    }
  }

  @Test("Repeated renders of the same view are artifact-stable")
  func repeatedRendersAreStable() {
    let proposal = ProposedSize(width: .finite(40), height: .finite(20))
    for entry in Self.matrix {
      let renderer = DefaultRenderer()
      let first = renderer.render(entry.view, proposal: proposal)
      let second = renderer.render(entry.view, proposal: proposal)
      #expect(
        first.rasterSurface == second.rasterSurface,
        "\(entry.name): identical input must produce identical raster")
      #expect(
        first.semanticSnapshot == second.semanticSnapshot,
        "\(entry.name): identical input must produce identical semantics")
    }
  }
}
