import Testing

@testable import SwiftTUIViews

/// The toolbar erasure must not flatten what the strip's reuse-cache key is
/// built from. `AnyToolbarStyle` keeps the concrete style boxed so the
/// signature still comes from the concrete item layout; deriving it from the
/// erased `AnyLayout` would give every style one key.
@MainActor
@Suite("Toolbar style erasure")
struct ToolbarStyleErasureTests {
  private struct WideGapToolbarStyle: ToolbarStyle {
    var itemLayout: HStackLayout { HStackLayout(alignment: .center, spacing: 4) }
    var placement: ToolbarPlacement { .top }
  }

  private struct StackedToolbarStyle: ToolbarStyle {
    var itemLayout: VStackLayout { VStackLayout(alignment: .leading, spacing: 1) }
    var placement: ToolbarPlacement { .bottom }
  }

  @Test("the erased style forwards label and placement")
  func erasureForwardsLabelAndPlacement() {
    #expect(AnyToolbarStyle.defaultTop.snapshotLabel == "ToolbarStyle.defaultTop")
    #expect(AnyToolbarStyle.defaultTop.placement == .top)
    #expect(AnyToolbarStyle.defaultBottom.snapshotLabel == "ToolbarStyle.defaultBottom")
    #expect(AnyToolbarStyle.defaultBottom.placement == .bottom)
    // A custom style takes the reflection default.
    #expect(AnyToolbarStyle(WideGapToolbarStyle()).snapshotLabel.contains("WideGapToolbarStyle"))
  }

  @Test("layout signatures survive erasure and stay distinct across layouts")
  func layoutSignaturesSurviveErasure() throws {
    let hstack = try #require(AnyToolbarStyle.defaultTop.layoutSignature)
    let wideGap = try #require(AnyToolbarStyle(WideGapToolbarStyle()).layoutSignature)
    let stacked = try #require(AnyToolbarStyle(StackedToolbarStyle()).layoutSignature)

    // The signature is derived from the concrete layout, so a different
    // layout type and a different spacing both remain distinguishable.
    #expect(hstack != stacked)
    #expect(hstack != wideGap)
    // …and it names the concrete layout, never the eraser.
    #expect(!hstack.contains("AnyLayout"))
    #expect(!stacked.contains("AnyLayout"))
  }

  @Test("built-in styles are reuse-transparent and compare equal for reuse")
  func builtinsAreReuseTransparent() {
    #expect(AnyToolbarStyle.defaultTop.isEqualForReuse(to: AnyToolbarStyle.defaultTop))
    #expect(!AnyToolbarStyle.defaultTop.isEqualForReuse(to: AnyToolbarStyle.defaultBottom))
  }
}
