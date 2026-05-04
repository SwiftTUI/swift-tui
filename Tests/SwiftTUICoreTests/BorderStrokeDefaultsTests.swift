import Testing

@testable import SwiftTUICore

/// Anchors the framework's canonical border/stroke defaults so any
/// regression in the implicit `StrokeStyle()` defaults is caught
/// immediately.
///
/// See `docs/plans/2026-04-26-003-border-stroke-simplification-plan.md`
/// and `docs/proposals/BORDERS_AND_STROKES.md` for the migration
/// history that established these defaults.
@Test("StrokeStyle.init produces outerHalfBlock by default")
func strokeStyleInitDefaultIsOuterHalfBlock() {
  let style = StrokeStyle()
  // Canonical default: outerHalfBlock with .outset placement.
  #expect(style.borderSet == .outerHalfBlock)
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
