/// A pure gate predicate that decides whether a pending frame can skip the
/// rendering pipeline because its redraw cannot reach the visible surface.
///
/// The check is conservative: it only elides frames that were produced
/// *solely* by an animation deadline (no user input, no state invalidation)
/// and carry no explicit animation transaction, provided every identity
/// that would be redrawn is absent from the set of identities that have
/// ever appeared on-screen.
///
/// The predicate is a pure function with no runtime dependencies and is
/// therefore unit-testable in isolation.
///
/// - Note: The predicate is only as sound as the caller's `drawnIdentities`
///   set. An identity that appeared on-screen but was never recorded there
///   would cause live content to be incorrectly elided. The load-bearing
///   invariant — clipped-out identities must NEVER be recorded in
///   `drawnIdentities` — is documented at the recording site in
///   `Raster/Rasterizer+Paint.swift`; it is what makes eliding an off-screen
///   animation (paint-only or layout-affecting) sound.
///
/// - Note: "never drawn" only implies "cannot reach the surface" for a redraw
///   that repaints a node where it already sits. Work owned by the placed
///   overlay pass breaks that implication in both directions, which is why
///   `hasPlacedPassOwnedAnimationWork` is a hard blocker.
package enum OffscreenFrameElision {
  /// Returns `true` when the frame is safe to skip.
  ///
  /// - Parameters:
  ///   - causes: The set of wake reasons that produced the scheduled frame.
  ///   - hasExplicitAnimationTransactions: Whether the frame carries any new
  ///     identity-scoped animation transaction.
  ///   - redrawIdentities: Identities that would be redrawn this frame.
  ///   - drawnIdentities: Identities that have been committed to the visible
  ///     surface at least once.
  ///   - hasPlacedPassOwnedAnimationWork: Whether the placed-overlay pass owns
  ///     live animation work — an insertion offset, a matched-geometry travel,
  ///     or an exit overlay. Such a frame can never be elided, for two
  ///     independent reasons: the work relocates a node's placed rect, so an
  ///     identity that is off-surface now is precisely the one due to arrive
  ///     on it; and the pass an elided frame skips is the sole owner of that
  ///     work's evaluation, advance, and completion. An elided frame would
  ///     therefore freeze the animation at the sample it was registered with —
  ///     permanently, since the frozen sample keeps the identity off-surface
  ///     and so keeps every later tick elidable.
  package static func shouldElide(
    causes: Set<WakeCause>,
    hasExplicitAnimationTransactions: Bool,
    redrawIdentities: Set<Identity>,
    drawnIdentities: Set<Identity>,
    hasPlacedPassOwnedAnimationWork: Bool
  ) -> Bool {
    // Explicitness stays keyed to animation intent: `isContinuous` alone
    // does not make a transaction explicit. Continuity is resolve-side
    // metadata — its segment never survives append without animation
    // intent, so elision cannot drop a delivery that carries only the
    // flag (plan 2026-08-04-002 §5.5).
    guard causes == [.deadline] else { return false }
    guard !hasExplicitAnimationTransactions else { return false }
    guard !hasPlacedPassOwnedAnimationWork else { return false }
    return redrawIdentities.isDisjoint(with: drawnIdentities)
  }
}
