@_spi(Testing) import SwiftTUICore

/// The read/write face of a collection's stored scroll anchor, plus the
/// movement vocabulary its input handlers need.
///
/// Every mutation funnels through here — the wheel, the page/edge keys, the
/// selection follow, and the programmatic `ScrollViewProxy` route via
/// `registerScrollPosition` — so the layout functions stay pure over
/// (anchor, selection, viewport) and no phase product ever writes state. A
/// layout-time reveal that persisted itself is the invalidation-loop bug
/// class; input-time mutation avoids it by construction.
@MainActor
package struct CollectionScrollCurrency {
  package let identity: Identity
  private let estimatedGeometry: CollectionScrollGeometry
  private let ownerNode: SwiftTUICore.ViewNode?
  private let registry: LocalScrollPositionRegistry?
  /// The window the layout would show for a given viewport height with no
  /// anchor stored: its first display line (the selection-centred fallback)
  /// and how many lines are actually usable once overflow indicators and
  /// fixed chrome take their share. The offset is consulted while no anchor is
  /// stored, so the first gesture continues from where the user is actually
  /// looking instead of snapping to the top; the line count is what `reveal`
  /// measures "already visible" against. It receives the viewport height and
  /// the row geometry in use, so a fallback offset maps to display lines the
  /// way the layout does.
  private let windowMetrics:
    @MainActor (Int, CollectionScrollGeometry) -> (offset: Int, visibleLineCount: Int)
  /// The fewest display lines one row can take. A table row whose following
  /// separator is hidden takes a single line, although the estimated stride
  /// of an unmeasured table row is two.
  private let minimumRowLineSpan: Int

  /// `minimumRowLineSpan` defaults to the estimated geometry's stride.
  package init(
    identity: Identity,
    geometry: CollectionScrollGeometry,
    ownerNode: SwiftTUICore.ViewNode?,
    registry: LocalScrollPositionRegistry?,
    minimumRowLineSpan: Int? = nil,
    windowMetrics:
      @escaping @MainActor (Int, CollectionScrollGeometry) -> (
        offset: Int, visibleLineCount: Int
      )
  ) {
    self.identity = identity
    estimatedGeometry = geometry
    self.ownerNode = ownerNode
    self.registry = registry
    self.minimumRowLineSpan = max(1, minimumRowLineSpan ?? geometry.rowSpan)
    self.windowMetrics = windowMetrics
  }

  private var layout: CollectionScrollLayout? {
    guard let layout = registry?.collectionScrollLayout(scopeIdentity: identity),
      layout.geometry.rowCount == estimatedGeometry.rowCount
    else { return nil }
    return layout
  }

  package var geometry: CollectionScrollGeometry {
    layout?.geometry ?? estimatedGeometry
  }

  package var storedAnchor: CollectionScrollAnchor? {
    storedCollectionScrollAnchor(in: ownerNode)
  }

  /// The current row, after layout has fitted the requested anchor to its
  /// measured viewport. Before that frame, use the latest known extent.
  package var effectiveAnchorRow: Int {
    if let layout, layout.anchor == storedAnchor {
      if case .position = storedAnchor {
        return geometry.row(atOrBeforeLine: layout.visibleLines.lowerBound)
      }
      // Whole-row fitting may leave a separator at the top of a table. The
      // following row, not the row before that separator, starts this window.
      return geometry.row(atOrAfterLine: layout.visibleLines.lowerBound)
    }
    if let storedAnchor {
      if case .position = storedAnchor {
        return storedAnchor.rowIndex(rowCount: geometry.rowCount)
      }
      return min(storedAnchor.rowIndex(rowCount: geometry.rowCount), maxAnchorRow)
    }
    return geometry.row(atOrBeforeLine: windowMetrics(viewportLineCount, geometry).offset)
  }

  /// The viewport height published for this collection's scroll route, or 0
  /// before the first geometry sync (frame 1).
  package var viewportLineCount: Int {
    registry?.viewportRect(scopeIdentity: identity)?.size.height ?? 0
  }

  /// The largest anchor row that still fills the window. The geometry counts
  /// the known row heights; layout also accounts for interleaved chrome and
  /// whole-row fitting at the bottom of the viewport. While the stored anchor
  /// selects a window the layout has not measured, a projected geometry
  /// (``projectedGeometry()``) is the better estimate of the content's end.
  private var maxAnchorRow: Int {
    if layout?.anchor != storedAnchor, let projected = projectedGeometry() {
      return projected.maxAnchorRow(viewportLineCount: visibleLineCount)
    }
    return registry?.collectionMaximumAnchorRow(scopeIdentity: identity)
      ?? geometry.maxAnchorRow(viewportLineCount: visibleLineCount)
  }

  /// The display lines the window can actually show. This is the number every
  /// extent decision must use — the raw viewport over-counts by whatever the
  /// overflow indicators and fixed chrome consume, and clamping the anchor
  /// against the raw height leaves the last rows of the dataset unreachable.
  package var visibleLineCount: Int {
    if let layout { return layout.visibleLines.count }
    let viewport = viewportLineCount
    guard viewport > 0 else {
      return 0
    }
    return max(1, windowMetrics(viewport, geometry).visibleLineCount)
  }

  /// The rows the window shows, by each row's real line span: tall rows and
  /// hidden table separators included. Interaction bands size from this, and
  /// review pages from ``pageRowCount``. `visibleLineCount / rowSpan` halves
  /// the rows of a table that hides its separators (STUI-1239).
  ///
  /// When the published layout measured the window that the stored anchor
  /// still selects, its geometry is exact. Otherwise this frame places a
  /// window over rows the layout has not measured, which the geometry only
  /// estimates. The count then bounds what such a window can show: one row
  /// per `minimumRowLineSpan` lines.
  package var visibleRowCount: Int {
    let lines = visibleLineCount
    guard lines > 0, geometry.rowCount > 0 else { return 0 }
    if let layout, layout.anchor == storedAnchor, !layout.visibleLines.isEmpty {
      let first = layout.geometry.row(atOrBeforeLine: layout.visibleLines.lowerBound)
      let last = layout.geometry.row(atOrBeforeLine: layout.visibleLines.upperBound - 1)
      return max(1, last - first + 1)
    }
    return min(geometry.rowCount, (lines + minimumRowLineSpan - 1) / minimumRowLineSpan)
  }

  /// The rows a page moves by, plus the row of overlap: the rows the window
  /// shows (STUI-1262). When the layout measured the window the stored anchor
  /// selects, this is the exact ``visibleRowCount``. Otherwise the window is
  /// estimated from the movement geometry rather than bounded, because a page
  /// that over-counts skips rows where a band that over-counts is harmless.
  package var pageRowCount: Int {
    let lines = visibleLineCount
    guard lines > 0, geometry.rowCount > 0 else { return 0 }
    if let layout, layout.anchor == storedAnchor { return visibleRowCount }
    let window = movementWindow()
    let geometry = window.geometry
    let last = geometry.row(
      atOrBeforeLine: min(window.anchorLine + lines, geometry.displayLineCount) - 1)
    return max(1, last - geometry.row(atOrAfterLine: window.anchorLine) + 1)
  }

  /// The geometry page and reveal arithmetic estimates unmeasured rows with.
  /// Rows the layout has not measured are estimated at the table's drawn
  /// stride of two lines. When every visible row of the measured window hides
  /// its separator, a row that has not been measured is estimated to hide its
  /// separator as well, so keys applied before a frame measures their rows
  /// move as far as the same keys one frame at a time (STUI-1316). Nil keeps
  /// the published geometry: a list, a table with drawn or mixed separators,
  /// or no layout yet.
  private func projectedGeometry() -> CollectionScrollGeometry? {
    guard minimumRowLineSpan < estimatedGeometry.rowSpan, let layout,
      !layout.visibleLines.isEmpty
    else { return nil }
    let geometry = layout.geometry
    let first = geometry.row(atOrAfterLine: layout.visibleLines.lowerBound)
    let last = min(
      geometry.row(atOrBeforeLine: layout.visibleLines.upperBound - 1), geometry.lastRowIndex - 1)
    guard first <= last, geometry.hidesFollowingSeparators(ofRows: first...last) else {
      return nil
    }
    return geometry.estimatingUnmeasuredSeparatorsHidden()
  }

  /// The window's first row and line in the geometry movement arithmetic
  /// uses. A projected geometry numbers lines differently before unmeasured
  /// rows, so a measured window is carried over through its first row, and an
  /// unmeasured one is placed from the stored anchor directly.
  private func movementWindow() -> (
    geometry: CollectionScrollGeometry, anchorRow: Int, anchorLine: Int
  ) {
    guard let projected = projectedGeometry() else {
      return (geometry, effectiveAnchorRow, currentOffset().y)
    }
    let row = effectiveAnchorRow
    if let layout, layout.anchor == storedAnchor {
      let lineOffset = layout.visibleLines.lowerBound - layout.geometry.line(forRow: row)
      return (projected, row, max(0, projected.line(forRow: row) + lineOffset))
    }
    return (projected, row, windowTop(in: projected, maxAnchorRow: maxAnchorRow))
  }

  /// The first display line of the window the stored anchor selects, laid
  /// out over `geometry`.
  private func windowTop(in geometry: CollectionScrollGeometry, maxAnchorRow: Int) -> Int {
    switch storedAnchor {
    case .start: return 0
    case .end: return max(0, geometry.displayLineCount - visibleLineCount)
    case .row(let index): return geometry.line(forRow: min(index, maxAnchorRow))
    case .position:
      return geometry.positionedOffset(for: storedAnchor, capacity: visibleLineCount) ?? 0
    case nil: return windowMetrics(viewportLineCount, geometry).offset
    }
  }

  /// Capture the initial window before selection starts following it.
  @discardableResult
  package func pinCurrentAnchor() -> Bool {
    guard storedAnchor == nil else { return false }
    let offset = currentOffset().y
    return setAnchorLine(offset)
  }

  package func currentOffset() -> ScrollOffset {
    if let layout, layout.anchor == storedAnchor {
      return ScrollOffset(y: layout.visibleLines.lowerBound)
    }
    return ScrollOffset(y: windowTop(in: geometry, maxAnchorRow: maxAnchorRow))
  }

  package func applyOffset(_ offset: ScrollOffset) {
    if offset.y <= 0 {
      _ = setAnchor(.start)
    } else if visibleLineCount > 0,
      offset.y >= max(0, geometry.displayLineCount - visibleLineCount)
    {
      _ = setAnchor(.end)
    } else {
      _ = setAnchorLine(offset.y)
    }
  }

  @discardableResult
  private func setAnchor(_ anchor: CollectionScrollAnchor) -> Bool {
    guard storedAnchor != anchor else { return false }
    setStoredCollectionScrollAnchor(anchor, in: ownerNode, invalidationIdentity: identity)
    return true
  }

  @discardableResult
  package func setAnchorRow(_ rowIndex: Int) -> Bool {
    let row = min(max(0, rowIndex), geometry.lastRowIndex)
    return setAnchor(.row(row))
  }

  private func setAnchorLine(_ line: Int) -> Bool {
    if line <= 0 { return setAnchor(.start) }
    if visibleLineCount > 0, line >= geometry.displayLineCount - visibleLineCount {
      return setAnchor(.end)
    }
    let row = geometry.row(atOrBeforeLine: line)
    let offset = line - geometry.line(forRow: row)
    return offset == 0
      ? setAnchorRow(row) : setAnchor(.position(row: row, lineOffset: offset))
  }

  /// Moves the anchor by whole rows.
  ///
  /// The wheel and page keys move in rows rather than cells so the top of the
  /// viewport always lands on a row boundary in both directions. A one-cell
  /// delta at `rowSpan == 2` rounds back onto the same row going up and jams
  /// the scroll.
  @discardableResult
  package func scroll(byRows rows: Int) -> Bool {
    guard rows != 0 else {
      return false
    }
    // A footer-only end window is one position beyond the final row. Count
    // it separately when reversing so that row is not skipped in either direction.
    let current = effectiveAnchorRow
    let startsAfterLastRow =
      currentOffset().y >= geometry.lineRange(forRow: geometry.lastRowIndex).upperBound
    // Wheel deltas come from hosts unbounded; saturate instead of trapping.
    let destination = SaturatingConversion.adding(
      SaturatingConversion.adding(current, rows), rows < 0 && startsAfterLastRow ? 1 : 0)
    if destination < 0 { return setAnchor(.start) }
    if destination > maxAnchorRow { return setAnchor(.end) }
    if visibleLineCount > 0, geometry.displayLineCount > visibleLineCount,
      geometry.line(forRow: destination) >= geometry.displayLineCount - visibleLineCount
    {
      return setAnchor(.end)
    }
    return setAnchorRow(destination)
  }

  @discardableResult
  package func page(by pages: Int) -> Bool {
    guard pages != 0 else {
      return false
    }
    let visible = visibleLineCount
    guard visible > 0 else {
      // Frame 1 has no synced geometry; a page is at least one row so the
      // keypress still moves rather than reading as inert.
      return scroll(byRows: pages)
    }
    // Preserve a line of overlap where whole-row fitting permits it. Round
    // toward the current page so a tall row is not skipped between pages.
    let window = movementWindow()
    let geometry = window.geometry
    let current = window.anchorRow
    let offset = window.anchorLine
    let startsAfterLastRow =
      offset >= geometry.lineRange(forRow: geometry.lastRowIndex).upperBound
    if pages < 0, !startsAfterLastRow, offset > geometry.line(forRow: current) {
      // An exact end can begin inside the final row. Visit that row's start
      // before the preceding row, just as a footer-only window does.
      return setAnchorRow(current)
    }
    let currentLine = startsAfterLastRow ? offset : geometry.line(forRow: current)
    let destination = currentLine + pages * max(1, visible - 1)
    let target =
      pages > 0
      ? max(current + 1, geometry.row(atOrBeforeLine: destination))
      : min(current - (startsAfterLastRow ? 0 : 1), geometry.row(atOrAfterLine: destination))
    if target < 0 { return setAnchor(.start) }
    if target > geometry.lastRowIndex { return setAnchor(.end) }
    return setAnchorRow(target)
  }

  @discardableResult
  package func scroll(toEdge edge: Edge) -> Bool {
    switch edge {
    case .top:
      return setAnchor(.start)
    case .bottom:
      return setAnchor(.end)
    case .leading, .trailing:
      return false
    }
  }

  /// Moves the anchor the minimum distance that brings `rowIndex` into view
  /// with `margin` rows of context beyond it, and not at all when it is
  /// already that far inside the window. This is what makes a selection step
  /// *follow* the window instead of recentring it.
  ///
  /// Context is bounded by the space left after the target row. Oversized
  /// rows align at their start rather than alternating between their edges.
  @discardableResult
  package func reveal(
    row rowIndex: Int,
    margin: Int = 1
  ) -> Bool {
    let visibleLines = visibleLineCount
    guard visibleLines > 0 else {
      // Nothing to measure "visible" against on frame 1; the next frame
      // reveals precisely once geometry syncs.
      return false
    }
    let window = movementWindow()
    let geometry = window.geometry
    let target = min(max(0, rowIndex), geometry.lastRowIndex)
    let targetLines = geometry.lineRange(forRow: target)
    let anchorLine = window.anchorLine
    let contextLimit = max(0, (visibleLines - targetLines.count) / 2)
    let firstContextRow = max(0, target - max(0, margin))
    let lastContextRow = min(geometry.lastRowIndex, target + max(0, margin))
    let precedingContext = min(
      contextLimit, targetLines.lowerBound - geometry.line(forRow: firstContextRow))
    let followingContext = min(
      contextLimit, geometry.lineRange(forRow: lastContextRow).upperBound - targetLines.upperBound)
    let firstLine = max(0, targetLines.lowerBound - precedingContext)
    if firstLine < anchorLine {
      // Rounding into a tall preceding row could consume the space reserved
      // for the target. Omit context that cannot fit as a whole row.
      return setAnchorRow(geometry.row(atOrAfterLine: firstLine))
    }
    if targetLines.upperBound + followingContext > anchorLine + visibleLines {
      let firstVisibleLine = min(
        targetLines.lowerBound, max(0, targetLines.upperBound + followingContext - visibleLines))
      return setAnchorRow(geometry.row(atOrAfterLine: firstVisibleLine))
    }
    return false
  }

  /// Answers a `scrollTo(_:)` query for a row this collection owns, including
  /// rows that were never realized and so have no placed frame. Returns `nil`
  /// when the query matches no row, so the registry keeps looking.
  ///
  /// The collection performs the move itself rather than reporting a rect: its
  /// usable window is smaller than its raw viewport (overflow indicators,
  /// fixed table chrome), and the registry's offset arithmetic is written
  /// against the raw rect.
  package func revealTarget(
    for query: ScrollTargetQuery,
    anchor: UnitPoint?,
    resolvingRow: (ScrollTargetQuery) -> Int?
  ) -> Bool? {
    guard let rowIndex = resolvingRow(query) else {
      return nil
    }
    // A non-finite anchor is ignored, as if no anchor were given.
    guard let anchor, anchor.x.isFinite, anchor.y.isFinite else {
      return reveal(row: rowIndex)
    }
    // An explicit unit anchor positions the row rather than merely revealing
    // it: 0 pins it to the top of the window, 1 to the bottom.
    let visible = visibleLineCount
    guard visible > 0 else {
      return setAnchorRow(rowIndex)
    }
    let targetLines = geometry.lineRange(forRow: rowIndex)
    let offsetLines = SaturatingConversion.int(
      Double(max(0, visible - targetLines.count)) * anchor.y, rounding: .toNearestOrAwayFromZero)
    return setAnchorLine(max(0, targetLines.lowerBound - offsetLines))
  }
}

private let collectionScrollAnchorStateSlot = StateSlotOrdinals.collectionScrollAnchor

@MainActor
package func storedCollectionScrollAnchor(
  in ownerNode: SwiftTUICore.ViewNode?
) -> CollectionScrollAnchor? {
  withPersistentDormantStateSlot {
    ownerNode?.stateSlot(
      ordinal: collectionScrollAnchorStateSlot,
      seed: nil as CollectionScrollAnchor?
    ) ?? nil
  }
}

@MainActor
package func setStoredCollectionScrollAnchor(
  _ anchor: CollectionScrollAnchor?,
  in ownerNode: SwiftTUICore.ViewNode?,
  invalidationIdentity: Identity? = nil
) {
  withPersistentDormantStateSlot {
    ownerNode?.setStateSlot(
      ordinal: collectionScrollAnchorStateSlot,
      value: anchor,
      invalidationIdentity: invalidationIdentity
    )
  }
}

/// Maps a key event to a scroll movement on a collection, mirroring the
/// vocabulary `ScrollView` already answers to. Returns `false` for keys the
/// collection does not own so selection handling still sees them.
@MainActor
package func applyCollectionScrollKey(
  _ event: KeyEvent,
  to currency: CollectionScrollCurrency
) -> Bool {
  switch event {
  case .pageDown:
    return currency.page(by: 1)
  case .pageUp:
    return currency.page(by: -1)
  case .home:
    return currency.scroll(toEdge: .top)
  case .end:
    return currency.scroll(toEdge: .bottom)
  default:
    return false
  }
}
