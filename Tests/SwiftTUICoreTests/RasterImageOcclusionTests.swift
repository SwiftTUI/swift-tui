import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Rasterization must fold paint order back into image attachments: cell
/// content painted after an image (a presentation surface, an overlay)
/// occludes it, and terminal graphics protocols cannot express that stacking
/// at draw time, so the attachment itself carries the trimmed rect.
@Suite
struct RasterImageOcclusionTests {
  @Test("cells painted after an image trim its attachment")
  func cellsPaintedAfterImageTrimAttachment() throws {
    let imageBounds = CellRect(
      origin: .init(x: 1, y: 1), size: .init(width: 4, height: 4))
    let overlayBounds = CellRect(
      origin: .init(x: 0, y: 4), size: .init(width: 6, height: 2))
    let surface = Rasterizer().rasterize(
      occlusionRoot(children: [
        occlusionImageNode(id: "trimmed", bounds: imageBounds),
        occlusionFillNode(id: "overlay", bounds: overlayBounds),
      ])
    )

    let attachment = try #require(surface.imageAttachments.first)
    #expect(attachment.visibleBounds == imageBounds)
    #expect(
      attachment.unoccludedVisibleBounds
        == CellRect(origin: .init(x: 1, y: 1), size: .init(width: 4, height: 3))
    )
    #expect(
      attachment.effectiveVisibleBounds
        == CellRect(origin: .init(x: 1, y: 1), size: .init(width: 4, height: 3))
    )
  }

  @Test("cells painted before an image do not trim it")
  func cellsPaintedBeforeImageDoNotTrim() throws {
    let imageBounds = CellRect(
      origin: .init(x: 1, y: 1), size: .init(width: 4, height: 4))
    let surface = Rasterizer().rasterize(
      occlusionRoot(children: [
        occlusionFillNode(
          id: "background",
          bounds: .init(origin: .zero, size: .init(width: 6, height: 6))
        ),
        occlusionImageNode(id: "above-background", bounds: imageBounds),
      ])
    )

    let attachment = try #require(surface.imageAttachments.first)
    #expect(attachment.unoccludedVisibleBounds == nil)
    #expect(attachment.effectiveVisibleBounds == imageBounds)
  }

  @Test("a fully covered image carries an empty unoccluded rect")
  func fullyCoveredImageCarriesEmptyUnoccludedRect() throws {
    let imageBounds = CellRect(
      origin: .init(x: 1, y: 1), size: .init(width: 4, height: 4))
    let surface = Rasterizer().rasterize(
      occlusionRoot(children: [
        occlusionImageNode(id: "covered", bounds: imageBounds),
        occlusionFillNode(id: "cover", bounds: imageBounds),
      ])
    )

    let attachment = try #require(surface.imageAttachments.first)
    let unoccluded = try #require(attachment.unoccludedVisibleBounds)
    #expect(unoccluded.isEmpty)
    #expect(attachment.effectiveVisibleBounds.isEmpty)
  }

  @Test("a corner overlap keeps the largest edge remainder")
  func cornerOverlapKeepsLargestEdgeRemainder() throws {
    let imageBounds = CellRect(
      origin: .zero, size: .init(width: 4, height: 4))
    let surface = Rasterizer().rasterize(
      occlusionRoot(children: [
        occlusionImageNode(id: "corner", bounds: imageBounds),
        occlusionFillNode(
          id: "corner-overlay",
          bounds: .init(origin: .init(x: 2, y: 2), size: .init(width: 4, height: 4))
        ),
      ])
    )

    let attachment = try #require(surface.imageAttachments.first)
    // The visible remainder is L-shaped; the trim keeps one rect. The top
    // band (4×2) and left band (2×4) tie on area and the vertical remainder
    // is considered first.
    #expect(
      attachment.unoccludedVisibleBounds
        == CellRect(origin: .zero, size: .init(width: 4, height: 2))
    )
  }

  @Test("blend-effect fragments do not trim images beneath them")
  func blendEffectFragmentsDoNotTrim() throws {
    let imageBounds = CellRect(
      origin: .init(x: 1, y: 1), size: .init(width: 4, height: 4))
    let surface = Rasterizer().rasterize(
      occlusionRoot(children: [
        occlusionImageNode(id: "blended-under", bounds: imageBounds),
        occlusionFillNode(
          id: "blend-overlay",
          bounds: imageBounds,
          drawEffects: .init([.blendMode(.screen)])
        ),
      ])
    )

    let attachment = try #require(surface.imageAttachments.first)
    #expect(attachment.unoccludedVisibleBounds == nil)
  }

  @Test("the sidecar's recorded image layer stays untrimmed")
  func sidecarImageLayerStaysUntrimmed() throws {
    let imageBounds = CellRect(
      origin: .init(x: 1, y: 1), size: .init(width: 4, height: 4))
    let surface = Rasterizer().rasterize(
      occlusionRoot(children: [
        occlusionImageNode(id: "sidecar", bounds: imageBounds),
        occlusionFillNode(id: "sidecar-overlay", bounds: imageBounds),
      ])
    )

    // Layered hosts composite the sidecar in paint order and need no trim;
    // it also keys next frame's retained-layer matching, so it must keep the
    // pristine value the recorder captured.
    let imageLayer = try #require(
      surface.presentationLayers.first { layer in
        if case .image = layer.content { return true }
        return false
      }
    )
    guard case .image(let recorded) = imageLayer.content else {
      Issue.record("expected an image layer")
      return
    }
    #expect(recorded.unoccludedVisibleBounds == nil)
    #expect(surface.imageAttachments.first?.unoccludedVisibleBounds != nil)
  }
}

private func occlusionRoot(
  width: Int = 6,
  height: Int = 6,
  children: [DrawNode]
) -> DrawNode {
  DrawNode(
    identity: testIdentity("ImageOcclusionRoot"),
    bounds: .init(origin: .zero, size: .init(width: width, height: height)),
    children: children
  )
}

private func occlusionImageNode(
  id: String,
  bounds: CellRect
) -> DrawNode {
  let identity = testIdentity("ImageOcclusion", id)
  return DrawNode(
    identity: identity,
    bounds: bounds,
    commands: [
      .image(
        bounds: bounds,
        identity: identity,
        payload: .init(source: .path("\(id).png"))
      )
    ]
  )
}

private func occlusionFillNode(
  id: String,
  bounds: CellRect,
  drawEffects: DrawEffects = .init()
) -> DrawNode {
  DrawNode(
    identity: testIdentity("ImageOcclusionFill", id),
    bounds: bounds,
    drawEffects: drawEffects,
    commands: [
      .fill(
        bounds: bounds,
        geometry: .rectangle,
        insetAmount: 0,
        style: .color(.red),
        mode: .full
      )
    ]
  )
}
