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
  package static func shouldElide(
    causes: Set<WakeCause>,
    hasExplicitAnimationTransactions: Bool,
    redrawIdentities: Set<Identity>,
    drawnIdentities: Set<Identity>
  ) -> Bool {
    guard causes == [.deadline] else { return false }
    guard !hasExplicitAnimationTransactions else { return false }
    return redrawIdentities.isDisjoint(with: drawnIdentities)
  }
}
