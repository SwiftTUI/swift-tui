import Testing

@testable import Core

@Suite
struct PipelineTests {
  @Test("noOp renderer produces valid frame artifacts")
  func noOpRendererProducesArtifacts() {
    let renderer = Renderer<NoOpRoot>.noOp()
    let root = NoOpRoot(
      identity: testIdentity("root"),
      intrinsicSize: Size(width: 20, height: 10)
    )

    let artifacts = renderer.renderFrame(root: root)
    #expect(artifacts.resolvedTree.identity == testIdentity("root"))
    #expect(artifacts.measuredTree.measuredSize == Size(width: 20, height: 10))
    #expect(artifacts.placedTree.bounds.size == Size(width: 20, height: 10))
  }

  @Test("noOp renderer with zero size produces zero-sized artifacts")
  func noOpRendererWithZeroSize() {
    let renderer = Renderer<NoOpRoot>.noOp()
    let root = NoOpRoot(identity: testIdentity("empty"), intrinsicSize: .zero)

    let artifacts = renderer.renderFrame(root: root)
    #expect(artifacts.measuredTree.measuredSize == .zero)
  }
}
