/// Folds the paint-order sidecar's stacking back into image attachments as
/// occlusion trims.
///
/// The paint walk records every cell write and every image placement into
/// `RasterSurface.presentationLayers` in paint order. Layered hosts composite
/// those layers directly, so cells painted after an image already cover it
/// there. Terminal graphics cannot express that stacking: a kitty placement
/// draws above every text cell regardless of write order, and the fallback
/// path stamps image overlay cells onto the finished grid. Without a trim,
/// content presented over an image — a command palette, a sheet — is painted
/// into the cell grid and the image is then drawn back on top of it.
///
/// The trim keeps, per attachment, the largest single rectangle of
/// `visibleBounds` left after removing each plain cell fragment recorded
/// above the image (largest-remainder edge trim). The visible remainder of a
/// partially covered image is not rectangular in general and a placement can
/// crop only one source rect, so the trim under-draws: cells the trim gives
/// up simply keep showing the content painted there, which is always sound,
/// while over-drawing (the pre-trim behavior) never is. Effect-carrying
/// fragments (blend modes) do not trim — blended stacking over images is
/// modeled by `RasterImageCompositing`, not occlusion.
///
/// Cross-frame soundness: incremental rasterization retains sidecar layers as
/// an untouched prefix. When damage intersects an image, it expands to a
/// paint-order-closed suffix before recording, so every layer that can compare
/// above the re-emitted image is recorded again in authored traversal order.
enum RasterImageOcclusion {
  /// Recomputes every attachment's `unoccludedVisibleBounds` from the
  /// sidecar. Runs after each paint (fresh and incremental); the result is a
  /// pure function of the sidecar, so retained attachments converge to the
  /// same trim they carried and the F13 incremental-vs-fresh oracle sees
  /// equal surfaces.
  static func apply(
    to attachments: inout [RasterImageAttachment],
    layers: [RasterPresentationLayer]
  ) {
    guard !attachments.isEmpty else {
      return
    }

    var occluders: [(order: Int, bounds: CellRect)] = []
    var imageOrders: [ImageLayerKey: Int] = [:]
    for layer in layers {
      switch layer.content {
      case .cells:
        if layer.effects.isEmpty, !layer.bounds.isEmpty {
          occluders.append((order: layer.order, bounds: layer.bounds))
        }
      case .image(let recorded):
        let key = ImageLayerKey(
          identity: recorded.identity,
          bounds: recorded.bounds,
          visibleBounds: recorded.visibleBounds
        )
        if imageOrders[key] == nil {
          imageOrders[key] = layer.order
        }
      }
    }

    for index in attachments.indices {
      let attachment = attachments[index]
      let key = ImageLayerKey(
        identity: attachment.identity,
        bounds: attachment.bounds,
        visibleBounds: attachment.visibleBounds
      )
      guard let imageOrder = imageOrders[key] else {
        // No recorded placement for this attachment (hand-built surface or a
        // sidecar-less raster): nothing to derive a stacking order from, so
        // leave the attachment untrimmed.
        attachments[index].unoccludedVisibleBounds = nil
        continue
      }

      var visible: CellRect? = attachment.visibleBounds
      for occluder in occluders where occluder.order > imageOrder {
        guard let current = visible else {
          break
        }
        visible = subtracting(occluder.bounds, from: current)
      }

      if let visible, visible == attachment.visibleBounds {
        attachments[index].unoccludedVisibleBounds = nil
      } else {
        attachments[index].unoccludedVisibleBounds =
          visible
          ?? CellRect(origin: attachment.visibleBounds.origin, size: .zero)
      }
    }
  }

  private struct ImageLayerKey: Hashable {
    var identity: Identity
    var bounds: CellRect
    var visibleBounds: CellRect
  }

  /// Removes `occluder` from `visible`, keeping the largest of the four edge
  /// remainders (above / below / left-of / right-of the overlap). Returns
  /// `visible` unchanged when they do not overlap and `nil` when no non-empty
  /// remainder exists.
  private static func subtracting(
    _ occluder: CellRect,
    from visible: CellRect
  ) -> CellRect? {
    let overlapMinX = max(visible.origin.x, occluder.origin.x)
    let overlapMinY = max(visible.origin.y, occluder.origin.y)
    let overlapMaxX = min(visible.maxX, occluder.maxX)
    let overlapMaxY = min(visible.maxY, occluder.maxY)
    guard overlapMinX < overlapMaxX, overlapMinY < overlapMaxY else {
      return visible
    }

    var best: CellRect?
    var bestArea = 0
    func consider(_ candidate: CellRect) {
      let area = candidate.size.width * candidate.size.height
      if area > bestArea {
        best = candidate
        bestArea = area
      }
    }

    if overlapMinY > visible.origin.y {
      consider(
        CellRect(
          origin: visible.origin,
          size: CellSize(
            width: visible.size.width,
            height: overlapMinY - visible.origin.y
          )
        )
      )
    }
    if overlapMaxY < visible.maxY {
      consider(
        CellRect(
          origin: CellPoint(x: visible.origin.x, y: overlapMaxY),
          size: CellSize(
            width: visible.size.width,
            height: visible.maxY - overlapMaxY
          )
        )
      )
    }
    if overlapMinX > visible.origin.x {
      consider(
        CellRect(
          origin: visible.origin,
          size: CellSize(
            width: overlapMinX - visible.origin.x,
            height: visible.size.height
          )
        )
      )
    }
    if overlapMaxX < visible.maxX {
      consider(
        CellRect(
          origin: CellPoint(x: overlapMaxX, y: visible.origin.y),
          size: CellSize(
            width: visible.maxX - overlapMaxX,
            height: visible.size.height
          )
        )
      )
    }
    return best
  }
}
