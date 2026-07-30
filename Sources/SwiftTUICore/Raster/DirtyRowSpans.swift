/// The exact dirty-row set of an incremental raster, coalesced into sorted,
/// disjoint, half-open row spans.
///
/// The incremental rasterizer is handed an exact `Set<Int>` of dirty rows, but
/// a set can only answer per-row membership. Asking "does this subtree's row
/// span touch any dirty row?" of a set costs O(span) or O(set); the only
/// span-shaped question a set answers cheaply is its convex hull, which is why
/// the paint walk historically culled on `(min, max)` alone. A one-cell clock
/// in row 0 plus a spinner in the last row therefore produced a hull covering
/// the whole screen, and every command on it re-resolved styles and re-laid out
/// text to write ~2 cells — the writes were dropped by the exact-set clamp in
/// ``Rasterizer/write(_:width:style:hyperlink:atX:y:cells:clip:blendMode:dirtyRows:presentationRecorder:presentationEffects:)``
/// only *after* the compute had already happened.
///
/// Spans keep both answers: O(log k) for a span test (binary search over k
/// coalesced bands) and the original hull for the cheap reject. The `Set` is
/// retained alongside this type for the per-row membership tests, where it is
/// already in scope and O(1) is the right cost.
internal struct DirtyRowSpans: Sendable, Equatable {
  /// Ascending, disjoint, non-empty, non-adjacent row spans.
  internal let spans: [Range<Int>]

  /// The convex hull of every dirty row — the band the paint walk used to cull
  /// on by itself. Retained as an O(1) pre-reject before the binary search.
  internal let hull: Range<Int>

  /// Builds the coalesced spans, or `nil` when no row is dirty (the caller
  /// falls back to a fresh raster in that case).
  internal init?(dirtyRows: Set<Int>) {
    guard !dirtyRows.isEmpty else {
      return nil
    }

    let sortedRows = dirtyRows.sorted()
    var spans: [Range<Int>] = []
    var spanStart = sortedRows[0]
    var spanEnd = sortedRows[0]

    for row in sortedRows.dropFirst() {
      if row == spanEnd + 1 {
        spanEnd = row
        continue
      }
      spans.append(spanStart..<(spanEnd + 1))
      spanStart = row
      spanEnd = row
    }
    spans.append(spanStart..<(spanEnd + 1))

    self.spans = spans
    self.hull = sortedRows[0]..<(spanEnd + 1)
  }

  /// Whether any dirty row falls inside the half-open row range `rows`.
  ///
  /// Restricted to the hull this is exactly the pre-existing band test, so a
  /// caller that swaps a hull check for this one can only ever cull *more*.
  internal func intersects(rows: Range<Int>) -> Bool {
    guard !rows.isEmpty else {
      return false
    }
    guard rows.lowerBound < hull.upperBound, rows.upperBound > hull.lowerBound else {
      return false
    }

    // First span that could still reach `rows`: the leftmost one whose end is
    // past `rows.lowerBound`. Every earlier span ends at or before it.
    var low = 0
    var high = spans.count
    while low < high {
      let middle = low + (high - low) / 2
      if spans[middle].upperBound <= rows.lowerBound {
        low = middle + 1
      } else {
        high = middle
      }
    }

    guard low < spans.count else {
      return false
    }
    return spans[low].lowerBound < rows.upperBound
  }

  /// Whether any dirty row falls inside `bounds`' row span. Column extent is
  /// irrelevant: every raster write path stays within a single row, so row
  /// containment alone decides whether painting `bounds` can reach a dirty row.
  internal func intersects(rows bounds: CellRect) -> Bool {
    guard bounds.size.height > 0 else {
      return false
    }
    return intersects(rows: bounds.origin.y..<(bounds.origin.y + bounds.size.height))
  }
}

extension DrawCommand {
  /// The row span outside which this command provably writes nothing, or `nil`
  /// when the command must not be culled as a whole.
  ///
  /// Every bounded painter writes only into its own `bounds` rows — the shape
  /// painters inset `bounds` before walking, the text family indexes lines as
  /// `bounds.origin.y + lineIndex` under a `prefix(bounds.size.height)`, and
  /// `.foreignSurface` clamps its row loop to `bounds.size.height`. No write
  /// path crosses rows: `write`, `tintCell`, and `clearExistingGlyph` all
  /// address `cells[y]` for a fixed `y`, reaching sideways at most to a wide
  /// glyph's continuation cell in the same row.
  ///
  /// Two cases deliberately opt out:
  ///
  /// - `.group` carries a bounds field, but nothing establishes it as a
  ///   superset of its children's bounds, so culling on it could drop a child
  ///   that reaches outside. The children are tested individually as they pop,
  ///   which costs one span test each and needs no such invariant.
  /// - `.image` keeps the exact-set guard at its own call site. That guard is
  ///   not an optimization: it must mirror the retained-attachment filter
  ///   *exactly* (F125) or an attachment overlapping only the dirty hull is
  ///   appended twice. Leaving one authority for that decision is the point.
  internal var culledRowBounds: CellRect? {
    switch self {
    case .text(let bounds, _, _, _, _, _),
      .preformattedText(let bounds, _, _),
      .styledPreformattedText(let bounds, _, _),
      .richText(let bounds, _, _, _, _),
      .fill(let bounds, _, _, _, _),
      .stroke(let bounds, _, _, _, _, _, _),
      .rule(let bounds, _, _, _),
      .border(let bounds, _, _, _, _, _, _),
      .canvas(let bounds, _, _),
      .foreignSurface(let bounds, _):
      return bounds
    case .clip(let bounds, _):
      // Everything the child paints is clipped to this rect, so a clip whose
      // rows miss the damage rejects the whole subcommand without descending.
      return bounds
    case .group, .image:
      return nil
    }
  }
}
