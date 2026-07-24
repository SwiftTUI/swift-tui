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
    incrementalMismatch: IncrementalRasterMismatch?
  )

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
    /// Empty when only non-cell surface state (image attachments or
    /// presentation layers) diverged.
    package var mismatchedRows: [Int]

    package init(mismatchedRows: [Int]) {
      self.mismatchedRows = mismatchedRows
    }
  }

  internal indirect enum ResolvedShapeColorMode {
    case constant(Color?)
    case sampled(LinearGradient)
    case sampledRadial(RadialGradient)
    case sampledMesh(PreparedMeshGradient)
    case tile(ResolvedTileColorMode)
  }

  internal struct ResolvedTileColorMode {
    var pattern: TileStyle.Pattern
    var foreground: ResolvedShapeColorMode
    var background: ResolvedShapeColorMode?
  }

  private var incrementalVerificationPolicy: IncrementalRasterVerificationPolicy

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
    verifyIncrementalRasterDamage: Bool = false
  ) -> RasterizationResult {
    let surfaceSize = rasterSurfaceSize(for: draw, minimumSize: minimumSize)
    guard surfaceSize.width > 0, surfaceSize.height > 0 else {
      return (RasterSurface(), [], nil, nil)
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
        verifyIncrementalRasterDamage: verifyIncrementalRasterDamage
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
      dirtyRowRange: nil,
      visibleIdentities: &visibleIdentities,
      presentationRecorder: presentationRecorder
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
      nil
    )
  }

  private func rasterizeIncrementallyCollectingVisibleIdentities(
    _ draw: DrawNode,
    surfaceSize: CellSize,
    previousSurface: RasterSurface,
    soundDamage: SoundRasterDamage,
    verifyIncrementalRasterDamage: Bool = false
  ) -> RasterizationResult {
    let damage = soundDamage.presentationDamage
    let dirtyRows = soundDamage.dirtyRows
    var cells = previousSurface.cells
    var imageAttachments = previousSurface.imageAttachments.filter { attachment in
      !visibleBounds(attachment.visibleBounds, intersectsAnyOf: dirtyRows)
    }
    let presentationRecorder = RasterPresentationLayerRecorder(
      layers: previousSurface.presentationLayers.filter { layer in
        !visibleBounds(layer.bounds, intersectsAnyOf: dirtyRows)
      }
    )
    clear(cells: &cells, for: damage, surfaceWidth: surfaceSize.width)

    let dirtyRowRange: (min: Int, max: Int)
    if let lo = dirtyRows.min(), let hi = dirtyRows.max() {
      dirtyRowRange = (min: lo, max: hi)
    } else {
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
      dirtyRowRange: dirtyRowRange,
      visibleIdentities: &visibleIdentities,
      presentationRecorder: presentationRecorder
    )

    let surface = RasterSurface(
      size: surfaceSize,
      cells: cells,
      imageAttachments: imageAttachments,
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
      if let freshFallback = freshRasterizationIfIncrementalMismatch(
        draw,
        surfaceSize: surfaceSize,
        incrementalSurface: surface
      ) {
        return freshFallback
      }
    }

    return (
      surface,
      visibleIdentities,
      refinedPresentationDamage(
        from: damage,
        previousSurface: previousSurface,
        currentSurface: surface
      ),
      nil
    )
  }

  private func freshRasterizationIfIncrementalMismatch(
    _ draw: DrawNode,
    surfaceSize: CellSize,
    incrementalSurface: RasterSurface
  ) -> RasterizationResult? {
    var fresh = rasterizeFreshCollectingVisibleIdentities(
      draw,
      surfaceSize: surfaceSize
    )
    guard fresh.surface != incrementalSurface else {
      return nil
    }

    fresh.incrementalMismatch = IncrementalRasterMismatch(
      mismatchedRows: fresh.surface.cells.indices.filter { row in
        row >= incrementalSurface.cells.count
          || fresh.surface.cells[row] != incrementalSurface.cells[row]
      }
    )
    return fresh
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
