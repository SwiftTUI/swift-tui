/// A per-presented-frame claim that exactly one scroll route's viewport
/// content moved vertically by a whole-cell delta between the previously
/// presented frame and this one, with everything else unchanged.
///
/// The candidate is a *hypothesis*, not a verified fact: its producer (the run
/// loop's presented-frame scroll ledger) compares only registry offsets and
/// viewport geometry, never surface cells. Any consumer that wants to act on
/// it — scroll-region emission, raster band blits — must first verify the
/// translation against the actual surfaces, cell-for-cell, and must discard
/// the candidate whenever the presentation baseline is stale
/// (`requestedDamageTrustsBaseline == false`): after a writer drop the run
/// loop's presented baseline is one frame ahead of the rolled-back written
/// baseline, so the claim is unsound for exactly that recovery frame.
package struct ScrollTranslationCandidate: Equatable, Sendable {
  /// The scroll route's viewport rect in surface coordinates, clamped to the
  /// surface — the rows and columns the translation claim covers.
  ///
  /// For hosted collections (list, table) this is the drawn-content rect
  /// (chrome and overflow-indicator lines excluded). For a plain `ScrollView`
  /// it is the node's bounds, which still contain the trailing
  /// scroll-indicator overlay column (and the bottom indicator row when a
  /// horizontal indicator is shown). Cell-for-cell verification stays sound
  /// either way; the distinction only moves a consumer's fallback rate.
  package var band: CellRect
  /// Screen-space rows the band's content moved: negative when the user
  /// scrolled down (offset increased, content slid up), positive when the
  /// user scrolled up. Computed as `previousOffset.y - currentOffset.y`.
  package var dy: Int
  /// The run-loop frame ordinal of the presented frame the claim is relative
  /// to — the same ordinal `frames.tsv` reports — so a consumer can check
  /// that the claim's baseline is the frame it thinks it is diffing against.
  package var baselineFrameOrdinal: Int

  package init(
    band: CellRect,
    dy: Int,
    baselineFrameOrdinal: Int
  ) {
    self.band = band
    self.dy = dy
    self.baselineFrameOrdinal = baselineFrameOrdinal
  }
}
