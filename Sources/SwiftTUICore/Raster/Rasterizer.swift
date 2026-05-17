/// Converts draw commands into a terminal cell surface.
public struct Rasterizer: Sendable {
  internal static let emptyCompositingStyle = ResolvedTextStyle()
  package typealias RasterizationResult = (
    surface: RasterSurface,
    visibleIdentities: Set<Identity>,
    presentationDamage: PresentationDamage?
  )

  internal enum ResolvedShapeColorMode {
    case constant(Color?)
    case sampled(LinearGradient)
    case sampledRadial(RadialGradient)
    case tile(TileStyle)
  }

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

  public init() {}

  /// Rasterizes a draw tree into a ``RasterSurface``.
  public func rasterize(_ draw: DrawNode) -> RasterSurface {
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
  package func rasterizeCollectingVisibleIdentities(
    _ draw: DrawNode,
    minimumSize: CellSize,
    previousSurface: RasterSurface?,
    damage: PresentationDamage?
  ) -> RasterizationResult {
    let surfaceSize = rasterSurfaceSize(for: draw, minimumSize: minimumSize)
    guard surfaceSize.width > 0, surfaceSize.height > 0 else {
      return (RasterSurface(), [], nil)
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
        soundDamage: soundDamage
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

    paint(
      node: draw,
      cells: &cells,
      imageAttachments: &imageAttachments,
      clip: nil,
      dirtyRows: nil,
      dirtyRowRange: nil,
      visibleIdentities: &visibleIdentities
    )

    return (
      RasterSurface(
        size: surfaceSize,
        cells: cells,
        imageAttachments: imageAttachments
      ),
      visibleIdentities,
      nil
    )
  }

  private func rasterizeIncrementallyCollectingVisibleIdentities(
    _ draw: DrawNode,
    surfaceSize: CellSize,
    previousSurface: RasterSurface,
    soundDamage: SoundRasterDamage
  ) -> RasterizationResult {
    let damage = soundDamage.presentationDamage
    let dirtyRows = soundDamage.dirtyRows
    var cells = previousSurface.cells
    var imageAttachments = previousSurface.imageAttachments.filter { attachment in
      !visibleBounds(attachment.visibleBounds, intersectsAnyOf: dirtyRows)
    }
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
      visibleIdentities: &visibleIdentities
    )

    let surface = RasterSurface(
      size: surfaceSize,
      cells: cells,
      imageAttachments: imageAttachments
    )

    return (
      surface,
      visibleIdentities,
      refinedPresentationDamage(
        from: damage,
        previousSurface: previousSurface,
        currentSurface: surface
      )
    )
  }
}
