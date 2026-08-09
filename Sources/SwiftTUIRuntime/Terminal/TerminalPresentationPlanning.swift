import SwiftTUICore

struct TerminalPresentationPlan: Sendable {
  struct GraphicsReplayPlan: Equatable, Sendable {
    enum Scope: String, Equatable, Sendable {
      case none
      case targeted
      case full
    }

    var scope: Scope
    var attachmentsToReplay: [RasterImageAttachment]

    static let none = Self(
      scope: .none,
      attachmentsToReplay: []
    )
  }

  struct SpanUpdate: Equatable, Sendable {
    var row: Int
    var column: Int
    var renderedSpan: String
    var cellsChanged: Int
  }

  struct RowBatch: Equatable, Sendable {
    var row: Int
    var anchorColumn: Int
    var renderedBatch: String
    var spanUpdates: [SpanUpdate]

    var cellsChanged: Int {
      spanUpdates.reduce(0) { $0 + $1.cellsChanged }
    }

    func canLowerToEraseToEndOfLine(
      surfaceWidth: Int
    ) -> Bool {
      guard
        spanUpdates.count == 1,
        let span = spanUpdates.first,
        renderedBatch == span.renderedSpan,
        span.column == anchorColumn,
        span.column + span.cellsChanged >= surfaceWidth,
        !span.renderedSpan.isEmpty
      else {
        return false
      }

      return span.renderedSpan.allSatisfy { $0 == " " }
    }
  }

  enum Strategy: String, Equatable, Sendable {
    case fullRepaint
    case incremental
  }

  /// A verified scroll-region translation emitted as a prefix on an
  /// incremental plan: DECSTBM over `topRow...bottomRow`, SU/SD by `delta`,
  /// region reset, cursor re-home — then the plan's ordinary row batches
  /// repaint exposed rows and any in-band mismatches.
  ///
  /// The operation exists only when the planner proved, cell-for-cell, that
  /// shifting the previously written band by `delta` plus the accompanying
  /// row batches reproduces the current surface exactly.
  struct ScrollRegionOperation: Equatable, Sendable {
    /// First surface row of the DECSTBM region (0-based, inclusive).
    var topRow: Int
    /// Last surface row of the DECSTBM region (0-based, inclusive).
    var bottomRow: Int
    /// Screen rows the region content moves: negative scrolls the content up
    /// (SU, blank rows appear at the region bottom), positive scrolls it
    /// down (SD, blank rows appear at the region top). Same sign convention
    /// as ``ScrollTranslationCandidate/dy``.
    var delta: Int
  }

  var strategy: Strategy
  var rowBatches: [RowBatch]
  var graphicsReplay: GraphicsReplayPlan
  var surfaceSize: CellSize
  var scrollRegion: ScrollRegionOperation?

  static func fullRepaint(
    surfaceSize: CellSize
  ) -> Self {
    Self(
      strategy: .fullRepaint,
      rowBatches: [],
      graphicsReplay: .none,
      surfaceSize: surfaceSize,
      scrollRegion: nil
    )
  }

  static func incremental(
    rowBatches: [RowBatch],
    graphicsReplay: GraphicsReplayPlan,
    surfaceSize: CellSize,
    scrollRegion: ScrollRegionOperation? = nil
  ) -> Self {
    Self(
      strategy: .incremental,
      rowBatches: rowBatches,
      graphicsReplay: graphicsReplay,
      surfaceSize: surfaceSize,
      scrollRegion: scrollRegion
    )
  }

  var spanUpdates: [SpanUpdate] {
    rowBatches.flatMap(\.spanUpdates)
  }

  var linesTouched: Int {
    switch strategy {
    case .fullRepaint:
      surfaceSize.height
    case .incremental:
      Set(rowBatches.map(\.row)).count
    }
  }

  var cellsChanged: Int {
    switch strategy {
    case .fullRepaint:
      max(0, surfaceSize.width) * max(0, surfaceSize.height)
    case .incremental:
      rowBatches.reduce(0) { $0 + $1.cellsChanged }
    }
  }
}

struct TerminalPresentationPlanner {
  let capabilityProfile: TerminalCapabilityProfile
  let graphicsCapabilities: TerminalGraphicsCapabilities
  let terminalBackgroundColor: Color?

  init(
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities = .none,
    terminalBackgroundColor: Color? = nil
  ) {
    self.capabilityProfile = capabilityProfile
    self.graphicsCapabilities = graphicsCapabilities
    self.terminalBackgroundColor = terminalBackgroundColor
  }

  /// Row-share of a candidate band that may mismatch under translation
  /// before the scroll-region path abandons the frame wholesale: past this,
  /// the "translate then patch the differences" emission stops being cheaper
  /// than the plain row diff it replaces.
  static let scrollRegionMismatchFallbackShare = 0.25

  /// Band-share the damage hint must reach before the scroll-region path is
  /// attempted at all. The full-band verify costs real planner time
  /// (~0.5 ms on an 80×32 styled band), so narrow hints — uniform
  /// collections whose consecutive rows differ in a few digit cells — keep
  /// the plain diff. Chosen from measured hint distributions: the
  /// heterogeneous-document shape hints ≥ ~20% of its band, the uniform
  /// shapes ≤ ~4%; 15% separates them with margin on both sides.
  static let scrollRegionHintAttemptShare = 0.15

  func plan(
    previousSurface: RasterSurface?,
    currentSurface: RasterSurface,
    damage: PresentationDamage? = nil,
    translationCandidate: ScrollTranslationCandidate? = nil
  ) -> TerminalPresentationPlan {
    guard let previousSurface,
      previousSurface.size == currentSurface.size,
      previousSurface.attachments == currentSurface.attachments,
      previousSurface.metadata == currentSurface.metadata
    else {
      return .fullRepaint(
        surfaceSize: currentSurface.size
      )
    }

    let supportsIncrementalGraphicsReplay = graphicsCapabilities.preferredProtocol == .kitty
    if previousSurface.imageAttachments != currentSurface.imageAttachments,
      !supportsIncrementalGraphicsReplay
    {
      return .fullRepaint(
        surfaceSize: currentSurface.size
      )
    }

    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile,
      terminalBackgroundColor: terminalBackgroundColor
    )

    let rowCount = max(
      max(previousSurface.cells.count, currentSurface.cells.count),
      currentSurface.size.height
    )

    if let translationCandidate,
      capabilityProfile.supportsScrollRegions,
      let scrollRegionPlan = scrollRegionPlan(
        for: translationCandidate,
        previousSurface: previousSurface,
        currentSurface: currentSurface,
        damage: damage,
        renderer: renderer,
        rowCount: rowCount
      )
    {
      return scrollRegionPlan
    }

    var rowBatches: [TerminalPresentationPlan.RowBatch] = []
    appendDiffedRowBatches(
      rows: rowsToDiff(damage: damage, rowCount: rowCount),
      previousSurface: previousSurface,
      currentSurface: currentSurface,
      damage: damage,
      renderer: renderer,
      to: &rowBatches
    )

    let graphicsReplay = graphicsReplayPlan(
      previousAttachments: previousSurface.imageAttachments,
      currentAttachments: currentSurface.imageAttachments,
      dirtyRows: Set(rowBatches.map(\.row)),
      supportsIncrementalGraphicsReplay: supportsIncrementalGraphicsReplay
    )

    return .incremental(
      rowBatches: rowBatches,
      graphicsReplay: graphicsReplay,
      surfaceSize: currentSurface.size
    )
  }

  private func rowsToDiff(
    damage: PresentationDamage?,
    rowCount: Int
  ) -> [Int] {
    if let damage {
      damage.dirtyRows
        .filter { $0 >= 0 && $0 < rowCount }
        .sorted()
    } else {
      Array(0..<rowCount)
    }
  }

  private func appendDiffedRowBatches(
    rows: [Int],
    previousSurface: RasterSurface,
    currentSurface: RasterSurface,
    damage: PresentationDamage?,
    renderer: TerminalSurfaceRenderer,
    to rowBatches: inout [TerminalPresentationPlan.RowBatch]
  ) {
    for row in rows {
      let previousRow = row < previousSurface.cells.count ? previousSurface.cells[row] : []
      let currentRow = row < currentSurface.cells.count ? currentSurface.cells[row] : []
      let rowSpans = renderer.diffSpans(
        previousRow: previousRow,
        currentRow: currentRow,
        width: max(
          previousSurface.size.width,
          currentSurface.size.width,
          previousRow.count,
          currentRow.count
        ),
        limitingTo: damage?.columnRanges(for: row)
      )

      if let rowBatch = renderer.renderRowBatch(
        row: row,
        currentRow: currentRow,
        spans: rowSpans
      ) {
        rowBatches.append(rowBatch)
      }
    }
  }

  /// Attempts the verified scroll-region plan (R2.3) for a translation
  /// candidate, or `nil` to fall back to the plain incremental diff.
  ///
  /// Soundness is by construction, not trust: the terminal state after
  /// DECSTBM + SU/SD over the band's rows is exactly the previously written
  /// rows shifted by `dy` — across the **full surface width**, because
  /// DECSTBM regions are full-width — with blank rows exposed at the vacated
  /// edge. Every region row is therefore diffed, full-width, against
  /// precisely that post-scroll content — translated rows against the
  /// dy-shifted written row, exposed rows against blank — and every
  /// difference becomes an ordinary repaint batch. The emitted bytes
  /// reproduce the current surface no matter what the candidate claimed; the
  /// candidate only decides *which* baseline rows the diff runs against.
  ///
  /// Full-width verification is also what admits partial-width bands
  /// soundly: chrome sharing the band's rows (vertical borders, padding
  /// gutters, a plain `ScrollView`'s indicator column) is row-invariant, so
  /// its shifted cells equal its unshifted cells and verification passes;
  /// row-varying flanking content (the indicator thumb, a sidebar) simply
  /// mismatches and is repainted — or, past the threshold, vetoes the
  /// translation wholesale.
  ///
  /// Declines (returns `nil`) when:
  /// - the band's rows leave the surface, number fewer than two, or `dy` is
  ///   zero / band-sized (nothing to translate),
  /// - image attachments exist (scroll behavior of terminal-drawn images
  ///   inside a DECSTBM region is emulator-dependent),
  /// - translated-row mismatches exceed
  ///   ``scrollRegionMismatchFallbackShare`` of the region's cells (the
  ///   translation hypothesis is materially wrong — the plain diff is
  ///   cheaper).
  private func scrollRegionPlan(
    for candidate: ScrollTranslationCandidate,
    previousSurface: RasterSurface,
    currentSurface: RasterSurface,
    damage: PresentationDamage?,
    renderer: TerminalSurfaceRenderer,
    rowCount: Int
  ) -> TerminalPresentationPlan? {
    let band = candidate.band
    let dy = candidate.dy
    guard
      band.origin.y >= 0,
      band.maxY <= currentSurface.size.height,
      band.size.height >= 2,
      dy != 0,
      abs(dy) < band.size.height,
      previousSurface.imageAttachments.isEmpty,
      currentSurface.imageAttachments.isEmpty
    else {
      return nil
    }

    // R3.2c: row-buffer identity verification. When the raster tier served
    // this frame through the translation blit (R3.2b), every served band
    // row's buffer IS the previous surface's `row − dy` buffer — and for
    // image-free frames `preparedSurface` is the identity function (G10,
    // pinned by `TerminalPreparedSurfaceIdentityTests`), so the same buffers
    // reach this planner's written baseline. Row identity therefore proves
    // the translation claim in O(band height) pointer compares. Rows without
    // identity provenance — repainted rows, the first frame after a barrier,
    // dropped-frame recovery, image frames — keep the full-width cell
    // verification below, wholesale.
    var identityRows: Set<Int> = []
    for row in band.origin.y..<band.maxY {
      let sourceRow = row - dy
      guard sourceRow >= band.origin.y, sourceRow < band.maxY,
        row < currentSurface.cells.count,
        sourceRow < previousSurface.cells.count,
        Self.rowsShareStorage(currentSurface.cells[row], previousSurface.cells[sourceRow])
      else {
        continue
      }
      identityRows.insert(row)
    }

    // The translated verification diffs every band row full-width, which
    // costs real planner time (~0.5 ms on an 80×32 band of styled cells).
    // When the damage hint says the plain diff would repaint only a sliver
    // of the band — the uniform-collection shape, where consecutive rows
    // differ in a few digit cells — translation cannot pay for that
    // verify: the plain emission is already narrow. Attempt the region only
    // when the hinted in-band repaint reaches
    // ``scrollRegionHintAttemptShare`` of the band; with no hint the plain
    // path would full-diff every row anyway, so the verify adds nothing.
    //
    // Identity-verified frames skip this pre-gate outright (R3.2c): the
    // pre-gate exists only because the verify costs ~0.5 ms, and identity
    // rows are proven for free — which readmits the notch/fling
    // scroll-region emissions R2.3 deliberately forfeited.
    if identityRows.isEmpty, let damage {
      let hintedBandCells = hintedCellCount(
        damage: damage,
        bandRows: band.origin.y..<band.maxY,
        surfaceWidth: currentSurface.size.width
      )
      guard
        Double(hintedBandCells)
          >= Double(max(1, currentSurface.size.width) * band.size.height)
          * Self.scrollRegionHintAttemptShare
      else {
        return nil
      }
    }

    // Screen-pinned edge rows — a hosted collection's overflow-indicator
    // lines and box-border rows sit inside the published band but do not
    // move with the content. Inside the region they would be repainted
    // full-width every frame (shifted chrome never equals pinned chrome);
    // outside it they cost nothing, because their unshifted frame-over-frame
    // diff is empty. Trimming is sound for ANY choice of edge rows — a
    // trimmed row is simply handled by the ordinary unshifted diff below —
    // so the criterion is purely a bytes heuristic: trim an edge row when
    // its unshifted diff is empty (it did not change on screen) and keeping
    // it would force a repaint (it is exposed by the scroll, or its
    // translated mismatch exceeds half the row).
    let trimmedRegion = trimmedScrollRegionRows(
      band: band,
      dy: dy,
      previousSurface: previousSurface,
      currentSurface: currentSurface,
      renderer: renderer
    )
    let regionHeight = trimmedRegion.count
    guard regionHeight >= 2, abs(dy) < regionHeight else {
      return nil
    }

    let bandRows = trimmedRegion
    let bandCellCount = max(1, currentSurface.size.width) * regionHeight
    let mismatchFallbackCellCount = Int(
      Double(bandCellCount) * Self.scrollRegionMismatchFallbackShare
    )
    var mismatchedCellCount = 0
    var rowBatches: [TerminalPresentationPlan.RowBatch] = []

    for row in bandRows {
      let sourceRow = row - dy
      let currentRow = row < currentSurface.cells.count ? currentSurface.cells[row] : []
      let isExposedRow = !bandRows.contains(sourceRow)
      if !isExposedRow, identityRows.contains(row) {
        // Proven translated by row-buffer identity: after SU/SD the terminal
        // already shows exactly this row's cells. No diff, no batch, no
        // mismatch contribution.
        continue
      }
      // After SU/SD the terminal's row `row` holds the previously written
      // row `row - dy` when that source stayed inside the region, and blank
      // cells when the scroll vacated it — diff against exactly that.
      let previousRow: [RasterCell] =
        if isExposedRow {
          []
        } else {
          sourceRow < previousSurface.cells.count ? previousSurface.cells[sourceRow] : []
        }
      let rowSpans = renderer.diffSpans(
        previousRow: previousRow,
        currentRow: currentRow,
        width: max(
          previousSurface.size.width,
          currentSurface.size.width,
          previousRow.count,
          currentRow.count
        ),
        limitingTo: nil
      )
      if !isExposedRow {
        mismatchedCellCount += rowSpans.reduce(0) { partial, span in
          partial + max(0, span.upperBound - span.lowerBound)
        }
        guard mismatchedCellCount <= mismatchFallbackCellCount else {
          return nil
        }
      }
      if let rowBatch = renderer.renderRowBatch(
        row: row,
        currentRow: currentRow,
        spans: rowSpans
      ) {
        rowBatches.append(rowBatch)
      }
    }

    // Off-band rows keep today's damage-hinted diff: the region ops leave
    // them untouched, so the written baseline remains their sound previous
    // content. In-band rows were handled above and are excluded even when
    // the damage hint lists them — the hint's column ranges were computed
    // against the *unshifted* baseline the scroll just invalidated.
    appendDiffedRowBatches(
      rows: rowsToDiff(damage: damage, rowCount: rowCount)
        .filter { !bandRows.contains($0) },
      previousSurface: previousSurface,
      currentSurface: currentSurface,
      damage: damage,
      renderer: renderer,
      to: &rowBatches
    )
    rowBatches.sort { $0.row < $1.row }

    return .incremental(
      rowBatches: rowBatches,
      graphicsReplay: .none,
      surfaceSize: currentSurface.size,
      scrollRegion: .init(
        topRow: bandRows.lowerBound,
        bottomRow: bandRows.upperBound - 1,
        delta: dy
      )
    )
  }

  /// Whether two rows share their element storage — the R3.2c identity
  /// currency. Same buffer means same cells with no compare; the blit
  /// (R3.2b) *constructs* this identity by moving row buffers, and CoW
  /// breaks it exactly where content was repainted. Equal-count empty rows
  /// are trivially identical.
  private static func rowsShareStorage(
    _ currentRow: [RasterCell],
    _ previousRow: [RasterCell]
  ) -> Bool {
    guard currentRow.count == previousRow.count else {
      return false
    }
    guard !currentRow.isEmpty else {
      return true
    }
    return unsafe currentRow.withUnsafeBufferPointer { current in
      unsafe previousRow.withUnsafeBufferPointer { previous in
        unsafe current.baseAddress == previous.baseAddress
      }
    }
  }

  /// Cells the damage hint would let the plain incremental diff repaint
  /// within the band's rows — the cost proxy the scroll-region pre-gate
  /// compares against. A dirty row without column ranges is a full-row
  /// repaint.
  private func hintedCellCount(
    damage: PresentationDamage,
    bandRows: Range<Int>,
    surfaceWidth: Int
  ) -> Int {
    var cells = 0
    for row in damage.dirtyRows where bandRows.contains(row) {
      if let ranges = damage.columnRanges(for: row), !ranges.isEmpty {
        cells += ranges.reduce(0) { partial, range in
          partial + max(0, min(range.upperBound, surfaceWidth) - max(0, range.lowerBound))
        }
      } else {
        cells += max(0, surfaceWidth)
      }
    }
    return cells
  }

  /// Shrinks the candidate band to the rows that actually benefit from the
  /// DECSTBM translation, dropping screen-pinned edge rows (see the call
  /// site). Bounded work: each loop iteration diffs at most two rows and
  /// stops at the first edge row that moved on screen or translates cleanly.
  private func trimmedScrollRegionRows(
    band: CellRect,
    dy: Int,
    previousSurface: RasterSurface,
    currentSurface: RasterSurface,
    renderer: TerminalSurfaceRenderer
  ) -> Range<Int> {
    var topRow = band.origin.y
    var bottomRow = band.maxY - 1
    let halfRowCells = max(1, currentSurface.size.width) / 2

    func row(_ index: Int, of surface: RasterSurface) -> [RasterCell] {
      index < surface.cells.count ? surface.cells[index] : []
    }
    func diffCells(previousRow: [RasterCell], currentRow: [RasterCell]) -> Int {
      renderer.diffSpans(
        previousRow: previousRow,
        currentRow: currentRow,
        width: max(
          previousSurface.size.width,
          currentSurface.size.width,
          previousRow.count,
          currentRow.count
        ),
        limitingTo: nil
      ).reduce(0) { partial, span in
        partial + max(0, span.upperBound - span.lowerBound)
      }
    }
    func shouldTrim(edgeRow: Int) -> Bool {
      // A row that changed on screen is content, not pinned chrome — keep it
      // in the region (the translated diff or exposure repaint handles it).
      guard
        diffCells(
          previousRow: row(edgeRow, of: previousSurface),
          currentRow: row(edgeRow, of: currentSurface)
        ) == 0
      else {
        return false
      }
      let sourceRow = edgeRow - dy
      guard sourceRow >= topRow, sourceRow <= bottomRow else {
        // Exposed by the scroll: keeping it means a repaint of an unchanged
        // row; trimming it costs nothing.
        return true
      }
      return diffCells(
        previousRow: row(sourceRow, of: previousSurface),
        currentRow: row(edgeRow, of: currentSurface)
      ) > halfRowCells
    }

    while topRow < bottomRow, shouldTrim(edgeRow: topRow) {
      topRow += 1
    }
    while bottomRow > topRow, shouldTrim(edgeRow: bottomRow) {
      bottomRow -= 1
    }
    return topRow..<(bottomRow + 1)
  }

  private func graphicsReplayPlan(
    previousAttachments: [RasterImageAttachment],
    currentAttachments: [RasterImageAttachment],
    dirtyRows: Set<Int>,
    supportsIncrementalGraphicsReplay: Bool
  ) -> TerminalPresentationPlan.GraphicsReplayPlan {
    guard supportsIncrementalGraphicsReplay else {
      return .none
    }
    guard !previousAttachments.isEmpty || !currentAttachments.isEmpty else {
      return .none
    }

    if previousAttachments != currentAttachments {
      return .init(
        scope: .full,
        attachmentsToReplay: currentAttachments
      )
    }

    let attachmentsToReplay = currentAttachments.filter { attachment in
      attachment.visibleBoundsIntersectsAnyDirtyRow(dirtyRows)
    }
    guard !attachmentsToReplay.isEmpty else {
      return .none
    }

    return .init(
      scope: .targeted,
      attachmentsToReplay: attachmentsToReplay
    )
  }
}

extension RasterImageAttachment {
  fileprivate func visibleBoundsIntersectsAnyDirtyRow(_ dirtyRows: Set<Int>) -> Bool {
    guard !dirtyRows.isEmpty else {
      return false
    }

    let lowerRow = visibleBounds.origin.y
    let upperRow = visibleBounds.origin.y + visibleBounds.size.height
    guard lowerRow < upperRow else {
      return false
    }

    return dirtyRows.contains { dirtyRow in
      dirtyRow >= lowerRow && dirtyRow < upperRow
    }
  }
}
