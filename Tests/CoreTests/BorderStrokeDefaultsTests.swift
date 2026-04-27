import Testing

@testable import Core

/// Baseline test capturing the framework's canonical border/stroke
/// defaults. Each `@Test` lists the *expected post-simplification* default
/// (after Task 6 lands) and the *current pre-simplification* default it
/// replaces. The default-borderset test below is INTENTIONALLY FAILING
/// today; it will pass once Task 6 of the border/stroke simplification
/// plan flips the default. The placement test is commented out until
/// Task 2 adds the `placement` field to `StrokeStyle`.
///
/// See `docs/plans/2026-04-26-003-border-stroke-simplification-plan.md`.
@Test("StrokeStyle.init produces outerHalfBlock by default")
func strokeStyleInitDefaultIsOuterHalfBlock() {
  let style = StrokeStyle()
  // PRE-SIMPLIFICATION: this is `.single` and FAILS.
  // POST-TASK-6: expected to be `.outerHalfBlock`.
  #expect(style.borderSet == .outerHalfBlock)
}

// TODO(Task 2): uncomment once `StrokeStyle.placement` exists.
// @Test("StrokeStyle.init defaults placement to .outset")
// func strokeStyleInitDefaultPlacementIsOutset() {
//   let style = StrokeStyle()
//   #expect(style.placement == .outset)
// }

@Test("StrokeStyle.init lineWidth defaults to 1")
func strokeStyleInitDefaultLineWidth() {
  #expect(StrokeStyle().lineWidth == 1)
}

@Test("BorderSet.outerHalfBlock has consistent half-block corners")
func outerHalfBlockCornersAreConsistent() {
  let set = BorderSet.outerHalfBlock
  #expect(set.top == "▀")
  #expect(set.bottom == "▄")
  #expect(set.left == "▌")
  #expect(set.right == "▐")
  #expect(set.topLeading == "▛")
  #expect(set.topTrailing == "▜")
  #expect(set.bottomLeading == "▙")
  #expect(set.bottomTrailing == "▟")
}
