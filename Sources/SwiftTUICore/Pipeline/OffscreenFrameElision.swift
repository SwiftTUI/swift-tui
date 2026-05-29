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
///   would cause live content to be incorrectly elided.
package enum OffscreenFrameElision {
  /// Returns `true` when the frame is safe to skip.
  ///
  /// - Parameters:
  ///   - causes: The set of wake reasons that produced the scheduled frame.
  ///   - animationRequest: The animation intent attached to the frame.
  ///   - redrawIdentities: Identities that would be redrawn this frame.
  ///   - drawnIdentities: Identities that have been committed to the visible
  ///     surface at least once.
  package static func shouldElide(
    causes: Set<WakeCause>,
    animationRequest: AnimationRequest,
    redrawIdentities: Set<Identity>,
    drawnIdentities: Set<Identity>
  ) -> Bool {
    guard causes == [.deadline] else { return false }
    guard case .inherit = animationRequest else { return false }
    return redrawIdentities.isDisjoint(with: drawnIdentities)
  }
}
