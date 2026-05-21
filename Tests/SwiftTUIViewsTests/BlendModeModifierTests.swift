import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct BlendModeModifierTests {
  @Test("blendMode modifier writes draw metadata")
  func blendModeModifierWritesDrawMetadata() {
    let resolved = Text("Glow")
      .blendMode(.multiply)
      .resolve(in: .init(identity: testIdentity("BlendMode", "Root")))

    #expect(resolved.drawMetadata.blendMode == .multiply)
  }

  @Test("later blendMode modifier overrides earlier blend metadata")
  func laterBlendModeModifierOverridesEarlierBlendMetadata() {
    let resolved = Text("Glow")
      .blendMode(.multiply)
      .blendMode(.screen)
      .resolve(in: .init(identity: testIdentity("BlendMode", "Root")))

    #expect(resolved.drawMetadata.blendMode == .screen)
  }
}
