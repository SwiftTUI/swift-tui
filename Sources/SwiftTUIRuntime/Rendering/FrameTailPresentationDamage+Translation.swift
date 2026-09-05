import SwiftTUICore

// The translation-hypothesis leg of the frame-tail damage resolver
// (scroll-latency R3.2b).
//
// Given the tail-time committed-translation candidate (R3.2a) and the previous
// and current committed draw trees, this walk decides — structurally, in
// O(band draw nodes + band commands) — which band rows are *provably* the
// previous frame's `row − dy` and which must repaint. The soundness argument
// is the damage resolver's own: rasterization is a pure function of the draw
// tree, so a band row all of whose possible painters (commands with ink reach
// into the row, on either side of the diff) are translated twins rasterizes
// to the translated cells. Everything the walk cannot prove is *tainted* —
// moved onto the ordinary repaint path — so a wrong hypothesis costs
// performance, never correctness; the F13 oracle sits on top unchanged.
extension FrameTailPresentationDamageResolver {
  /// Produces the raster blit plan for a committed translation candidate, or
  /// `nil` when the walk cannot serve any band row.
  ///
  /// `surfaceSize` must be the previous committed surface's size — the
  /// surface whose rows the blit will move. The rasterizer re-checks that
  /// its own surface matches before applying the plan.
  static func translationPlan(
    candidate: CommittedScrollTranslation,
    surfaceSize: CellSize,
    previousDraw: DrawNode,
    currentDraw: DrawNode
  ) -> RasterTranslationPlan? {
    guard let clamped = candidate.clamped(toSurface: surfaceSize),
      previousDraw.identity == currentDraw.identity
    else {
      return nil
    }
    let band = clamped.band
    let dy = clamped.dy
    let bandRows = band.origin.y..<band.maxY

    var taint = TranslationTaint(band: band, dy: dy, surfaceWidth: surfaceSize.width)

    var stack: [(previous: DrawNode, current: DrawNode)] = [(previousDraw, currentDraw)]
    while let (previous, current) = stack.popLast() {
      if previous == current {
        // Static subtree. Nodes ink only through commands, so taint by each
        // command's ink decomposition rather than the subtree's bounding box
        // — a container ring whose box covers the band but whose ink is the
        // perimeter must not taint every band row. Off the band's columns
        // static ink cannot land in the band, and a full-row blit is
        // self-consistent for flanking chrome (the moved row carries its own
        // chrome cells; the rasterizer's flank verification proves them
        // row-invariant). On the band's columns, static ink must repaint at
        // both its own rows (the blit slid foreign content under it) and the
        // rows its previous ink is carried to.
        taintStaticSubtree(previous, taint: &taint)
        continue
      }
      if previous.paintsSubtreeTranslated(by: dy, as: current) {
        continue
      }
      guard previous.identity == current.identity else {
        // A re-key at this slot: unrelated subtrees on both sides.
        taint.add(previousRect: previous.subtreeBounds, currentRect: current.subtreeBounds)
        continue
      }
      guard previous.clipBounds == current.clipBounds else {
        // The clip governs every descendant's ink; a changed clip defeats
        // per-command reasoning for the whole subtree.
        taint.add(previousRect: previous.subtreeBounds, currentRect: current.subtreeBounds)
        continue
      }
      if previous.drawEffects.isEmpty,
        current.drawEffects.isEmpty,
        previous.metadata == current.metadata,
        previous.environmentSnapshot == current.environmentSnapshot
      {
        // Same node, same paint context: match its own commands under the
        // shift so a windowed collection's per-line commands (which live on
        // one node and re-window every scroll) can be served line-wise.
        matchCommands(
          previous: previous.commands,
          current: current.commands,
          dy: dy,
          environment: current.environmentSnapshot.style,
          taint: &taint
        )
        matchCommands(
          previous: previous.postCommands,
          current: current.postCommands,
          dy: dy,
          environment: current.environmentSnapshot.style,
          taint: &taint
        )
      } else {
        // Effects may sample beyond the one-cell reach and record
        // presentation-layer state the blit cannot translate; a changed
        // paint context re-renders every own-command. Taint the node's own
        // ink on both sides (children still get their own chance below).
        for command in previous.commands + previous.postCommands {
          for rect in command.inkRects {
            taint.add(previousRect: rect, currentRect: nil)
          }
        }
        for command in current.commands + current.postCommands {
          for rect in command.inkRects {
            taint.add(previousRect: nil, currentRect: rect)
          }
        }
        if !previous.drawEffects.isEmpty || !current.drawEffects.isEmpty {
          // Effect output covers the subtree, not just own commands.
          taint.add(previousRect: previous.subtreeBounds, currentRect: current.subtreeBounds)
          continue
        }
      }
      pairChildren(previous: previous.children, current: current.children, taint: &taint) {
        stack.append($0)
      }
    }

    // Exposed rows have no in-band source; they and their one-cell reach
    // neighbours repaint.
    var repaintRows: Set<Int> = []
    for row in bandRows where !bandRows.contains(row - dy) {
      for neighbour in (row - 1)...(row + 1) where bandRows.contains(neighbour) {
        repaintRows.insert(neighbour)
      }
    }
    repaintRows.formUnion(taint.rows)

    guard repaintRows.count < bandRows.count else {
      return nil
    }
    return RasterTranslationPlan(band: band, dy: dy, repaintRows: repaintRows)
  }

  /// Row-taint accumulator. A non-translated contribution taints the band
  /// rows its current ink covers and the band rows its previous ink is
  /// carried to by the blit (`previous rows + dy`), each dilated one row for
  /// the half-block reach doctrine. Changed contributions in flanking columns
  /// also taint rows: the blit copies whole buffers, and raster flank checks
  /// compare only previous-frame cells, so they cannot detect new flank ink.
  /// Unchanged flank commands retain the row-invariance shortcut below.
  private struct TranslationTaint {
    var rows: Set<Int> = []
    private let bandRows: Range<Int>
    private let bandColumns: Range<Int>
    private let surfaceColumns: Range<Int>
    private let dy: Int

    init(band: CellRect, dy: Int, surfaceWidth: Int) {
      bandRows = band.origin.y..<band.maxY
      bandColumns = band.origin.x..<band.maxX
      surfaceColumns = 0..<surfaceWidth
      self.dy = dy
    }

    mutating func add(previousRect: CellRect?, currentRect: CellRect?) {
      if let previousRect {
        addDilated(previousRect.rows, shiftedBy: dy, columns: previousRect.columns)
      }
      if let currentRect {
        addDilated(currentRect.rows, shiftedBy: 0, columns: currentRect.columns)
      }
    }

    mutating func addStatic(_ rect: CellRect) {
      add(previousRect: rect, currentRect: rect)
    }

    /// Taints a static (identical, unshifted) command. Row-invariant chrome
    /// — a uniform-style container fill or ring whose interior rows paint
    /// identical ink — taints only the rows whose contribution class
    /// changes under the shift (its edge zones); a section box enclosing
    /// the whole band then taints nothing, which is what lets a hosted
    /// collection's container chrome coexist with the blit. Everything else
    /// taints its full ink decomposition on both sides.
    mutating func addStaticCommand(
      _ command: DrawCommand,
      environment: StyleEnvironmentSnapshot
    ) {
      if let invariance = command.verticalRowInvariance(in: environment) {
        addRowInvariantStatic(rect: invariance.rect, edge: invariance.edge)
        return
      }
      for rect in command.inkRects {
        addStatic(rect)
      }
    }

    private mutating func addRowInvariantStatic(rect: CellRect, edge: Int) {
      guard rect.columns.overlaps(bandColumns) else {
        return
      }
      let rectRows = rect.rows
      guard !rectRows.isEmpty else {
        return
      }
      // Contribution class per row: 2 = row-invariant interior, 0 = beyond
      // the one-cell reach (no ink), 1 = edge zone (corners, boundary
      // glyphs, half-block reach — ink that may vary by row).
      func contributionClass(_ row: Int) -> Int {
        if row >= rectRows.lowerBound + edge, row < rectRows.upperBound - edge {
          return 2
        }
        if row < rectRows.lowerBound - 1 || row >= rectRows.upperBound + 1 {
          return 0
        }
        return 1
      }
      for row in bandRows {
        let sourceClass = contributionClass(row - dy)
        let rowClass = contributionClass(row)
        if rowClass == 1 || sourceClass == 1 || rowClass != sourceClass {
          rows.insert(row)
        }
      }
    }

    /// Quick reject for static-subtree walks: can any ink inside
    /// `subtreeBounds` reach a band row after dilation, on either the
    /// current side or the shifted previous side?
    func couldAffectBand(subtreeBounds: CellRect) -> Bool {
      guard subtreeBounds.columns.overlaps(bandColumns) else {
        return false
      }
      let rows = subtreeBounds.rows
      guard !rows.isEmpty else {
        return false
      }
      let currentReach = (rows.lowerBound - 1)..<(rows.upperBound + 1)
      let previousReach = (rows.lowerBound + dy - 1)..<(rows.upperBound + dy + 1)
      return currentReach.overlaps(bandRows) || previousReach.overlaps(bandRows)
    }

    private mutating func addDilated(
      _ rectRows: Range<Int>,
      shiftedBy shift: Int,
      columns: Range<Int>
    ) {
      guard !rectRows.isEmpty, !columns.isEmpty,
        columns.overlaps(surfaceColumns)
      else {
        return
      }
      let lower = rectRows.lowerBound + shift - 1
      let upper = rectRows.upperBound + shift + 1
      for row in lower..<upper where bandRows.contains(row) {
        rows.insert(row)
      }
    }
  }

  /// Taints a static (unchanged, unshifted) subtree by its commands' ink
  /// decomposition. Subtrees whose extent cannot reach the band — even after
  /// the one-row dilation and the previous-ink shift — are skipped without a
  /// walk.
  private static func taintStaticSubtree(
    _ root: DrawNode,
    taint: inout TranslationTaint
  ) {
    guard taint.couldAffectBand(subtreeBounds: root.subtreeBounds) else {
      return
    }
    var stack: [DrawNode] = [root]
    while let node = stack.popLast() {
      guard taint.couldAffectBand(subtreeBounds: node.subtreeBounds) else {
        continue
      }
      for command in node.commands + node.postCommands {
        taint.addStaticCommand(command, environment: node.environmentSnapshot.style)
      }
      stack.append(contentsOf: node.children)
    }
  }

  /// Matches one node's command lists under the shift.
  ///
  /// Commands are keyed by shifted top-level bounds and consumed FIFO so
  /// equal-bounds duplicates keep their relative order; the matched previous
  /// indices must be strictly increasing (relative paint order preserved) or
  /// the out-of-order pair is demoted to taint. Unmatched commands taint via
  /// their ink decomposition, which is what lets a static container ring
  /// beside the band avoid tainting every row its bounding box covers.
  private static func matchCommands(
    previous: [DrawCommand],
    current: [DrawCommand],
    dy: Int,
    environment: StyleEnvironmentSnapshot,
    taint: inout TranslationTaint
  ) {
    guard !previous.isEmpty || !current.isEmpty else {
      return
    }

    enum MatchKind {
      /// A translated twin: no taint.
      case translated
      /// An identical, unshifted command (static chrome inside a changed
      /// node): tainted through the static classifier, which spares the
      /// row-invariant interiors of container fills and rings.
      case staticIdentical(DrawCommand)
    }
    struct QueueEntry {
      var index: Int
      var command: DrawCommand
      var consumed = false
    }
    var translatedQueues: [CellRect: [Int]] = [:]
    var staticQueues: [CellRect: [Int]] = [:]
    var entries: [QueueEntry] = []
    entries.reserveCapacity(previous.count)
    for (index, command) in previous.enumerated() {
      entries.append(QueueEntry(index: index, command: command))
      translatedQueues[command.topLevelBounds.offsetBy(dy: dy), default: []].append(index)
      staticQueues[command.topLevelBounds, default: []].append(index)
    }

    func consume(
      _ queues: inout [CellRect: [Int]],
      key: CellRect,
      matches: (DrawCommand) -> Bool
    ) -> Int? {
      guard var queue = queues[key] else {
        return nil
      }
      for (position, entryIndex) in queue.enumerated()
      where !entries[entryIndex].consumed && matches(entries[entryIndex].command) {
        queue.remove(at: position)
        queues[key] = queue
        return entryIndex
      }
      return nil
    }

    var matched: [(previousIndex: Int, kind: MatchKind, current: DrawCommand)] = []
    for command in current {
      // The shifted interpretation is the primary claim: repeating identical
      // commands (row markers, separators — the same glyphs at every row)
      // are ambiguous between "static" and "translated", and only the
      // translated pairing serves rows. Genuinely static chrome has no
      // shifted twin and falls through to the static pass, where the
      // row-invariance classifier decides its taint.
      if let entryIndex = consume(
        &translatedQueues, key: command.topLevelBounds,
        matches: { $0.paintsTranslated(by: dy, as: command) })
      {
        entries[entryIndex].consumed = true
        matched.append((entryIndex, .translated, command))
        continue
      }
      if let entryIndex = consume(
        &staticQueues, key: command.topLevelBounds, matches: { $0 == command })
      {
        entries[entryIndex].consumed = true
        matched.append((entryIndex, .staticIdentical(command), command))
        continue
      }
      for rect in command.inkRects {
        taint.add(previousRect: nil, currentRect: rect)
      }
    }

    // Paint order must survive the shift: demote any match that would replay
    // previous commands out of order.
    var highestPreviousIndex = -1
    for (previousIndex, kind, command) in matched {
      if previousIndex < highestPreviousIndex {
        entries[previousIndex].consumed = false
        for rect in command.inkRects {
          taint.add(previousRect: nil, currentRect: rect)
        }
        continue
      }
      highestPreviousIndex = previousIndex
      if case .staticIdentical(let staticCommand) = kind {
        taint.addStaticCommand(staticCommand, environment: environment)
      }
    }

    for entry in entries where !entry.consumed {
      for rect in entry.command.inkRects {
        taint.add(previousRect: rect, currentRect: nil)
      }
    }
  }

  /// Pairs children by identity (the windowed edge rows shift positions, so
  /// positional pairing would misalign the whole band), preserving relative
  /// order and tainting everything unpaired or ambiguous.
  private static func pairChildren(
    previous: [DrawNode],
    current: [DrawNode],
    taint: inout TranslationTaint,
    push: ((previous: DrawNode, current: DrawNode)) -> Void
  ) {
    guard !previous.isEmpty || !current.isEmpty else {
      return
    }

    var previousIndexByIdentity: [Identity: Int] = [:]
    var ambiguous: Set<Identity> = []
    for (index, child) in previous.enumerated() {
      if previousIndexByIdentity.updateValue(index, forKey: child.identity) != nil {
        ambiguous.insert(child.identity)
      }
    }
    var currentSeen: Set<Identity> = []
    for child in current where !currentSeen.insert(child.identity).inserted {
      ambiguous.insert(child.identity)
    }

    var consumed = [Bool](repeating: false, count: previous.count)
    var highestPreviousIndex = -1
    for child in current {
      guard !ambiguous.contains(child.identity),
        let index = previousIndexByIdentity[child.identity],
        !consumed[index],
        index > highestPreviousIndex
      else {
        taint.add(previousRect: nil, currentRect: child.subtreeBounds)
        continue
      }
      consumed[index] = true
      highestPreviousIndex = index
      push((previous[index], child))
    }
    for (index, child) in previous.enumerated() where !consumed[index] {
      taint.add(previousRect: child.subtreeBounds, currentRect: nil)
    }
  }
}
