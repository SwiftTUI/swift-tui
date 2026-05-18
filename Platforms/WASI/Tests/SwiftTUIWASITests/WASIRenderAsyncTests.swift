import SwiftTUI
import Testing

struct WASIRenderAsyncTests {
  @MainActor
  @Test("renderAsync produces a surface in the WASI test lane")
  func renderAsyncSmokeTest() async {
    let artifacts = await DefaultRenderer().renderAsync(
      Text("wasi async"),
      proposal: .init(width: 16, height: 2)
    )

    #expect(artifacts.rasterSurface.lines.contains { $0.contains("wasi async") })
  }
}
