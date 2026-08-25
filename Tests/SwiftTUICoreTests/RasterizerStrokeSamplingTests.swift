import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

// Regression coverage for GitHub issue SwiftTUI/swift-tui#5.
//
// A rectangle stroke with no explicit background infers each edge cell's
// background from the neighbouring cell *outside* the ring (top edge reads the
// row above, bottom edge the row below). That read depends on paint order: a
// fresh raster samples whatever earlier commands painted there, while an
// incremental raster's clean rows hold the previous frame's *final* cells —
// including ink from commands that paint after the stroke. A ring whose edge
// row is dirty but whose sampled row is clean therefore repaints against
// different neighbour state than a fresh raster and diverges (the reported
// shape: a focus-ring overlay above a Button inside a sheet). The rasterizer
// closes the dirty set over those sampled rows so both paths replay them in
// authored order.

@Suite
struct RasterizerStrokeSamplingTests {
  @Test("an incremental raster replays the rows a repainting stroke edge samples")
  func incrementalRasterReplaysSampledRows() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let size = CellSize(width: 10, height: 6)

    // A surface fill, a ring on rows 1...3, a label inside it, and a "button"
    // painted after the ring whose fill sits directly under the ring's
    // bottom-left corner (row 4, columns 0...3).
    func tree(label: String) -> DrawNode {
      strokeSamplingRoot(
        size: size,
        children: [
          strokeSamplingFill(id: "surface", bounds: strokeSamplingRect(0, 0, 10, 6), color: .blue),
          strokeSamplingStroke(id: "ring", bounds: strokeSamplingRect(0, 1, 8, 3)),
          strokeSamplingText(id: "label", bounds: strokeSamplingRect(1, 2, 6, 1), text: label),
          strokeSamplingFill(id: "button", bounds: strokeSamplingRect(0, 4, 4, 1), color: .red),
        ]
      )
    }
    let previous = tree(label: "red")
    let current = tree(label: "green")

    let previousSurface = rasterizer.rasterize(previous, minimumSize: size)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: size,
      previousSurface: nil,
      damage: nil
    )
    // The label on row 2 changed; the draw-tree diff dilates that by one cell
    // on every side, so the ring's edge rows are dirty but row 4 is not.
    let verified = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: size,
      previousSurface: previousSurface,
      damage: .init(textRows: [1, 2, 3].map { .init(row: $0) })
    )

    #expect(
      verified.incrementalMismatch == nil,
      "incremental raster diverged: \(verified.incrementalMismatch?.evidence ?? "")"
    )
    #expect(verified.surface == fresh.surface)
    #expect(verified.path == .incremental)
  }

  @Test("the closure adds only the rows a dirty stroke edge samples")
  func closureAddsOnlySampledRows() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let size = CellSize(width: 10, height: 8)
    let ring = strokeSamplingRoot(
      size: size,
      children: [strokeSamplingStroke(id: "ring", bounds: strokeSamplingRect(0, 2, 8, 3))]
    )

    // A dirty middle row repaints only the left/right glyphs, which sample
    // sideways on their own row: nothing to add.
    #expect(
      rasterizer.strokeSamplingDamageClosure([3], draw: ring, surfaceHeight: size.height) == [3]
    )
    // The top edge (row 2) reads the row above; the bottom edge (row 4) the
    // row below.
    #expect(
      rasterizer.strokeSamplingDamageClosure([2], draw: ring, surfaceHeight: size.height)
        == [1, 2]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([4], draw: ring, surfaceHeight: size.height)
        == [4, 5]
    )
    // Rows outside the ring never trigger it.
    #expect(
      rasterizer.strokeSamplingDamageClosure([6], draw: ring, surfaceHeight: size.height) == [6]
    )
  }

  @Test("the closure clamps to the surface and skips explicit backgrounds")
  func closureClampsAndSkipsExplicitBackgrounds() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let size = CellSize(width: 10, height: 3)

    // A ring flush with the surface edges has nothing above or below to read.
    let flush = strokeSamplingRoot(
      size: size,
      children: [strokeSamplingStroke(id: "ring", bounds: strokeSamplingRect(0, 0, 8, 3))]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([0, 2], draw: flush, surfaceHeight: size.height)
        == [0, 2]
    )

    // An explicit per-side background never samples.
    let explicit = strokeSamplingRoot(
      size: CellSize(width: 10, height: 8),
      children: [
        strokeSamplingStroke(
          id: "ring",
          bounds: strokeSamplingRect(0, 2, 8, 3),
          backgroundStyle: BorderBackgroundStyle(Color.green)
        )
      ]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([2, 4], draw: explicit, surfaceHeight: 8)
        == [2, 4]
    )

    // Curved geometry strokes on the Braille canvas and never samples.
    let curved = strokeSamplingRoot(
      size: CellSize(width: 10, height: 8),
      children: [
        strokeSamplingStroke(
          id: "ring",
          bounds: strokeSamplingRect(0, 2, 8, 3),
          geometry: .capsule
        )
      ]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([2, 4], draw: curved, surfaceHeight: 8)
        == [2, 4]
    )
  }

  @Test("inner half-block strokes sample inside as well as outside")
  func innerHalfBlockSamplesBothSides() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let ring = strokeSamplingRoot(
      size: CellSize(width: 10, height: 8),
      children: [
        strokeSamplingStroke(
          id: "ring",
          bounds: strokeSamplingRect(0, 2, 8, 4),
          strokeStyle: .innerHalfBlock
        )
      ]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([2], draw: ring, surfaceHeight: 8) == [1, 2, 3]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([5], draw: ring, surfaceHeight: 8) == [4, 5, 6]
    )
  }

  @Test("a clip decides whether an edge writes; a nested clip replaces the outer one")
  func clipDecidesWhetherAnEdgeWrites() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let size = CellSize(width: 10, height: 8)
    let ring = strokeSamplingRect(0, 2, 8, 3)

    // Clipped to rows 0..<3: the top edge (row 2) writes and samples row 1;
    // the bottom edge (row 4) never writes, so it never samples.
    let clipped = strokeSamplingRoot(
      size: size,
      children: [
        DrawNode(
          identity: testIdentity("StrokeSampling", "clipped"),
          bounds: strokeSamplingRect(0, 0, 10, 8),
          commands: [
            .clip(
              bounds: strokeSamplingRect(0, 0, 10, 3),
              child: strokeSamplingStrokeCommand(bounds: ring)
            )
          ]
        )
      ]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([2], draw: clipped, surfaceHeight: size.height)
        == [1, 2]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([4], draw: clipped, surfaceHeight: size.height)
        == [4]
    )

    // The paint walk replaces the clip for a nested `.clip` command rather
    // than intersecting: an inner clip wider than the outer one lets the
    // bottom edge write, so it samples row 5.
    let nested = strokeSamplingRoot(
      size: size,
      children: [
        DrawNode(
          identity: testIdentity("StrokeSampling", "nested"),
          bounds: strokeSamplingRect(0, 0, 10, 8),
          commands: [
            .clip(
              bounds: strokeSamplingRect(0, 0, 10, 3),
              child: .clip(
                bounds: strokeSamplingRect(0, 0, 10, 8),
                child: strokeSamplingStrokeCommand(bounds: ring)
              )
            )
          ]
        )
      ]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([4], draw: nested, surfaceHeight: size.height)
        == [4, 5]
    )
  }

  @Test("the closure reaches a fixpoint through stacked strokes and post-commands")
  func closureReachesFixpoint() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    // Ring A on rows 1...3 whose bottom edge samples row 4; row 4 is the
    // bottom edge of a one-row-taller ring B (rows 2...4) carried as a
    // post-command, which in turn samples row 5.
    let root = strokeSamplingRoot(
      size: CellSize(width: 10, height: 8),
      children: [
        strokeSamplingStroke(id: "a", bounds: strokeSamplingRect(0, 1, 8, 3)),
        DrawNode(
          identity: testIdentity("StrokeSampling", "b"),
          bounds: strokeSamplingRect(0, 2, 8, 3),
          postCommands: [strokeSamplingStrokeCommand(bounds: strokeSamplingRect(0, 2, 8, 3))]
        ),
      ]
    )
    #expect(
      rasterizer.strokeSamplingDamageClosure([3], draw: root, surfaceHeight: 8) == [3, 4, 5]
    )
  }
}

// MARK: - Fixtures

private func strokeSamplingRect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CellRect {
  CellRect(origin: .init(x: x, y: y), size: .init(width: width, height: height))
}

private func strokeSamplingRoot(size: CellSize, children: [DrawNode]) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeSamplingRoot"),
    bounds: .init(origin: .zero, size: size),
    children: children
  )
}

private func strokeSamplingFill(id: String, bounds: CellRect, color: Color) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeSampling", id),
    bounds: bounds,
    commands: [
      .fill(
        bounds: bounds,
        geometry: .rectangle,
        insetAmount: 0,
        style: AnyShapeStyle(color),
        mode: .full
      )
    ]
  )
}

private func strokeSamplingStrokeCommand(
  bounds: CellRect,
  geometry: ShapeGeometry = .roundedRectangle(cornerRadius: 1),
  strokeStyle: StrokeStyle = .rounded,
  backgroundStyle: BorderBackgroundStyle? = nil
) -> DrawCommand {
  .stroke(
    bounds: bounds,
    geometry: geometry,
    insetAmount: 0,
    style: AnyShapeStyle(Color.white),
    strokeStyle: strokeStyle,
    strokeBorder: true,
    backgroundStyle: backgroundStyle
  )
}

private func strokeSamplingStroke(
  id: String,
  bounds: CellRect,
  geometry: ShapeGeometry = .roundedRectangle(cornerRadius: 1),
  strokeStyle: StrokeStyle = .rounded,
  backgroundStyle: BorderBackgroundStyle? = nil
) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeSampling", id),
    bounds: bounds,
    commands: [
      strokeSamplingStrokeCommand(
        bounds: bounds,
        geometry: geometry,
        strokeStyle: strokeStyle,
        backgroundStyle: backgroundStyle
      )
    ]
  )
}

private func strokeSamplingText(id: String, bounds: CellRect, text: String) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeSampling", id),
    bounds: bounds,
    commands: [
      .text(
        bounds: bounds,
        content: text,
        style: .init(),
        lineLimit: nil,
        truncationMode: .tail,
        wrappingStrategy: .wordBoundary
      )
    ]
  )
}
