/// Row geometry and the usable viewport from the same layout pass. The range
/// uses body display-line coordinates and excludes fixed chrome and indicators.
package struct CollectionScrollLayout: Equatable, Sendable {
  package let geometry: CollectionScrollGeometry
  package let visibleLines: Range<Int>
  package let anchor: CollectionScrollAnchor?
  /// The rows a windowed generation realized when the layout's bounds are
  /// the whole content: inside a `ScrollView`, the rows the enclosing
  /// viewport declares, plus overscan. `visibleLines` is then the whole body.
  /// `nil` when the layout's own window is the viewport.
  package let realizedRows: Range<Int>?

  package init(
    geometry: CollectionScrollGeometry,
    visibleLines: Range<Int>,
    anchor: CollectionScrollAnchor? = nil,
    realizedRows: Range<Int>? = nil
  ) {
    self.geometry = geometry
    self.visibleLines = visibleLines
    self.anchor = anchor
    self.realizedRows = realizedRows
  }

  /// The rows with a line in `visibleLines`. A separator line that starts
  /// the window belongs to no row, so the row above it is not shown; a row
  /// that the window starts inside is (STUI-1312).
  package var shownRows: Range<Int>? {
    guard geometry.rowCount > 0, !visibleLines.isEmpty else { return nil }
    var first = geometry.row(atOrBeforeLine: visibleLines.lowerBound)
    if geometry.lineRange(forRow: first).upperBound <= visibleLines.lowerBound,
      first < geometry.lastRowIndex
    {
      first += 1
    }
    let last = max(first, geometry.row(atOrBeforeLine: visibleLines.upperBound - 1))
    return first..<(last + 1)
  }

  /// The rows an interaction band must cover for this layout: the realized
  /// rows inside a `ScrollView`, otherwise the shown rows.
  package var interactionRows: Range<Int>? {
    if let realizedRows, !realizedRows.isEmpty { return realizedRows }
    return shownRows
  }
}

extension ScrollRoute {
  /// Whether this frame's collection layout shows rows outside the
  /// interaction band its collection registered at resolve. The band is
  /// sized from the previous frame's layout, so a resize, a sibling's layout
  /// change or an enclosing scroll view's scroll can leave rows on screen
  /// without a row action or pointer route (STUI-1315, STUI-1321).
  package var collectionInteractionBandIsStale: Bool {
    guard let band = collectionInteractionRows,
      let rows = collectionScrollLayout?.interactionRows
    else { return false }
    return rows.lowerBound < band.lowerBound || rows.upperBound > band.upperBound
  }
}
