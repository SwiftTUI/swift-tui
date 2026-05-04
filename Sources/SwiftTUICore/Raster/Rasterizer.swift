/// Converts draw commands into a terminal cell surface.
public struct Rasterizer: Sendable {
  internal static let emptyCompositingStyle = ResolvedTextStyle()
  internal enum ResolvedShapeColorMode {
    case constant(Color?)
    case sampled(LinearGradient)
    case sampledRadial(RadialGradient)
    case tile(TileStyle)
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
  ) -> (
    surface: RasterSurface,
    visibleIdentities: Set<Identity>,
    presentationDamage: PresentationDamage?
  ) {
    let extent = maximumExtent(for: draw, clip: nil)
    let surfaceSize = CellSize(
      width: max(extent.x, max(0, minimumSize.width)),
      height: max(extent.y, max(0, minimumSize.height))
    )
    guard surfaceSize.width > 0, surfaceSize.height > 0 else {
      return (RasterSurface(), [], damage)
    }

    let dirtyRows: Set<Int>?
    let damageToRefine: PresentationDamage?
    var cells: [[RasterCell]]
    var imageAttachments: [RasterImageAttachment]

    if let previousSurface, let damage,
      previousSurface.size == surfaceSize,
      !damage.dirtyRows.isEmpty
    {
      cells = previousSurface.cells
      imageAttachments = []
      dirtyRows = damage.dirtyRows
      damageToRefine = damage
      clear(cells: &cells, for: damage, surfaceWidth: surfaceSize.width)
    } else {
      cells = Array(
        repeating: Array(repeating: RasterCell.empty, count: surfaceSize.width),
        count: surfaceSize.height
      )
      imageAttachments = []
      dirtyRows = nil
      damageToRefine = nil
    }

    var visibleIdentities: Set<Identity> = []

    // Pre-compute the dirty-row range once so the per-node culling check
    // in `paint(node:...)` is O(1) instead of O(|dirtyRows|).
    let dirtyRowRange: (min: Int, max: Int)?
    if let dirtyRows, let lo = dirtyRows.min(), let hi = dirtyRows.max() {
      dirtyRowRange = (min: lo, max: hi)
    } else {
      dirtyRowRange = nil
    }

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

    let refinedDamage =
      if let previousSurface, let damageToRefine {
        refinedPresentationDamage(
          from: damageToRefine,
          previousSurface: previousSurface,
          currentSurface: surface
        )
      } else {
        damage
      }

    return (
      surface,
      visibleIdentities,
      refinedDamage
    )
  }
}

