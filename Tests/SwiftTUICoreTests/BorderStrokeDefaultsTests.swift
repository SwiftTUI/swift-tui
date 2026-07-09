import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Anchors the framework's canonical border/stroke defaults so any
/// regression in the implicit `StrokeStyle()` defaults is caught
/// immediately.
///
/// These defaults are the outcome of unifying border and stroke styling
/// onto a single `StrokeStyle`: an empty `StrokeStyle()` is a rounded,
/// one-cell, outset border.
@Test("StrokeStyle.init produces rounded by default")
func strokeStyleInitDefaultIsRounded() {
  let style = StrokeStyle()
  // Canonical default: rounded with .outset placement.
  #expect(style.borderSet == .rounded)
}

@Test("StrokeStyle.init defaults placement to .outset")
func strokeStyleInitDefaultPlacementIsOutset() {
  let style = StrokeStyle()
  #expect(style.placement == .outset)
}

@Test("StrokeStyle.init lineWidth defaults to 1")
func strokeStyleInitDefaultLineWidth() {
  #expect(StrokeStyle().lineWidth == 1)
}
