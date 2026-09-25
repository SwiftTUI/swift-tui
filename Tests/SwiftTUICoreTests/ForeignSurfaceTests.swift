import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Foreign surface rasterization")
struct ForeignSurfaceTests {
  struct StaticPayload: ForeignSurfacePayload {
    let grid: ForeignGrid
  }

  @Test("foreign surface cells appear at the right bounds")
  func foreignSurfaceBlit() {
    let cells: [[RasterCell]] = [
      [RasterCell(character: "A"), RasterCell(character: "B")],
      [RasterCell(character: "C"), RasterCell(character: "D")],
    ]
    let payload = StaticPayload(
      grid: ForeignGrid(
        size: CellSize(width: 2, height: 2),
        cells: cells
      )
    )
    let command: DrawCommand = .foreignSurface(
      bounds: CellRect(origin: CellPoint(x: 1, y: 1), size: CellSize(width: 2, height: 2)),
      payload: payload
    )

    let rasterizer = Rasterizer()
    let surface = rasterizer.rasterize(
      DrawNode(
        identity: testIdentity("root"),
        bounds: CellRect(origin: .zero, size: CellSize(width: 4, height: 4)),
        commands: [command]
      )
    )

    #expect(surface.cells[1][1].character == "A")
    #expect(surface.cells[1][2].character == "B")
    #expect(surface.cells[2][1].character == "C")
    #expect(surface.cells[2][2].character == "D")
    #expect(surface.cells[0][0].character == RasterCell.empty.character)
  }

  @Test("foreign surface commands compare the grid they paint")
  func foreignSurfaceCommandEquality() {
    let bounds = CellRect(origin: .zero, size: CellSize(width: 2, height: 1))
    func command(_ characters: String) -> DrawCommand {
      .foreignSurface(
        bounds: bounds,
        payload: StaticPayload(
          grid: ForeignGrid(
            size: bounds.size, cells: [characters.map { RasterCell(character: $0) }])))
    }
    #expect(command("AB") == command("AB"))
    #expect(command("AB") != command("AC"))
  }
}

/// F167: the non-blend foreign-surface fast path copied source cells
/// verbatim. A wide glyph's continuation cell carries its lead's column in
/// SOURCE-grid coordinates, so at a non-zero origin the copied continuation
/// pointed at the wrong destination column — span normalization and damage
/// repair then cleared the wrong cell. And a verbatim copy over half of an
/// existing wide glyph left the other half as a stale orphan.
@Suite("Foreign surface wide-glyph correctness (F167)")
struct ForeignSurfaceWideGlyphTests {
  private func wideGlyphPayload() -> ForeignSurfaceTests.StaticPayload {
    ForeignSurfaceTests.StaticPayload(
      grid: ForeignGrid(
        size: CellSize(width: 3, height: 1),
        cells: [
          [
            RasterCell(character: "寿", spanWidth: 2),
            RasterCell(character: " ", continuationLeadX: 0),
            RasterCell(character: "!"),
          ]
        ]
      )
    )
  }

  @Test("a wide glyph's continuation translates to destination columns at a non-zero origin")
  func continuationTranslatesToDestinationColumns() {
    let command: DrawCommand = .foreignSurface(
      bounds: CellRect(origin: CellPoint(x: 3, y: 1), size: CellSize(width: 3, height: 1)),
      payload: wideGlyphPayload()
    )
    let rasterizer = Rasterizer()
    let surface = rasterizer.rasterize(
      DrawNode(
        identity: testIdentity("wideRoot"),
        bounds: CellRect(origin: .zero, size: CellSize(width: 8, height: 3)),
        commands: [command]
      )
    )

    #expect(surface.cells[1][3].character == "寿")
    #expect(surface.cells[1][3].spanWidth == 2)
    #expect(
      surface.cells[1][4].continuationLeadX == 3,
      "the continuation still points at the SOURCE column: \(String(describing: surface.cells[1][4].continuationLeadX))"
    )
    #expect(surface.cells[1][5].character == "!")
  }

  @Test("copying over half of an existing wide glyph clears the stale remainder")
  func overlapClearsStaleWideGlyphRemainder() {
    // First paint a wide glyph spanning columns 2-3, then blit a 1-column
    // foreign surface over column 2 (the lead). Column 3's continuation
    // must not survive as an orphan pointing at a non-glyph cell.
    let wideText: DrawCommand = .text(
      bounds: CellRect(origin: CellPoint(x: 2, y: 0), size: CellSize(width: 2, height: 1)),
      content: "寿",
      style: .init(),
      lineLimit: nil,
      truncationMode: .tail,
      wrappingStrategy: .wordBoundary
    )
    let overwrite: DrawCommand = .foreignSurface(
      bounds: CellRect(origin: CellPoint(x: 2, y: 0), size: CellSize(width: 1, height: 1)),
      payload: ForeignSurfaceTests.StaticPayload(
        grid: ForeignGrid(
          size: CellSize(width: 1, height: 1),
          cells: [[RasterCell(character: "N")]]
        )
      )
    )
    let rasterizer = Rasterizer()
    let surface = rasterizer.rasterize(
      DrawNode(
        identity: testIdentity("overlapRoot"),
        bounds: CellRect(origin: .zero, size: CellSize(width: 6, height: 2)),
        commands: [wideText, overwrite]
      )
    )

    #expect(surface.cells[0][2].character == "N")
    #expect(
      surface.cells[0][3].continuationLeadX == nil,
      "a stale continuation survived the overwrite: \(surface.cells[0][3])"
    )
  }
}

/// A foreign surface has no intrinsic size: like `Canvas` and raw shapes it
/// fills whatever it is proposed. Stack cross-axis reconciliation must
/// therefore re-measure it at the stack's resolved cross size; skipping it as
/// "rigid" left the surface at the zero cross it measured under an unspecified
/// proposal, so a populated grid painted no cells.
@Suite("Foreign surface stack layout")
struct ForeignSurfaceStackLayoutTests {
  @Test(
    "a foreign surface fills a cross-unspecified stack's resolved cross size",
    arguments: [Axis.horizontal, .vertical])
  func foreignSurfaceFillsStackCross(axis: Axis) {
    let foreign = ResolvedNode(
      identity: testIdentity("foreign"),
      kind: .view("ForeignSurface"),
      drawPayload: .foreignSurface(
        ForeignSurfaceTests.StaticPayload(
          grid: ForeignGrid(size: CellSize(width: 0, height: 0), cells: [])
        )
      )
    )
    let sibling = ResolvedNode(
      identity: testIdentity("sibling"),
      kind: .view("Sibling"),
      intrinsicSize: CellSize(width: 5, height: 3)
    )
    let stack = ResolvedNode(
      identity: testIdentity("stack"),
      kind: .view(axis == .horizontal ? "HStack" : "VStack"),
      children: [foreign, sibling],
      layoutBehavior: .stack(
        axis: axis,
        spacing: 0,
        horizontalAlignment: .leading,
        verticalAlignment: .top
      )
    )
    let proposal =
      axis == .horizontal
      ? ProposedSize(width: .finite(40), height: .unspecified)
      : ProposedSize(width: .unspecified, height: .finite(40))

    let measured = LayoutEngine().measure(stack, proposal: proposal)
    let foreignSize = measured.childMeasurements.first {
      $0.identity == testIdentity("foreign")
    }?.measuredSize
    let crossSize = axis == .horizontal ? foreignSize?.height : foreignSize?.width

    #expect(crossSize == (axis == .horizontal ? 3 : 5))
  }
}
