import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite("OffscreenFrameElisionRuntime")
@MainActor
struct OffscreenFrameElisionRuntimeTests {
  @Test("freshly-constructed renderer reports empty previousDrawnIdentities")
  func freshRendererHasEmptyPreviousDrawnIdentities() {
    let renderer = DefaultRenderer()
    #expect(renderer.frameTailRenderer.previousDrawnIdentities.isEmpty)
  }
}
