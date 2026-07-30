@_spi(Testing) import SwiftTUICore

/// The scroll currency of a collection: the dataset row pinned to the top of
/// the viewport, from which the visible window is derived.
///
/// Before this existed the window was recomputed every frame as
/// `clamp(selectedRowIndex − visibleLineCount / 2)`, which made "what is
/// selected" and "where am I looking" the same variable — a non-selectable
/// collection could not scroll at all, and every selection change dragged the
/// viewport with it. Storing the anchor separates the two: selection now
/// *follows* the window instead of *being* it.
package struct CollectionScrollAnchor: Equatable, Sendable {
  /// The dataset row index pinned to the top of the viewport.
  package var firstVisibleItemIndex: Int
  /// How many display lines into that row the viewport starts. Always 0 while
  /// every row occupies one display line; the field exists so the currency
  /// keeps its shape once real per-row heights land.
  package var intraItemLineOffset: Int

  package init(
    firstVisibleItemIndex: Int,
    intraItemLineOffset: Int = 0
  ) {
    self.firstVisibleItemIndex = firstVisibleItemIndex
    self.intraItemLineOffset = intraItemLineOffset
  }
}

/// The display-line arithmetic of a collection body: how many lines one row
/// occupies (2 when the style draws row separators) and how many chrome lines
/// precede row 0.
///
/// For the materialized (non-viewport-backed) list path this model is an
/// under-estimate — interleaved headers, footers, and section separators add
/// lines it does not count. That direction is deliberate: it makes every
/// derived extent conservative, so the anchor can never be stored past the
/// true end of the content, which is what would make reverse scrolling spin
/// before the viewport moves.
package struct CollectionScrollGeometry: Equatable, Sendable {
  package var rowCount: Int
  package var rowSpan: Int
  package var chromeInset: Int

  package init(
    rowCount: Int,
    rowSpan: Int,
    chromeInset: Int
  ) {
    self.rowCount = max(0, rowCount)
    self.rowSpan = max(1, rowSpan)
    self.chromeInset = max(0, chromeInset)
  }

  package var displayLineCount: Int {
    guard rowCount > 0 else {
      return chromeInset
    }
    return chromeInset + rowCount * rowSpan - (rowSpan - 1)
  }

  package var lastRowIndex: Int {
    max(0, rowCount - 1)
  }

  package func line(forRow rowIndex: Int) -> Int {
    chromeInset + min(max(0, rowIndex), lastRowIndex) * rowSpan
  }

  /// The first row at or after `line` — the row that is fully visible when the
  /// viewport starts there. Reveal-shaped conversions round this way so a
  /// partially covered row is never reported as the anchor.
  package func row(atOrAfterLine line: Int) -> Int {
    let body = max(0, line - chromeInset)
    return min((body + rowSpan - 1) / rowSpan, lastRowIndex)
  }

  /// The last row at or before `line`. Extent maths rounds this way; rounding
  /// up would let the anchor overshoot the end of the dataset.
  package func row(atOrBeforeLine line: Int) -> Int {
    let body = max(0, line - chromeInset)
    return min(body / rowSpan, lastRowIndex)
  }

  /// The largest anchor row that still fills a `viewportLineCount`-line
  /// viewport. Without synced geometry the dataset bound is the only clamp.
  package func maxAnchorRow(viewportLineCount: Int) -> Int {
    guard viewportLineCount > 0 else {
      return lastRowIndex
    }
    return row(atOrBeforeLine: max(0, displayLineCount - viewportLineCount))
  }
}

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
  package let geometry: CollectionScrollGeometry
  private let ownerNode: SwiftTUICore.ViewNode?
  private let registry: LocalScrollPositionRegistry?
  /// The window the layout would show for a given viewport height with no
  /// anchor stored: its first display line (the selection-centred fallback)
  /// and how many lines are actually usable once overflow indicators and
  /// fixed chrome take their share. The offset is consulted while no anchor is
  /// stored, so the first gesture continues from where the user is actually
  /// looking instead of snapping to the top; the line count is what `reveal`
  /// measures "already visible" against.
  private let windowMetrics: @MainActor (Int) -> (offset: Int, visibleLineCount: Int)

  package init(
    identity: Identity,
    geometry: CollectionScrollGeometry,
    ownerNode: SwiftTUICore.ViewNode?,
    registry: LocalScrollPositionRegistry?,
    windowMetrics: @escaping @MainActor (Int) -> (offset: Int, visibleLineCount: Int)
  ) {
    self.identity = identity
    self.geometry = geometry
    self.ownerNode = ownerNode
    self.registry = registry
    self.windowMetrics = windowMetrics
  }

  /// The stored anchor row clamped into the live dataset, or `nil` when
  /// nothing has scrolled this collection yet.
  package var storedAnchorRow: Int? {
    storedCollectionScrollAnchor(in: ownerNode).map { anchor in
      min(max(0, anchor.firstVisibleItemIndex), geometry.lastRowIndex)
    }
  }

  /// The row currently at the top of the viewport, from the stored anchor or —
  /// before anything has scrolled — from the selection-centred fallback the
  /// layout still applies.
  package var effectiveAnchorRow: Int {
    if let storedAnchorRow {
      return storedAnchorRow
    }
    return geometry.row(atOrBeforeLine: windowMetrics(viewportLineCount).offset)
  }

  /// The viewport height published for this collection's scroll route, or 0
  /// before the first geometry sync (frame 1).
  package var viewportLineCount: Int {
    registry?.viewportRect(scopeIdentity: identity)?.size.height ?? 0
  }

  /// The display lines the window can actually show. This is the number every
  /// extent decision must use — the raw viewport over-counts by whatever the
  /// overflow indicators and fixed chrome consume, and clamping the anchor
  /// against the raw height leaves the last rows of the dataset unreachable.
  package var visibleLineCount: Int {
    let viewport = viewportLineCount
    guard viewport > 0 else {
      return 0
    }
    return max(1, windowMetrics(viewport).visibleLineCount)
  }

  /// Writes the currently-shown top row into the slot when nothing is stored
  /// yet, so the window stops silently tracking the selection.
  ///
  /// Without this, a selection move while the anchor is still `nil` would be
  /// re-centred by the fallback no matter how minimal `reveal` was: the
  /// fallback *is* the selection. Pinning at the moment of the first
  /// selection-moving keypress is what makes "selection follows the window"
  /// true from the very first arrow press, while leaving a purely
  /// re-rendered payload (no interaction) on the historical path.
  @discardableResult
  package func pinCurrentAnchor() -> Bool {
    guard storedAnchorRow == nil else {
      return false
    }
    setStoredCollectionScrollAnchor(
      CollectionScrollAnchor(firstVisibleItemIndex: effectiveAnchorRow),
      in: ownerNode,
      invalidationIdentity: identity
    )
    return true
  }

  package func currentOffset() -> ScrollOffset {
    ScrollOffset(y: geometry.line(forRow: effectiveAnchorRow))
  }

  package func applyOffset(_ offset: ScrollOffset) {
    setAnchorRow(geometry.row(atOrAfterLine: offset.y))
  }

  @discardableResult
  package func setAnchorRow(_ rowIndex: Int) -> Bool {
    let clamped = min(
      max(0, rowIndex),
      geometry.maxAnchorRow(viewportLineCount: visibleLineCount)
    )
    guard clamped != effectiveAnchorRow else {
      return false
    }
    setStoredCollectionScrollAnchor(
      CollectionScrollAnchor(firstVisibleItemIndex: clamped),
      in: ownerNode,
      invalidationIdentity: identity
    )
    return true
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
    return setAnchorRow(effectiveAnchorRow + rows)
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
    // One line of overlap between pages, the usual pager convention.
    let rows = max(1, max(1, visible - 1) / geometry.rowSpan)
    return scroll(byRows: pages * rows)
  }

  @discardableResult
  package func scroll(toEdge edge: Edge) -> Bool {
    switch edge {
    case .top:
      return setAnchorRow(0)
    case .bottom:
      return setAnchorRow(geometry.lastRowIndex)
    case .leading, .trailing:
      return false
    }
  }

  /// Moves the anchor the minimum distance that brings `rowIndex` into view
  /// with `margin` rows of context beyond it, and not at all when it is
  /// already that far inside the window. This is what makes a selection step
  /// *follow* the window instead of recentring it.
  ///
  /// The margin is not cosmetic. Focus regions are published from the
  /// committed frame, so a row must already be drawn before focus can move
  /// onto it. Revealing with zero margin parks the selected row exactly on the
  /// window edge, leaving its neighbour undrawn — and the next arrow press
  /// then walks focus straight out of the collection instead of stepping to
  /// that row. One row of context is the smallest margin that keeps row
  /// navigation closed over the collection.
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
    let target = min(max(0, rowIndex), geometry.lastRowIndex)
    let targetLine = geometry.line(forRow: target)
    let anchorLine = geometry.line(forRow: effectiveAnchorRow)
    // A margin wider than the window would thrash; keep at least the target
    // itself visible.
    let marginLines = min(
      max(0, margin) * geometry.rowSpan,
      max(0, (visibleLines - geometry.rowSpan) / 2)
    )
    if targetLine - marginLines < anchorLine {
      return setAnchorRow(geometry.row(atOrBeforeLine: max(0, targetLine - marginLines)))
    }
    if targetLine + geometry.rowSpan + marginLines > anchorLine + visibleLines {
      return setAnchorRow(
        geometry.row(
          atOrAfterLine: max(0, targetLine + geometry.rowSpan + marginLines - visibleLines)
        )
      )
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
    guard let anchor else {
      return reveal(row: rowIndex)
    }
    // An explicit unit anchor positions the row rather than merely revealing
    // it: 0 pins it to the top of the window, 1 to the bottom.
    let visible = visibleLineCount
    guard visible > 0 else {
      return setAnchorRow(rowIndex)
    }
    let targetLine = geometry.line(forRow: rowIndex)
    let offsetLines = Int((Double(max(0, visible - geometry.rowSpan)) * anchor.y).rounded())
    return setAnchorRow(geometry.row(atOrAfterLine: max(0, targetLine - offsetLines)))
  }
}

private let collectionScrollAnchorStateSlot = StateSlotOrdinals.collectionScrollAnchor

@MainActor
package func storedCollectionScrollAnchor(
  in ownerNode: SwiftTUICore.ViewNode?
) -> CollectionScrollAnchor? {
  ownerNode?.stateSlot(
    ordinal: collectionScrollAnchorStateSlot,
    seed: nil as CollectionScrollAnchor?
  ) ?? nil
}

@MainActor
package func setStoredCollectionScrollAnchor(
  _ anchor: CollectionScrollAnchor?,
  in ownerNode: SwiftTUICore.ViewNode?,
  invalidationIdentity: Identity? = nil
) {
  ownerNode?.setStateSlot(
    ordinal: collectionScrollAnchorStateSlot,
    value: anchor,
    invalidationIdentity: invalidationIdentity
  )
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
