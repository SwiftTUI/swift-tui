import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct BlendModeModifierTests {
  @Test("blendMode modifier appends an ordered draw effect")
  func blendModeModifierAppendsOrderedDrawEffect() {
    let resolved = Text("Glow")
      .blendMode(.multiply)
      .resolve(in: .init(identity: testIdentity("BlendMode", "Root")))

    #expect(resolved.drawEffects.ordered == [.blendMode(.multiply)])
  }

  @Test("multiple blendMode modifiers preserve authored order")
  func multipleBlendModeModifiersPreserveAuthoredOrder() {
    let resolved = Text("Glow")
      .blendMode(.multiply)
      .blendMode(.screen)
      .resolve(in: .init(identity: testIdentity("BlendMode", "Root")))

    #expect(resolved.drawEffects.ordered == [.blendMode(.multiply), .blendMode(.screen)])
  }

  @Test("blendMode before compositingGroup preserves order")
  func blendModeBeforeCompositingGroupPreservesOrder() {
    let resolved = Text("Glow")
      .blendMode(.multiply)
      .compositingGroup()
      .resolve(in: .init(identity: testIdentity("BlendMode", "Root")))

    #expect(resolved.drawEffects.ordered == [.blendMode(.multiply), .compositingGroup])
  }

  @Test("compositingGroup before blendMode preserves order")
  func compositingGroupBeforeBlendModePreservesOrder() {
    let resolved = Text("Glow")
      .compositingGroup()
      .blendMode(.multiply)
      .resolve(in: .init(identity: testIdentity("BlendMode", "Root")))

    #expect(resolved.drawEffects.ordered == [.compositingGroup, .blendMode(.multiply)])
  }
}
