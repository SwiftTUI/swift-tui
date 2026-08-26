/// Converts draw commands into a terminal cell surface.
package struct Rasterizer: Sendable {
  internal static let emptyCompositingStyle = ResolvedTextStyle()

  package enum IncrementalRasterVerificationPolicy: Sendable {
    case verifySoundDamage
    case trustSoundDamage
  }

  package typealias RasterizationResult = (
    surface: RasterSurface,
    visibleIdentities: Set<Identity>,
    presentationDamage: PresentationDamage?,
    incrementalMismatch: IncrementalRasterMismatch?,
    /// Which path produced ``surface``. Institutionalized because the entire
    /// incremental tier was dormant for the whole of its existence and nothing
    /// in the codebase could say so: the four TermUIPerf scenarios checked in
    /// to prove it measured a flat zero, and finding out required patching the
    /// rasterizer by hand. Rides the result because the rasterizer may run on
    /// the frame-tail worker.
    path: RasterPath
  )

  /// Which of the rasterizer's two paths produced a surface.
  package enum RasterPath: String, Sendable, Equatable {
    /// Painted from an empty surface.
    case fresh
    /// Reused the previous surface's clean rows and repainted only the damaged
    /// ones.
    case incremental
    /// The incremental path additionally served verified scroll-band rows by
    /// moving the previous surface's row buffers (R3.2b translation blit).
    case incrementalTranslated
    /// Took the incremental path, then the F13 verification oracle caught a
    /// divergence and repaired it with a fresh raster.
    case incrementalRepaired
  }

  /// Evidence from the incremental-repaint verification oracle (F13): the
  /// incremental surface diverged from a fresh rasterization, meaning the
  /// presentation damage the runtime proved sound was incomplete. Historically
  /// the oracle repaired this in silence, so incomplete-damage producer bugs
  /// shipped as release-only corruption while every DEBUG run self-healed.
  /// Carried on ``RasterizationResult`` because the rasterizer may run on the
  /// frame-tail worker, where the probe's `@MainActor` counters are
  /// unreachable; the main-actor frame coordinator records it on return.
  package struct IncrementalRasterMismatch: Sendable, Equatable {
    /// Rows whose cells differ between the incremental and fresh surfaces.
    /// Empty when only non-cell surface state (image attachments, surface
    /// attachments, or metadata) diverged.
    package var mismatchedRows: [Int]
    /// Human-readable evidence for the divergence: the damage rows the
    /// incremental path trusted, and for the first few mismatched rows the
    /// row text each side produced (or the differing columns when only cell
    /// styles diverged). Empty when the caller has nothing beyond the rows.
    ///
    /// The crash diagnostics are frequently the only artifact a consumer can
    /// hand back: a DEBUG trap names the rows but, without the cells, a report
    /// cannot say which painter or damage producer under-reported. Carried on
    /// the mismatch so the main-actor recorder can fold it into the assertion
    /// message and the probe's per-kind detail.
    package var evidence: String

    package init(mismatchedRows: [Int], evidence: String = "") {
      self.mismatchedRows = mismatchedRows
      self.evidence = evidence
    }
  }

  internal indirect enum ResolvedShapeColorMode {
    case constant(Color?)
    case sampled(LinearGradient)
    /// The cell aspect ratio is captured when the style is resolved, where
    /// the style environment is in scope, so the per-cell sampler can measure
    /// falloff in device-pixel space without threading metrics through every
    /// `resolveColor` caller.
    case sampledRadial(RadialGradient, aspectRatio: Double)
    case sampledMesh(PreparedMeshGradient)
    case tile(ResolvedTileColorMode)
  }

  internal struct ResolvedTileColorMode {
    var pattern: TileStyle.Pattern
    var foreground: ResolvedShapeColorMode
    var background: ResolvedShapeColorMode?
  }

  private var incrementalVerificationPolicy: IncrementalRasterVerificationPolicy
  internal let preparedMeshGradientCache: PreparedMeshGradientCache

  /// Proof token for the incremental repaint adapter.
  ///
  /// The rasterizer can reject damage that is visibly incompatible with
  /// retained reuse, but the runtime remains responsible for only passing row
  /// damage after it has proven those rows cover every changed cell.
  internal struct SoundRasterDamage: Sendable {
    var presentationDamage: PresentationDamage
    var dirtyRows: Set<Int>

    init?(
      presentationDamage: PresentationDamage,
      previousSurface: RasterSurface,
      surfaceSize: CellSize
    ) {
      guard previousSurface.size == surfaceSize else {
        return nil
      }
      guard !presentationDamage.requiresFullTextRepaint,
        !presentationDamage.requiresFullGraphicsReplay
      else {
        return nil
      }

      let dirtyRows = presentationDamage.dirtyRows
      guard !dirtyRows.isEmpty else {
        return nil
      }

      self.presentationDamage = presentationDamage
      self.dirtyRows = dirtyRows
    }
  }

  package init() {
    self.init(
      incrementalVerificationPolicy: Self.defaultIncrementalVerificationPolicy()
    )
  }

  package init(
    incrementalVerificationPolicy: IncrementalRasterVerificationPolicy
  ) {
    self.incrementalVerificationPolicy = incrementalVerificationPolicy
    self.preparedMeshGradientCache = .shared
  }

  /// Test-isolation seam for cache behavior that must not depend on the
  /// process-wide cache's occupancy or admission history.
  internal init(
    preparedMeshGradientCache: PreparedMeshGradientCache,
    incrementalVerificationPolicy: IncrementalRasterVerificationPolicy =
      Self.defaultIncrementalVerificationPolicy()
  ) {
    self.incrementalVerificationPolicy = incrementalVerificationPolicy
    self.preparedMeshGradientCache = preparedMeshGradientCache
  }

  /// Rasterizes a draw tree into a ``RasterSurface``.
  package func rasterize(_ draw: DrawNode) -> RasterSurface {
    rasterize(draw, minimumSize: .zero)
  }

  package func rasterize(
    _ draw: DrawNode,
    minimumSize: CellSize
  ) -> RasterSurface {
    rasterize(draw, minimumSize: minimumSize, previousSurface: nil, damage: nil)
  }

  package func rasterize(
    _ draw: DrawNode,
    minimumSize: CellSize,
    previousSurface: RasterSurface?,
    damage: PresentationDamage?
  ) -> RasterSurface {
    rasterizeCollectingVisibleIdentities(
      draw,
      minimumSize: minimumSize,
      previousSurface: previousSurface,
      damage: damage
    ).surface
  }

  /// Rasterizes ``draw`` and returns both the rendered ``RasterSurface``
  /// and the set of identities whose draw nodes had non-empty visible
  /// bounds after clipping.
  ///
  /// The identity set is the "drawn-set" the run loop uses to gate
  /// animation tick scheduling on viewport visibility: if none of the
  /// identities affected by an animation tick appear in this set, the
  /// animation is painting into a clipped subtree and scheduling another
  /// deadline burns CPU for no visible effect.
  ///
  /// Note: identities are recorded *before* the dirty-rows culling step,
  /// so the set captures "would have painted cells if drawn from
  /// scratch" rather than "actually repainted cells this frame."  The
  /// distinction matters because dirty-rows is an incremental-repaint
  /// optimization, while the visibility check we gate animations on is
  /// a geometric predicate on the placed tree.
  /// - Parameter verifyIncrementalRasterDamage: when `true`, verify the
  ///   incremental surface against a fresh raster even if
  ///   ``incrementalVerificationPolicy`` would trust the sound-damage result.
  ///   The frame-tail coordinator passes the soundness probe's per-frame
  ///   sampling decision (``SoundnessProbeConfiguration/isSampledFrame``) here,
  ///   so the F13 oracle — historically DEBUG/env-only — also runs on a sampled
  ///   fraction of release frames when the probe is opted in. Defaults to
  ///   `false`, preserving the policy-only behavior for every other caller.
  package func rasterizeCollectingVisibleIdentities(
    _ draw: DrawNode,
    minimumSize: CellSize,
    previousSurface: RasterSurface?,
    damage: PresentationDamage?,
    verifyIncrementalRasterDamage: Bool = false,
    translation: RasterTranslationPlan? = nil
  ) -> RasterizationResult {
    let surfaceSize = rasterSurfaceSize(for: draw, minimumSize: minimumSize)
    guard surfaceSize.width > 0, surfaceSize.height > 0 else {
      return (RasterSurface(), [], nil, nil, .fresh)
    }

    if let previousSurface,
      let damage,
      let soundDamage = SoundRasterDamage(
        presentationDamage: damage,
        previousSurface: previousSurface,
        surfaceSize: surfaceSize
      )
    {
      return rasterizeIncrementallyCollectingVisibleIdentities(
        draw,
        surfaceSize: surfaceSize,
        previousSurface: previousSurface,
        soundDamage: soundDamage,
        verifyIncrementalRasterDamage: verifyIncrementalRasterDamage,
        translation: translation
      )
    }

    return rasterizeFreshCollectingVisibleIdentities(
      draw,
      surfaceSize: surfaceSize
    )
  }

  private func rasterSurfaceSize(
    for draw: DrawNode,
    minimumSize: CellSize
  ) -> CellSize {
    let extent = maximumExtent(for: draw, clip: nil)
    return CellSize(
      width: max(extent.x, max(0, minimumSize.width)),
      height: max(extent.y, max(0, minimumSize.height))
    )
  }

  private func rasterizeFreshCollectingVisibleIdentities(
    _ draw: DrawNode,
    surfaceSize: CellSize
  ) -> RasterizationResult {
    var cells = Array(
      repeating: Array(repeating: RasterCell.empty, count: surfaceSize.width),
      count: surfaceSize.height
    )
    var imageAttachments: [RasterImageAttachment] = []
    var visibleIdentities: Set<Identity> = []
    let presentationRecorder = RasterPresentationLayerRecorder()

    paint(
      node: draw,
      cells: &cells,
      imageAttachments: &imageAttachments,
      clip: nil,
      dirtyRows: nil,
      dirtySpans: nil,
      visibleIdentities: &visibleIdentities,
      presentationRecorder: presentationRecorder
    )
    RasterImageOcclusion.apply(
      to: &imageAttachments,
      layers: presentationRecorder.layers
    )

    return (
      RasterSurface(
        size: surfaceSize,
        cells: cells,
        imageAttachments: imageAttachments,
        presentationLayers: presentationRecorder.layers
      ),
      visibleIdentities,
      nil,
      nil,
      .fresh
    )
  }

  private func rasterizeIncrementallyCollectingVisibleIdentities(
    _ draw: DrawNode,
    surfaceSize: CellSize,
    previousSurface: RasterSurface,
    soundDamage: SoundRasterDamage,
    verifyIncrementalRasterDamage: Bool = false,
    translation: RasterTranslationPlan? = nil
  ) -> RasterizationResult {
    var damage = soundDamage.presentationDamage
    var dirtyRows = soundDamage.dirtyRows
    var cells = previousSurface.cells
    // R3.2b: serve the verified band rows by moving the previous surface's
    // row buffers before the ordinary damage-restricted repaint. The blit
    // constructs row-buffer identity at the translated rows and removes them
    // from the dirty set; a declined blit leaves this path byte-identical to
    // the plain incremental raster.
    var translatedRows: [Int] = []
    if let translation {
      translatedRows = applyTranslationBlit(
        translation,
        previousSurface: previousSurface,
        surfaceSize: surfaceSize,
        cells: &cells
      )
      if !translatedRows.isEmpty {
        dirtyRows.subtract(translatedRows)
        damage = PresentationDamage(
          textRows: damage.textRows.filter { !translatedRows.contains($0.row) },
          graphicsInvalidation: damage.graphicsInvalidation,
          requiresFullTextRepaint: damage.requiresFullTextRepaint,
          requiresFullGraphicsReplay: damage.requiresFullGraphicsReplay
        )
        guard !dirtyRows.isEmpty else {
          // The scroll always exposes at least one repaint row; an empty
          // dirty set here means the plan and the damage disagree about the
          // frame — decline the whole incremental path conservatively.
          return rasterizeFreshCollectingVisibleIdentities(
            draw,
            surfaceSize: surfaceSize
          )
        }
      }
    }
    // Close the dirty set over rows the retained presentation-layer order
    // needs re-recorded (`presentationOrderDamageClosure`). It is the only
    // closure: no painter reads a cell outside the row it writes (a stroke
    // with no explicit background keeps the background beneath it through
    // `write`'s compositing), so damage never has to grow to cover a
    // painter's reads.
    let closedDirtyRows = presentationOrderDamageClosure(
      dirtyRows,
      previousLayers: previousSurface.presentationLayers,
      surfaceHeight: surfaceSize.height
    ).dirtyRows
    let closureRows = closedDirtyRows.subtracting(dirtyRows)
    if !closureRows.isEmpty {
      dirtyRows = closedDirtyRows
      damage = PresentationDamage(
        textRows: damage.textRows
          + closureRows.sorted().map { PresentationDamage.TextRow(row: $0) },
        graphicsInvalidation: damage.graphicsInvalidation,
        requiresFullTextRepaint: damage.requiresFullTextRepaint,
        requiresFullGraphicsReplay: damage.requiresFullGraphicsReplay
      )
      // A served row the closure re-dirtied is cleared and repainted below,
      // so the blit no longer accounts for it.
      translatedRows.removeAll { closureRows.contains($0) }
    }
    var imageAttachments = previousSurface.imageAttachments.filter { attachment in
      !visibleBounds(attachment.visibleBounds, intersectsAnyOf: dirtyRows)
    }
    let presentationRecorder = RasterPresentationLayerRecorder(
      layers: previousSurface.presentationLayers.filter { layer in
        !visibleBounds(layer.bounds, intersectsAnyOf: dirtyRows)
      }
    )
    clear(cells: &cells, for: damage, surfaceWidth: surfaceSize.width)

    // Coalesced once per incremental raster, then reused by every cull
    // altitude in the paint walk (D70). Building it costs one sort of the
    // dirty rows; it replaces the convex hull the walk used to cull on, so a
    // subtree or command sitting *between* two disjoint damage bands is now
    // skipped before it resolves styles or lays out text, not merely stopped
    // at the cell-write clamp.
    guard let dirtySpans = DirtyRowSpans(dirtyRows: dirtyRows) else {
      return rasterizeFreshCollectingVisibleIdentities(
        draw,
        surfaceSize: surfaceSize
      )
    }

    var visibleIdentities: Set<Identity> = []

    paint(
      node: draw,
      cells: &cells,
      imageAttachments: &imageAttachments,
      clip: nil,
      dirtyRows: dirtyRows,
      dirtySpans: dirtySpans,
      visibleIdentities: &visibleIdentities,
      presentationRecorder: presentationRecorder
    )
    // Recomputed from the merged (retained + fresh) sidecar every raster:
    // retained attachments converge to the trim they already carried, and a
    // repainted occluder re-trims the attachments beneath it. Runs before
    // surface construction so the F13 oracle compares trimmed attachments on
    // both sides.
    RasterImageOcclusion.apply(
      to: &imageAttachments,
      layers: presentationRecorder.layers
    )

    let surface = RasterSurface(
      size: surfaceSize,
      cells: cells,
      imageAttachments: canonicallyOrderedImageAttachments(imageAttachments, draw: draw),
      presentationLayers: presentationRecorder.layers.sorted { lhs, rhs in
        lhs.order < rhs.order
      }
    )
    if incrementalVerificationPolicy == .verifySoundDamage || verifyIncrementalRasterDamage {
      // F13: when damage suppresses painting, verify against a fresh raster
      // before returning the incremental surface. A mismatch means damage was
      // incomplete, so the fresh result must force a full presentation repaint.
      // The `verifyIncrementalRasterDamage` path runs this same oracle on the
      // soundness probe's sampled release frames, not just DEBUG/env-forced ones.
      if var freshFallback = freshRasterizationIfIncrementalMismatch(
        draw,
        surfaceSize: surfaceSize,
        incrementalSurface: surface,
        trustedDirtyRows: dirtyRows
      ) {
        freshFallback.path = .incrementalRepaired
        return freshFallback
      }
    }

    var artifactDamage = refinedPresentationDamage(
      from: damage,
      previousSurface: previousSurface,
      currentSurface: surface
    )
    if !translatedRows.isEmpty {
      // Translated rows changed on screen (their buffers moved), so the
      // artifact damage must carry them — but as unrefined full rows: cell-
      // diffing them against the previous surface would pay the O(band cells)
      // compare the blit exists to remove.
      artifactDamage = PresentationDamage(
        textRows: artifactDamage.textRows + translatedRows.map { .init(row: $0) },
        graphicsInvalidation: artifactDamage.graphicsInvalidation,
        requiresFullTextRepaint: artifactDamage.requiresFullTextRepaint,
        requiresFullGraphicsReplay: artifactDamage.requiresFullGraphicsReplay
      )
    }
    return (
      surface,
      visibleIdentities,
      artifactDamage,
      nil,
      translatedRows.isEmpty ? .incremental : .incrementalTranslated
    )
  }

  /// Applies a verified translation blit: moves the previous surface's row
  /// buffers by `dy` at every band row the plan proved translatable, after
  /// re-validating the plan against this raster's actual geometry and
  /// verifying the flanking columns row-invariant. Returns the rows served
  /// (empty when the blit declines — the caller then runs the plain
  /// incremental raster unchanged).
  ///
  /// Reads always come from `previousSurface.cells` (an independent value
  /// referencing the shared row buffers), so move order cannot alias.
  /// Retained presentation layers on served rows keep their previous bounds;
  /// only non-compositing-significant cell fragments can remain there (the
  /// plan never serves effect-carrying or image content), and those carry no
  /// host-visible information beyond the cell grid.
  private func applyTranslationBlit(
    _ translation: RasterTranslationPlan,
    previousSurface: RasterSurface,
    surfaceSize: CellSize,
    cells: inout [[RasterCell]]
  ) -> [Int] {
    guard previousSurface.size == surfaceSize,
      previousSurface.imageAttachments.isEmpty,
      translation.dy != 0,
      translation.band.origin.y >= 0,
      translation.band.maxY <= surfaceSize.height,
      translation.band.maxY <= previousSurface.cells.count,
      translation.band.maxY <= cells.count
    else {
      return []
    }
    // Compositing-significant retained layers cannot ride a moved band: the
    // sidecar's bounds would describe the pre-scroll position.
    let bandRowSet = Set(translation.bandRows)
    for layer in previousSurface.presentationLayers
    where !layer.effects.isEmpty || isImageLayer(layer) {
      if visibleBounds(layer.bounds, intersectsAnyOf: bandRowSet) {
        return []
      }
    }

    let translatedRows = translation.translatedRows
    guard !translatedRows.isEmpty else {
      return []
    }

    // Flank verification: the blit moves whole row buffers, so the columns
    // outside the band must be row-invariant between each served row and its
    // source — the same argument that lets R2.3's full-width verification
    // admit partial-width bands. Rows whose flanks differ are demoted to the
    // repaint path, never mis-served.
    let bandColumns = translation.band.columns
    var servedRows: [Int] = []
    servedRows.reserveCapacity(translatedRows.count)
    for row in translatedRows {
      let sourceRow = row - translation.dy
      guard bandRowSet.contains(sourceRow) else {
        continue
      }
      if flankCellsMatch(
        previousSurface.cells[row],
        previousSurface.cells[sourceRow],
        excludingColumns: bandColumns,
        surfaceWidth: surfaceSize.width
      ) {
        servedRows.append(row)
      }
    }
    for row in servedRows {
      cells[row] = previousSurface.cells[row - translation.dy]
    }
    return servedRows
  }

  private func isImageLayer(_ layer: RasterPresentationLayer) -> Bool {
    if case .image = layer.content {
      return true
    }
    return false
  }

  private func flankCellsMatch(
    _ row: [RasterCell],
    _ sourceRow: [RasterCell],
    excludingColumns bandColumns: Range<Int>,
    surfaceWidth: Int
  ) -> Bool {
    func cell(_ cells: [RasterCell], _ column: Int) -> RasterCell {
      column < cells.count ? cells[column] : .empty
    }
    for column in 0..<max(0, min(surfaceWidth, bandColumns.lowerBound)) {
      guard cell(row, column) == cell(sourceRow, column) else {
        return false
      }
    }
    if bandColumns.upperBound < surfaceWidth {
      for column in bandColumns.upperBound..<surfaceWidth {
        guard cell(row, column) == cell(sourceRow, column) else {
          return false
        }
      }
    }
    return true
  }

  /// Restores fresh-raster paint order for an incrementally merged attachment
  /// array.
  ///
  /// The incremental path keeps retained attachments (outside the dirty rows)
  /// at the front of the array and appends repainted ones behind them, so a
  /// repainted attachment that paints *before* a retained one in the draw tree
  /// would otherwise land *after* it. Attachment order is presentation z-order
  /// for overlapping images, and the F13 verification oracle compares it
  /// against a fresh raster order-sensitively.
  ///
  /// Compositing groups do not disturb this order: a group flattens its
  /// collected attachments into the destination array at the group's own walk
  /// position, which is exactly where a plain depth-first walk would emit
  /// them. Clipping only removes attachments, so ranking by an unclipped walk
  /// preserves the relative order of every attachment that survives.
  private func canonicallyOrderedImageAttachments(
    _ attachments: [RasterImageAttachment],
    draw: DrawNode
  ) -> [RasterImageAttachment] {
    guard attachments.count > 1 else {
      return attachments
    }

    enum Frame {
      case visit(DrawNode)
      case post([DrawCommand])
    }

    var ranksByIdentity: [Identity: [Int]] = [:]
    var nextRank = 0
    func recordImageCommands(_ commands: [DrawCommand]) {
      for command in commands {
        guard case .image(_, let identity, _) = command else {
          continue
        }
        ranksByIdentity[identity, default: []].append(nextRank)
        nextRank += 1
      }
    }

    var stack: [Frame] = [.visit(draw)]
    while let frame = stack.popLast() {
      switch frame {
      case .post(let commands):
        recordImageCommands(commands)
      case .visit(let node):
        recordImageCommands(node.commands)
        if !node.postCommands.isEmpty {
          stack.append(.post(node.postCommands))
        }
        for child in node.children.reversed() {
          stack.append(.visit(child))
        }
      }
    }

    var consumedRanks: [Identity: Int] = [:]
    let ranked = attachments.enumerated().map { index, attachment in
      let occurrence = consumedRanks[attachment.identity, default: 0]
      consumedRanks[attachment.identity] = occurrence + 1
      let ranks = ranksByIdentity[attachment.identity] ?? []
      // An attachment whose identity no longer appears in the draw tree keeps
      // its relative position at the end of the array; the verification
      // oracle stays responsible for flagging it as incomplete damage.
      let rank = occurrence < ranks.count ? ranks[occurrence] : Int.max
      return (rank: rank, index: index, attachment: attachment)
    }
    return
      ranked
      .sorted { lhs, rhs in
        lhs.rank == rhs.rank ? lhs.index < rhs.index : lhs.rank < rhs.rank
      }
      .map(\.attachment)
  }

  private func freshRasterizationIfIncrementalMismatch(
    _ draw: DrawNode,
    surfaceSize: CellSize,
    incrementalSurface: RasterSurface,
    trustedDirtyRows: Set<Int>
  ) -> RasterizationResult? {
    var fresh = rasterizeFreshCollectingVisibleIdentities(
      draw,
      surfaceSize: surfaceSize
    )
    guard fresh.surface != incrementalSurface else {
      return nil
    }

    let mismatchedRows = fresh.surface.cells.indices.filter { row in
      row >= incrementalSurface.cells.count
        || fresh.surface.cells[row] != incrementalSurface.cells[row]
    }
    fresh.incrementalMismatch = IncrementalRasterMismatch(
      mismatchedRows: mismatchedRows,
      evidence: Self.incrementalMismatchEvidence(
        mismatchedRows: mismatchedRows,
        incremental: incrementalSurface,
        fresh: fresh.surface,
        trustedDirtyRows: trustedDirtyRows
      )
    )
    return fresh
  }

  /// How many mismatched rows the evidence spells out cell-by-cell. The trap
  /// message is a single line in a crash report; the first few rows identify
  /// the painter, more only pad the log.
  private static let incrementalMismatchEvidenceRowLimit = 4
  private static let incrementalMismatchEvidenceColumnLimit = 8
  private static let incrementalMismatchEvidenceTextLimit = 160

  /// Builds the human-readable evidence for an incremental-vs-fresh divergence.
  ///
  /// Row text is the glyph projection of each side's cells; rows whose glyphs
  /// agree while their cell styles differ are reported by column so a
  /// style-only divergence (a bold or colour that did not repaint) is named
  /// instead of looking like an empty diff.
  internal static func incrementalMismatchEvidence(
    mismatchedRows: [Int],
    incremental: RasterSurface,
    fresh: RasterSurface,
    trustedDirtyRows: Set<Int>
  ) -> String {
    var parts: [String] = []
    parts.append("trusted damage rows \(trustedDirtyRows.sorted())")
    if mismatchedRows.isEmpty {
      if incremental.imageAttachments != fresh.imageAttachments {
        parts.append(
          "image attachments diverged (incremental \(incremental.imageAttachments.count), "
            + "fresh \(fresh.imageAttachments.count))"
        )
      }
      if incremental.attachments != fresh.attachments {
        parts.append(
          "attachments diverged (incremental \(incremental.attachments.count), "
            + "fresh \(fresh.attachments.count))"
        )
      }
      if incremental.metadata != fresh.metadata {
        parts.append("metadata diverged")
      }
      if incremental.size != fresh.size {
        parts.append("size diverged (incremental \(incremental.size), fresh \(fresh.size))")
      }
      return parts.joined(separator: "; ")
    }
    for row in mismatchedRows.prefix(incrementalMismatchEvidenceRowLimit) {
      let incrementalRow = row < incremental.cells.count ? incremental.cells[row] : []
      let freshRow = row < fresh.cells.count ? fresh.cells[row] : []
      let incrementalText = rowText(incrementalRow)
      let freshText = rowText(freshRow)
      if incrementalText == freshText {
        let width = max(incrementalRow.count, freshRow.count)
        let columns = (0..<width).filter { column in
          let lhs = column < incrementalRow.count ? incrementalRow[column] : .empty
          let rhs = column < freshRow.count ? freshRow[column] : .empty
          return lhs != rhs
        }
        let shown = columns.prefix(incrementalMismatchEvidenceColumnLimit).map(String.init)
        let suffix = columns.count > incrementalMismatchEvidenceColumnLimit ? ", …" : ""
        parts.append(
          "row \(row) glyphs agree, cell styles differ at columns "
            + "[\(shown.joined(separator: ", "))\(suffix)] text=\"\(incrementalText)\""
        )
      } else {
        parts.append(
          "row \(row) incremental=\"\(incrementalText)\" fresh=\"\(freshText)\""
        )
      }
    }
    if mismatchedRows.count > incrementalMismatchEvidenceRowLimit {
      parts.append(
        "\(mismatchedRows.count - incrementalMismatchEvidenceRowLimit) more mismatched rows"
      )
    }
    return parts.joined(separator: "; ")
  }

  private static func rowText(_ row: [RasterCell]) -> String {
    var end = row.count
    while end > 0, row[end - 1].character == " ", !row[end - 1].isContinuation,
      row[end - 1].style == nil
    {
      end -= 1
    }
    var characters: [Character] = []
    for cell in row[..<end] where !cell.isContinuation {
      characters.append(cell.character)
    }
    if characters.count > incrementalMismatchEvidenceTextLimit {
      return String(characters.prefix(incrementalMismatchEvidenceTextLimit)) + "…"
    }
    return String(characters)
  }

  private static func defaultIncrementalVerificationPolicy()
    -> IncrementalRasterVerificationPolicy
  {
    if FeatureGate.rasterVerifyIncremental.initialIsEnabled() {
      return .verifySoundDamage
    }
    if FeatureGate.rasterTrustSoundDamage.initialIsEnabled() {
      return .trustSoundDamage
    }

    #if DEBUG
      return .verifySoundDamage
    #else
      return .trustSoundDamage
    #endif
  }
}
