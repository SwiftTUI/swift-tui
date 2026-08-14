import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Anchors the framework's canonical border/stroke defaults so any
/// regression in the implicit `StrokeStyle()` defaults is caught
/// immediately.
///
/// An empty `StrokeStyle()` is a rounded, one-cell, inset border so an
/// unlabeled stroke never changes layout allocation.
@Test("StrokeStyle.init produces rounded by default")
func strokeStyleInitDefaultIsRounded() {
  let style = StrokeStyle()
  #expect(style.borderSet == .rounded)
}

@Test("StrokeStyle.init defaults placement to .inset")
func strokeStyleInitDefaultPlacementIsInset() {
  let style = StrokeStyle()
  #expect(style.placement == .inset)
}

@Test("StrokeStyle static conveniences inherit inset placement")
func strokeStyleStaticConveniencesDefaultToInset() {
  let styles: [StrokeStyle] = [
    .rounded, .heavy, .single, .double, .ascii, .block, .innerHalfBlock,
    .hidden, .markdown,
  ]
  #expect(styles.allSatisfy { $0.placement == .inset })
}

@Test("StrokeStyle keeps explicit outset placement")
func strokeStyleSupportsExplicitOutset() {
  #expect(StrokeStyle(placement: .outset).placement == .outset)
}

@Test("StrokeStyle.init lineWidth defaults to 1")
func strokeStyleInitDefaultLineWidth() {
  #expect(StrokeStyle().lineWidth == 1)
}
