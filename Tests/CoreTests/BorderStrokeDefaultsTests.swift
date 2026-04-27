import Testing

@testable import Core

/// Baseline test capturing the framework's canonical border/stroke
/// defaults. Tracks the pre-vs-post-simplification flip planned in
/// `docs/plans/2026-04-26-003-border-stroke-simplification-plan.md`:
///
/// - `strokeStyleInitDefaultIsOuterHalfBlock` is INTENTIONALLY FAILING
///   today; it will pass once Task 6 changes the canonical default.
/// - `strokeStyleInitDefaultLineWidth` is an invariant — it should
///   pass before *and* after the simplification lands; it's here to
///   anchor the file's purpose alongside the changing assertions.
@Test("StrokeStyle.init produces outerHalfBlock by default")
func strokeStyleInitDefaultIsOuterHalfBlock() {
  let style = StrokeStyle()
  // PRE-SIMPLIFICATION: this is `.single` and FAILS.
  // POST-TASK-6: expected to be `.outerHalfBlock`.
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
