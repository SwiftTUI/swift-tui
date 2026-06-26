/// The carry-forward primitive behind ``AnimationController/publishCommittedState``.
///
/// When an in-flight frame's tail publishes its draft, it does a full `restore`
/// from the draft's snapshot — which predates any registration an async task
/// (a `PhaseAnimator` loop's `withAnimation { … } completion:`) made on the
/// *live* controller between frames. Re-applying those concurrent registrations
/// after the restore is what keeps the awaiting caller from stalling on an
/// orphaned completion.
///
/// Both registration maps that an async task can grow between frames (the
/// `withAnimation` completion closures and the animation-box registrations) run
/// through this one primitive, so the "what must survive a publish" rule lives
/// in a single named, testable place instead of being open-coded per map — the
/// open-coding is exactly the kind of hand-mirrored bookkeeping that silently
/// orphans a completion the day a third such map is added.
package enum ConcurrentRegistrationCarry {
  /// The entries present in `live` but absent from `baseline` — i.e. inserted
  /// since the baseline snapshot was taken. Keyed lookup only; values are never
  /// compared, so closures and other non-`Equatable` payloads are fine.
  package static func sinceBaseline<Key: Hashable, Value>(
    live: [Key: Value],
    baseline: [Key: Value]
  ) -> [Key: Value] {
    live.filter { baseline[$0.key] == nil }
  }

  /// Re-applies `carried` entries into `target`, never overwriting an entry the
  /// restored state already holds (the restored draft's own registration wins).
  package static func reapply<Key: Hashable, Value>(
    _ carried: [Key: Value],
    into target: inout [Key: Value]
  ) {
    for (key, value) in carried where target[key] == nil {
      target[key] = value
    }
  }
}
