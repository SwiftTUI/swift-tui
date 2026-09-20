import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Anchors the framework's canonical border/stroke defaults so any
/// regression in the implicit `StrokeStyle()` defaults is caught
/// immediately.
///
/// An empty `StrokeStyle()` is a solid single line with square corners, as
/// SwiftUI's default stroke is, and it is inset, so an unlabeled stroke never
/// changes layout allocation.
///
/// The default was `.rounded` until the border and stroke redesign (ruling 4,
/// 2026-09-19). The built-in controls ask for rounded corners themselves, so
/// they did not change with it.
@Test("StrokeStyle.init is a solid single line with square corners by default")
func strokeStyleInitDefaultIsSquareSingleLine() {
  let style = StrokeStyle()
  #expect(style.borderSet == .single)
  #expect(style.lineJoin == .miter)
  #expect(style.dash.isEmpty)
  #expect(style.dashPhase == 0)
}

@Test("StrokeStyle.init defaults placement to .inset")
func strokeStyleInitDefaultPlacementIsInset() {
  let style = StrokeStyle()
  #expect(style.placement == .inset)
}

@Test("StrokeStyle static conveniences inherit inset placement")
func strokeStyleStaticConveniencesDefaultToInset() {
  let styles: [StrokeStyle] = [
    .rounded, .heavy, .single, .double, .singleDouble, .doubleSingle, .ascii, .block,
    .innerHalfBlock, .outerHalfBlock, .hidden, .none, .markdown, .dashed, .dashedHeavy,
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
