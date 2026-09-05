import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUIRuntime

/// R3.2b: the draw-walk translation plan and the raster-tier band blit.
///
/// The soundness pin is the F13 shape: a blitted surface must equal a fresh
/// rasterization of the current draw tree cell-for-cell, with the blit path
/// reporting `.incrementalTranslated` (a `.incrementalRepaired` result means
/// the oracle caught an unsound serve). The identity pin is the R3.2c
/// premise: served rows keep the previous surface's row-buffer identity at
/// their new y.
@Suite
struct RasterizerTranslationBlitTests {
  // MARK: - Fixture

  /// Surface 12×14. Band (2,2)-(10,12): rows 2..<12, columns 2..<10.
  /// A static ring at (1,1,10,12) draws perimeter chrome: its left/right
  /// strips sit in the flank columns (row-invariant), its top/bottom strips
  /// dilate one row into the band. Content rows scroll by one (dy = -1);
  /// a selection background moves from dataset row 13 to dataset row 14.
  private static let surfaceSize = CellSize(width: 12, height: 14)
  private static let band = CellRect(
    origin: CellPoint(x: 2, y: 2),
    size: CellSize(width: 8, height: 10)
  )
  private static let dy = -1

  private static func candidate() -> CommittedScrollTranslation {
    CommittedScrollTranslation(
      routeIdentity: testIdentity("Fixture", "List"),
      band: band,
      dy: dy
    )
  }

  private static func rowNode(
    dataset: Int,
    y: Int,
    selected: Bool
  ) -> DrawNode {
    let bounds = CellRect(
      origin: CellPoint(x: 2, y: y),
      size: CellSize(width: 8, height: 1)
    )
    var commands: [DrawCommand] = []
    if selected {
      commands.append(
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: .semantic(.selection),
          mode: .full
        )
      )
    }
    commands.append(
      .text(
        bounds: bounds,
        content: "line \(dataset)",
        style: TextStyle(),
        lineLimit: 1,
        truncationMode: .tail,
        wrappingStrategy: .wordBoundary
      )
    )
    return DrawNode(
      identity: testIdentity("Fixture", "List", "row\(dataset)"),
      bounds: bounds,
      commands: commands
    )
  }

  /// `firstDataset` is the dataset row shown at the top band row;
  /// `selectedDataset` carries the moving selection background.
  private static func drawTree(
    firstDataset: Int,
    selectedDataset: Int,
    flankMarkRow: Int? = nil
  ) -> DrawNode {
    let ring = DrawNode(
      identity: testIdentity("Fixture", "Ring"),
      bounds: CellRect(origin: CellPoint(x: 1, y: 1), size: CellSize(width: 10, height: 12)),
      commands: [
        .stroke(
          bounds: CellRect(origin: CellPoint(x: 1, y: 1), size: CellSize(width: 10, height: 12)),
          geometry: .rectangle,
          insetAmount: 0,
          style: .semantic(.separator),
          strokeStyle: StrokeStyle(borderSet: .single),
          strokeBorder: false
        )
      ]
    )
    let rows = (0..<10).map { index in
      rowNode(
        dataset: firstDataset + index,
        y: 2 + index,
        selected: firstDataset + index == selectedDataset
      )
    }
    let list = DrawNode(
      identity: testIdentity("Fixture", "List"),
      bounds: Self.band,
      children: rows
    )
    var children: [DrawNode] = [
      DrawNode(
        identity: testIdentity("Fixture", "Header"),
        bounds: CellRect(origin: .zero, size: CellSize(width: 12, height: 1)),
        commands: [
          .text(
            bounds: CellRect(origin: .zero, size: CellSize(width: 12, height: 1)),
            content: "HEADER",
            style: TextStyle(),
            lineLimit: 1,
            truncationMode: .tail,
            wrappingStrategy: .wordBoundary
          )
        ]
      ),
      ring,
      list,
    ]
    if let flankMarkRow {
      let markBounds = CellRect(
        origin: CellPoint(x: 0, y: flankMarkRow),
        size: CellSize(width: 1, height: 1)
      )
      children.append(
        DrawNode(
          identity: testIdentity("Fixture", "FlankMark"),
          bounds: markBounds,
          commands: [
            .text(
              bounds: markBounds,
              content: "X",
              style: TextStyle(),
              lineLimit: 1,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          ]
        )
      )
    }
    return DrawNode(
      identity: testIdentity("Fixture", "Root"),
      bounds: CellRect(origin: .zero, size: Self.surfaceSize),
      children: children
    )
  }

  private static func rowBufferAddress(_ row: [RasterCell]) -> UInt {
    unsafe row.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
  }

  // MARK: - Plan production

  @Test("the walk serves interior rows and repaints exposure, selection, and edge dilation")
  func planServesInteriorRows() throws {
    let previous = Self.drawTree(firstDataset: 10, selectedDataset: 13)
    let current = Self.drawTree(firstDataset: 11, selectedDataset: 14)

    let plan = try #require(
      FrameTailPresentationDamageResolver.translationPlan(
        candidate: Self.candidate(),
        surfaceSize: Self.surfaceSize,
        previousDraw: previous,
        currentDraw: current
      )
    )
    #expect(plan.dy == Self.dy)
    #expect(plan.band == Self.band)
    // Kept rows must at least include interior rows away from every taint
    // source; every taint source (selection move rows, band edges, exposed
    // row) must be on the repaint path.
    let translated = Set(plan.translatedRows)
    #expect(!translated.isEmpty)
    #expect(translated.isDisjoint(with: [2, 11]), "band edges repaint (ring + exposure dilation)")
    // Selection moved dataset 13→14: previous ink at y5, current ink at y5;
    // with one-row dilation rows 4...6 repaint.
    #expect(translated.isDisjoint(with: [4, 5, 6]), "selection rows repaint")
    #expect(translated.contains(8), "interior rows are served")
    #expect(translated.contains(9), "interior rows are served")
  }

  @Test("a wrong hypothesis produces no served rows")
  func wrongHypothesisDeclines() {
    let previous = Self.drawTree(firstDataset: 10, selectedDataset: 13)
    let current = Self.drawTree(firstDataset: 11, selectedDataset: 14)
    // Claim dy = -2 while the content moved one row: nothing pairs, every
    // row taints, and the plan declines.
    let wrong = CommittedScrollTranslation(
      routeIdentity: testIdentity("Fixture", "List"),
      band: Self.band,
      dy: -2
    )
    let plan = FrameTailPresentationDamageResolver.translationPlan(
      candidate: wrong,
      surfaceSize: Self.surfaceSize,
      previousDraw: previous,
      currentDraw: current
    )
    #expect(plan == nil)
  }

  // MARK: - Blit soundness (the F13 shape)

  @Test("the blitted surface equals a fresh rasterization cell-for-cell")
  func blitEqualsFreshRaster() throws {
    let previous = Self.drawTree(firstDataset: 10, selectedDataset: 13)
    let current = Self.drawTree(firstDataset: 11, selectedDataset: 14)
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)

    let previousSurface = rasterizer.rasterize(previous, minimumSize: Self.surfaceSize)
    let plan = try #require(
      FrameTailPresentationDamageResolver.translationPlan(
        candidate: Self.candidate(),
        surfaceSize: Self.surfaceSize,
        previousDraw: previous,
        currentDraw: current
      )
    )
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: Self.surfaceSize,
      previousSurface: previousSurface,
      damage: PresentationDamage(dirtyRows: Set(1..<13)),
      verifyIncrementalRasterDamage: true,
      translation: plan
    )
    // `.incrementalRepaired` would mean the F13 oracle caught an unsound
    // serve and had to repair it; the blit must be right the first time.
    #expect(result.path == .incrementalTranslated)
    let fresh = rasterizer.rasterize(current, minimumSize: Self.surfaceSize)
    #expect(result.surface == fresh)
    // The artifact damage must cover every served row — the cells at those
    // rows changed on screen.
    let artifactDamage = try #require(result.presentationDamage)
    #expect(Set(plan.translatedRows).isSubset(of: artifactDamage.dirtyRows))
  }

  @Test("served rows keep the previous surface's row-buffer identity")
  func servedRowsPreserveBufferIdentity() throws {
    let previous = Self.drawTree(firstDataset: 10, selectedDataset: 13)
    let current = Self.drawTree(firstDataset: 11, selectedDataset: 14)
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)

    let previousSurface = rasterizer.rasterize(previous, minimumSize: Self.surfaceSize)
    let plan = try #require(
      FrameTailPresentationDamageResolver.translationPlan(
        candidate: Self.candidate(),
        surfaceSize: Self.surfaceSize,
        previousDraw: previous,
        currentDraw: current
      )
    )
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: Self.surfaceSize,
      previousSurface: previousSurface,
      damage: PresentationDamage(dirtyRows: Set(1..<13)),
      translation: plan
    )
    #expect(result.path == .incrementalTranslated)
    var servedRowCount = 0
    for row in plan.translatedRows {
      let servedAddress = Self.rowBufferAddress(result.surface.cells[row])
      let sourceAddress = Self.rowBufferAddress(previousSurface.cells[row - plan.dy])
      if servedAddress == sourceAddress {
        servedRowCount += 1
      }
    }
    #expect(servedRowCount == plan.translatedRows.count, "every served row is a pointer move")
    // A repainted row must NOT share storage with any previous row.
    for row in plan.repaintRows.sorted() {
      let repaintedAddress = Self.rowBufferAddress(result.surface.cells[row])
      #expect(repaintedAddress != Self.rowBufferAddress(previousSurface.cells[row]))
    }
  }

  @Test("row-varying flank content demotes its row to the repaint path")
  func flankVariationDemotesRow() throws {
    // A one-cell "X" in the flank at row 8 makes rows sourcing from or
    // serving row 8 non-row-invariant in the flank; the blit must demote
    // them rather than smear the mark, and the surface still equals fresh.
    let previous = Self.drawTree(firstDataset: 10, selectedDataset: 13, flankMarkRow: 8)
    let current = Self.drawTree(firstDataset: 11, selectedDataset: 14, flankMarkRow: 8)
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)

    let previousSurface = rasterizer.rasterize(previous, minimumSize: Self.surfaceSize)
    let plan = try #require(
      FrameTailPresentationDamageResolver.translationPlan(
        candidate: Self.candidate(),
        surfaceSize: Self.surfaceSize,
        previousDraw: previous,
        currentDraw: current
      )
    )
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: Self.surfaceSize,
      previousSurface: previousSurface,
      damage: PresentationDamage(dirtyRows: Set(1..<13)),
      verifyIncrementalRasterDamage: true,
      translation: plan
    )
    #expect(result.path == .incrementalTranslated || result.path == .incremental)
    let fresh = rasterizer.rasterize(current, minimumSize: Self.surfaceSize)
    #expect(result.surface == fresh)
    if result.path == .incrementalTranslated {
      // Row 8 itself and the row that would source from it cannot be served.
      let servedFromEight = Self.rowBufferAddress(result.surface.cells[8 + plan.dy])
      #expect(servedFromEight != Self.rowBufferAddress(previousSurface.cells[8]))
    }
  }

  @Test("new flank ink repaints even when the previous flank was row-invariant")
  func changedFlankDemotesRow() throws {
    let previous = Self.drawTree(firstDataset: 10, selectedDataset: 13)
    let current = Self.drawTree(firstDataset: 11, selectedDataset: 14, flankMarkRow: 8)
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let previousSurface = rasterizer.rasterize(previous, minimumSize: Self.surfaceSize)
    let plan = FrameTailPresentationDamageResolver.translationPlan(
      candidate: Self.candidate(), surfaceSize: Self.surfaceSize,
      previousDraw: previous, currentDraw: current)
    #expect(plan == nil || plan?.repaintRows.contains(8) == true)
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current, minimumSize: Self.surfaceSize, previousSurface: previousSurface,
      damage: PresentationDamage(dirtyRows: Set(1..<13)),
      verifyIncrementalRasterDamage: true, translation: plan)
    #expect(result.path == .incrementalTranslated || result.path == .incremental)
    #expect(result.surface == rasterizer.rasterize(current, minimumSize: Self.surfaceSize))
    #expect(result.surface.cells[8][0].character == "X")
  }

  @Test("the walk and twin check survive deep trees on an explicit stack")
  func deepTreeSafety() throws {
    let depth = 800
    // A deep wrapper chain around one content row, translated wholesale:
    // the twin check must walk all levels iteratively and serve the row.
    func chain(rowY: Int) -> DrawNode {
      let bounds = CellRect(
        origin: CellPoint(x: 2, y: rowY),
        size: CellSize(width: 8, height: 1)
      )
      var node = DrawNode(
        identity: testIdentity("Fixture", "Chain", "leaf"),
        bounds: bounds,
        commands: [
          .text(
            bounds: bounds,
            content: "deep line",
            style: TextStyle(),
            lineLimit: 1,
            truncationMode: .tail,
            wrappingStrategy: .wordBoundary
          )
        ]
      )
      for level in 0..<depth {
        node = DrawNode(
          identity: testIdentity("Fixture", "Chain", "level\(level)"),
          bounds: bounds,
          children: [node]
        )
      }
      return DrawNode(
        identity: testIdentity("Fixture", "Root"),
        bounds: CellRect(origin: .zero, size: Self.surfaceSize),
        children: [node]
      )
    }
    let previous = chain(rowY: 7)
    let current = chain(rowY: 6)
    let plan = FrameTailPresentationDamageResolver.translationPlan(
      candidate: Self.candidate(),
      surfaceSize: Self.surfaceSize,
      previousDraw: previous,
      currentDraw: current
    )
    // The wrapper chain is one translated twin; the walk proves it without
    // recursion and serves the interior rows away from the exposure edge.
    let resolved = try #require(plan)
    #expect(Set(resolved.translatedRows).contains(6))
  }
}
