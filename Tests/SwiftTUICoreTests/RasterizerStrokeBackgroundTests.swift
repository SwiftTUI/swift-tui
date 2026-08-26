import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

// A stroke glyph never reads another cell. With no explicit per-side
// background it carries no background of its own, and `write` composites it
// over whatever the cell already holds — so a ring keeps the fill or surface
// beneath it and nothing from a neighbouring row leaks in.
//
// The painter used to infer an edge's background from the cell *outside* the
// ring (the top edge read the row above, the bottom edge the row below). That
// let a highlighted row above a control bleed into the control's top edge,
// and because the read crossed rows it made the incremental raster diverge
// from a fresh one whenever a later-painted control sat under the ring
// (SwiftTUI/swift-tui#5). Both are pinned here.

@Suite
struct RasterizerStrokeBackgroundTests {
  @Test("a stroke keeps the background beneath it and ignores its neighbours")
  func strokeKeepsTheBackgroundBeneathIt() {
    let rasterizer = Rasterizer()
    let size = CellSize(width: 10, height: 6)
    // A red band on row 0 directly above the ring, a blue fill under the
    // ring's left half only, and a green band on row 4 directly below it.
    let root = strokeBackgroundRoot(
      size: size,
      children: [
        strokeBackgroundFill(id: "above", bounds: strokeBackgroundRect(0, 0, 10, 1), color: .red),
        strokeBackgroundFill(id: "under", bounds: strokeBackgroundRect(0, 1, 4, 3), color: .blue),
        strokeBackgroundFill(id: "below", bounds: strokeBackgroundRect(0, 4, 10, 1), color: .green),
        strokeBackgroundStroke(id: "ring", bounds: strokeBackgroundRect(0, 1, 8, 3)),
      ]
    )
    let surface = rasterizer.rasterize(root, minimumSize: size)

    #expect(surface.lines[1] == "╭──────╮")
    #expect(surface.lines[3] == "╰──────╯")
    // Ring cells over the blue fill keep blue; ring cells on bare surface stay
    // bare. Neither edge takes the band beside it.
    #expect(surface.cells[1][0].style?.backgroundColor == Color.blue)
    #expect(surface.cells[1][3].style?.backgroundColor == Color.blue)
    #expect(surface.cells[1][4].style?.backgroundColor == nil)
    #expect(surface.cells[1][7].style?.backgroundColor == nil)
    #expect(surface.cells[2][0].style?.backgroundColor == Color.blue)
    #expect(surface.cells[2][7].style?.backgroundColor == nil)
    #expect(surface.cells[3][0].style?.backgroundColor == Color.blue)
    #expect(surface.cells[3][3].style?.backgroundColor == Color.blue)
    #expect(surface.cells[3][4].style?.backgroundColor == nil)
    #expect(surface.cells[3][7].style?.backgroundColor == nil)
    // The bands themselves are untouched.
    #expect(surface.cells[0][5].style?.backgroundColor == Color.red)
    #expect(surface.cells[4][5].style?.backgroundColor == Color.green)
  }

  @Test("an explicit per-side background still styles the ring")
  func explicitBackgroundStylesTheRing() {
    let rasterizer = Rasterizer()
    let size = CellSize(width: 10, height: 5)
    let root = strokeBackgroundRoot(
      size: size,
      children: [
        strokeBackgroundFill(id: "under", bounds: strokeBackgroundRect(0, 1, 8, 3), color: .blue),
        strokeBackgroundStroke(
          id: "ring",
          bounds: strokeBackgroundRect(0, 1, 8, 3),
          backgroundStyle: BorderBackgroundStyle(
            top: Color.yellow,
            right: Color.red,
            bottom: Color.green,
            left: Color.magenta
          )
        ),
      ]
    )
    let surface = rasterizer.rasterize(root, minimumSize: size)

    #expect(surface.cells[1][3].style?.backgroundColor == Color.yellow)
    #expect(surface.cells[2][7].style?.backgroundColor == Color.red)
    #expect(surface.cells[3][3].style?.backgroundColor == Color.green)
    #expect(surface.cells[2][0].style?.backgroundColor == Color.magenta)
    #expect(surface.cells[2][3].style?.backgroundColor == Color.blue)
  }

  @Test("an incremental raster with a ring above a later-painted fill matches a fresh raster")
  func incrementalRasterMatchesFreshRasterAroundARing() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let size = CellSize(width: 10, height: 6)

    // The swift-tui#5 shape: a surface fill, a ring on rows 1...3, a label
    // inside it, and a "button" painted after the ring whose fill sits
    // directly under the ring's bottom-left corner (row 4, columns 0...3).
    func tree(label: String) -> DrawNode {
      strokeBackgroundRoot(
        size: size,
        children: [
          strokeBackgroundFill(id: "surface", bounds: strokeBackgroundRect(0, 0, 10, 6), color: .blue),
          strokeBackgroundStroke(id: "ring", bounds: strokeBackgroundRect(0, 1, 8, 3)),
          strokeBackgroundText(id: "label", bounds: strokeBackgroundRect(1, 2, 6, 1), text: label),
          strokeBackgroundFill(id: "button", bounds: strokeBackgroundRect(0, 4, 4, 1), color: .red),
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
    // on every side, so the ring's edge rows are dirty but row 4 is not. The
    // ring's bottom edge repaints without reading row 4, so nothing has to
    // grow the dirty set for it.
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
    // The ring's bottom edge sits on the surface fill, not the button's.
    #expect(verified.surface.cells[3][0].style?.backgroundColor == Color.blue)
  }
}

// MARK: - Fixtures

private func strokeBackgroundRect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CellRect {
  CellRect(origin: .init(x: x, y: y), size: .init(width: width, height: height))
}

private func strokeBackgroundRoot(size: CellSize, children: [DrawNode]) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeBackgroundRoot"),
    bounds: .init(origin: .zero, size: size),
    children: children
  )
}

private func strokeBackgroundFill(id: String, bounds: CellRect, color: Color) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeBackground", id),
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

private func strokeBackgroundStroke(
  id: String,
  bounds: CellRect,
  backgroundStyle: BorderBackgroundStyle? = nil
) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeBackground", id),
    bounds: bounds,
    commands: [
      .stroke(
        bounds: bounds,
        geometry: .roundedRectangle(cornerRadius: 1),
        insetAmount: 0,
        style: AnyShapeStyle(Color.white),
        strokeStyle: .rounded,
        strokeBorder: true,
        backgroundStyle: backgroundStyle
      )
    ]
  )
}

private func strokeBackgroundText(id: String, bounds: CellRect, text: String) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeBackground", id),
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
