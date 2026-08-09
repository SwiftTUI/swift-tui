/// A draw-tree-verified plan for serving a scroll frame's band by moving the
/// previous surface's row buffers (scroll-latency R3.2b).
///
/// Produced by the frame tail's translation-hypothesis leg from the committed
/// translation candidate plus a positional dy-walk of the previous vs current
/// draw trees. The rows in `repaintRows` could not be proven translatable
/// (exposed by the scroll, painted by non-translated content, or adjacent to
/// either — the one-cell half-block reach); every other band row is *provably*
/// the previous frame's `row − dy` under the walk's projection equality, so
/// the rasterizer may serve it by moving the previous row's buffer —
/// preserving the buffer's identity at its new y — and restrict repainting to
/// `repaintRows` plus the ordinary off-band damage.
///
/// The plan is a *raster-internal* instruction, not a presentation contract:
/// hosts still see full cells + damage, and the F13 verification oracle
/// compares the blitted surface against a fresh rasterization unchanged.
package struct RasterTranslationPlan: Equatable, Sendable {
  /// The verified band, clamped to the surface.
  package var band: CellRect
  /// Screen rows the band content moved; same sign convention as
  /// ``ScrollTranslationCandidate/dy``.
  package var dy: Int
  /// Band rows that must repaint through the ordinary damage path. Every row
  /// of `band` NOT in this set is verified translatable.
  package var repaintRows: Set<Int>

  package init(
    band: CellRect,
    dy: Int,
    repaintRows: Set<Int>
  ) {
    self.band = band
    self.dy = dy
    self.repaintRows = repaintRows
  }

  package var bandRows: Range<Int> {
    band.origin.y..<band.maxY
  }

  /// The rows the blit serves, ascending.
  package var translatedRows: [Int] {
    bandRows.filter { !repaintRows.contains($0) }
  }
}
