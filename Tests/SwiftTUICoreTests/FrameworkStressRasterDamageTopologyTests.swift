import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("SwiftTUI raster damage-topology stress behavior", .serialized)
struct FrameworkStressRasterDamageTopologyTests {
  @Test("stress raster damage topology 001 wide to narrow damages the departed span")
  func rasterDamageTopology001WideToNarrowDamagesDepartedSpan() {
    let previous = RasterSurface(size: .init(width: 4, height: 1), lines: ["A界B"])
    let current = RasterSurface(size: .init(width: 4, height: 1), lines: ["A語B"])
    var narrowCells = current.cells
    narrowCells[0][1] = RasterCell(character: "x")
    narrowCells[0][2] = .empty
    let narrow = RasterSurface(size: current.size, cells: narrowCells)

    #expect(rasterDamage(previous, narrow) == [.init(row: 0, columnRanges: [1..<3])])
  }

  @Test("stress raster damage topology 002 narrow to wide damages the arriving span")
  func rasterDamageTopology002NarrowToWideDamagesArrivingSpan() {
    let current = RasterSurface(size: .init(width: 4, height: 1), lines: ["A界B"])
    var narrowCells = current.cells
    narrowCells[0][1] = RasterCell(character: "x")
    narrowCells[0][2] = .empty
    let previous = RasterSurface(size: current.size, cells: narrowCells)

    #expect(rasterDamage(previous, current) == [.init(row: 0, columnRanges: [1..<3])])
  }

  @Test("stress raster damage topology 003 continuation-only style damage expands to lead")
  func rasterDamageTopology003ContinuationStyleDamageExpandsToLead() {
    let previous = RasterSurface(size: .init(width: 4, height: 1), lines: ["A界B"])
    var currentCells = previous.cells
    currentCells[0][2].style = ResolvedTextStyle(TextStyle(emphasis: .bold))
    let current = RasterSurface(size: previous.size, cells: currentCells)

    #expect(rasterDamage(previous, current) == [.init(row: 0, columnRanges: [1..<3])])
  }

  @Test("stress raster damage topology 004 adjacent wide changes merge into one span")
  func rasterDamageTopology004AdjacentWideChangesMergeIntoOneSpan() {
    let previous = RasterSurface(size: .init(width: 5, height: 1), lines: ["界語Z"])
    let current = RasterSurface(size: .init(width: 5, height: 1), lines: ["語界Z"])

    #expect(rasterDamage(previous, current) == [.init(row: 0, columnRanges: [0..<4])])
  }

  @Test("stress raster damage topology 005 short backing rows damage only missing suffix")
  func rasterDamageTopology005ShortBackingRowsDamageOnlyMissingSuffix() {
    let previous = RasterSurface(size: .init(width: 4, height: 1), lines: ["ABCD"])
    let current = RasterSurface(
      size: .init(width: 4, height: 1),
      cells: [[RasterCell(character: "A"), RasterCell(character: "B")]]
    )

    #expect(rasterDamage(previous, current) == [.init(row: 0, columnRanges: [2..<4])])
  }

  @Test("stress raster damage topology 006 negative image X clamps to column zero")
  func rasterDamageTopology006NegativeImageXClampsToZero() {
    let previous = rasterImageSurface()
    let current = rasterImageSurface(
      attachments: [
        rasterImage("006", visible: .init(x: -2, y: 1, width: 4, height: 1))
      ]
    )

    #expect(rasterDamage(previous, current) == [.init(row: 1, columnRanges: [0..<2])])
  }

  @Test("stress raster damage topology 007 negative image Y clamps to row zero")
  func rasterDamageTopology007NegativeImageYClampsToZero() {
    let previous = rasterImageSurface()
    let current = rasterImageSurface(
      attachments: [
        rasterImage("007", visible: .init(x: 2, y: -2, width: 2, height: 4))
      ]
    )

    #expect(
      rasterDamage(previous, current)
        == [
          .init(row: 0, columnRanges: [2..<4]),
          .init(row: 1, columnRanges: [2..<4]),
        ]
    )
  }

  @Test("stress raster damage topology 008 dual-negative image bounds clamp exactly")
  func rasterDamageTopology008DualNegativeImageBoundsClampExactly() {
    let previous = rasterImageSurface()
    let current = rasterImageSurface(
      attachments: [
        rasterImage("008", visible: .init(x: -3, y: -1, width: 5, height: 3))
      ]
    )

    #expect(
      rasterDamage(previous, current)
        == [
          .init(row: 0, columnRanges: [0..<2]),
          .init(row: 1, columnRanges: [0..<2]),
        ]
    )
  }

  @Test("stress raster damage topology 009 zero-area images add no phantom damage")
  func rasterDamageTopology009ZeroAreaImagesAddNoPhantomDamage() {
    let previous = rasterImageSurface()
    let current = rasterImageSurface(
      attachments: [
        rasterImage("009-width", visible: .init(x: 2, y: 1, width: 0, height: 2)),
        rasterImage("009-height", visible: .init(x: 3, y: 2, width: 2, height: 0)),
      ]
    )

    #expect(rasterDamage(previous, current).isEmpty)
  }

  @Test("stress raster damage topology 010 overlapping image motion normalizes its union")
  func rasterDamageTopology010OverlappingImageMotionNormalizesUnion() {
    let previous = rasterImageSurface(
      attachments: [rasterImage("010", visible: .init(x: 1, y: 1, width: 4, height: 1))]
    )
    let current = rasterImageSurface(
      attachments: [rasterImage("010", visible: .init(x: 3, y: 1, width: 4, height: 1))]
    )

    #expect(rasterDamage(previous, current) == [.init(row: 1, columnRanges: [1..<7])])
  }

  @Test("stress raster damage topology 011 inserted plain layers preserve significant topology")
  func rasterDamageTopology011InsertedPlainLayersPreserveSignificantTopology() {
    let image = rasterImage("011", visible: .init(x: 0, y: 0, width: 1, height: 1))
    let imageLayer = rasterImageLayer(order: 0, image: image)
    let effectLayer = rasterCellLayer(
      order: 1,
      rect: .init(x: 3, y: 1, width: 2, height: 1),
      effects: [.blendMode(.screen)]
    )
    let previous = rasterTopologySurface(layers: [imageLayer, effectLayer])
    let current = rasterTopologySurface(
      layers: [
        rasterCellLayer(order: 8, rect: .init(x: 0, y: 2, width: 8, height: 1)),
        rasterImageLayer(order: 9, image: image),
        rasterCellLayer(order: 10, rect: .init(x: 1, y: 0, width: 2, height: 1)),
        rasterCellLayer(
          order: 11,
          rect: effectLayer.bounds,
          effects: [.blendMode(.screen)]
        ),
      ]
    )

    #expect(rasterDamage(previous, current).isEmpty)
  }

  @Test("stress raster damage topology 012 removed plain layers preserve significant topology")
  func rasterDamageTopology012RemovedPlainLayersPreserveSignificantTopology() {
    let image = rasterImage("012", visible: .init(x: 1, y: 0, width: 1, height: 1))
    let effectBounds = CellRect(x: 4, y: 1, width: 2, height: 1)
    let previous = rasterTopologySurface(
      layers: [
        rasterCellLayer(order: 0, rect: .init(x: 0, y: 0, width: 8, height: 1)),
        rasterImageLayer(order: 1, image: image),
        rasterCellLayer(order: 2, rect: .init(x: 0, y: 2, width: 8, height: 1)),
        rasterCellLayer(order: 3, rect: effectBounds, effects: [.blendMode(.multiply)]),
      ]
    )
    let current = rasterTopologySurface(
      layers: [
        rasterImageLayer(order: 20, image: image),
        rasterCellLayer(order: 21, rect: effectBounds, effects: [.blendMode(.multiply)]),
      ]
    )

    #expect(rasterDamage(previous, current).isEmpty)
  }

  @Test("stress raster damage topology 013 order renumber storms remain equivalent")
  func rasterDamageTopology013OrderRenumberStormsRemainEquivalent() {
    let image = rasterImage("013", visible: .init(x: 1, y: 0, width: 2, height: 1))
    let effectBounds = CellRect(x: 5, y: 1, width: 2, height: 1)
    var previous = rasterTopologySurface(
      layers: [
        rasterImageLayer(order: 0, image: image),
        rasterCellLayer(order: 1, rect: effectBounds, effects: [.blendMode(.overlay)]),
      ]
    )

    for generation in 1...64 {
      let current = rasterTopologySurface(
        layers: [
          rasterImageLayer(order: generation * 7, image: image),
          rasterCellLayer(
            order: generation * 7 + 5,
            rect: effectBounds,
            effects: [.blendMode(.overlay)]
          ),
        ]
      )
      #expect(rasterDamage(previous, current).isEmpty)
      previous = current
    }
  }

  @Test("stress raster damage topology 014 effect order changes damage exact bounds")
  func rasterDamageTopology014EffectOrderChangesDamageExactBounds() {
    let bounds = CellRect(x: 2, y: 1, width: 3, height: 1)
    let previous = rasterTopologySurface(
      layers: [
        rasterCellLayer(
          order: 0,
          rect: bounds,
          effects: [.blendMode(.multiply), .compositingGroup]
        )
      ]
    )
    let current = rasterTopologySurface(
      layers: [
        rasterCellLayer(
          order: 0,
          rect: bounds,
          effects: [.compositingGroup, .blendMode(.multiply)]
        )
      ]
    )

    #expect(rasterDamage(previous, current) == [.init(row: 1, columnRanges: [2..<5])])
  }

  @Test("stress raster damage topology 015 moved effect bounds damage old and new clips")
  func rasterDamageTopology015MovedEffectBoundsDamageOldAndNewClips() {
    let previous = rasterTopologySurface(
      layers: [
        rasterCellLayer(
          order: 0,
          rect: .init(x: -2, y: 0, width: 4, height: 1),
          effects: [.blendMode(.screen)]
        )
      ]
    )
    let current = rasterTopologySurface(
      layers: [
        rasterCellLayer(
          order: 0,
          rect: .init(x: 5, y: 0, width: 2, height: 1),
          effects: [.blendMode(.screen)]
        )
      ]
    )

    #expect(
      rasterDamage(previous, current)
        == [.init(row: 0, columnRanges: [0..<2, 5..<7])]
    )
  }

  @Test("stress raster damage topology 016 zero-sized effects add no dirty ranges")
  func rasterDamageTopology016ZeroSizedEffectsAddNoDirtyRanges() {
    let previous = rasterTopologySurface(layers: [])
    let current = rasterTopologySurface(
      layers: [
        rasterCellLayer(
          order: 0,
          rect: .init(x: 3, y: 1, width: 0, height: 2),
          effects: [.blendMode(.screen)]
        ),
        rasterCellLayer(
          order: 1,
          rect: .init(x: 4, y: 2, width: 2, height: 0),
          effects: [.compositingGroup]
        ),
      ]
    )

    #expect(rasterDamage(previous, current).isEmpty)
  }

  @Test("stress raster damage topology 017 image layer identity swap damages fixed bounds")
  func rasterDamageTopology017ImageLayerIdentitySwapDamagesFixedBounds() {
    let bounds = CellRect(x: 2, y: 1, width: 3, height: 2)
    let previousImage = rasterImage("017-old", visible: bounds)
    let currentImage = rasterImage("017-new", visible: bounds)
    let previous = rasterTopologySurface(layers: [rasterImageLayer(order: 0, image: previousImage)])
    let current = rasterTopologySurface(layers: [rasterImageLayer(order: 0, image: currentImage)])

    #expect(
      rasterDamage(previous, current)
        == [
          .init(row: 1, columnRanges: [2..<5]),
          .init(row: 2, columnRanges: [2..<5]),
        ]
    )
  }

  @Test("stress raster damage topology 018 backdrop signature damages image layer bounds")
  func rasterDamageTopology018BackdropSignatureDamagesImageLayerBounds() {
    let bounds = CellRect(x: 3, y: 1, width: 2, height: 2)
    let previousImage = rasterImage("018", visible: bounds, compositingSignature: 1)
    let currentImage = rasterImage("018", visible: bounds, compositingSignature: 2)
    let previous = rasterTopologySurface(layers: [rasterImageLayer(order: 0, image: previousImage)])
    let current = rasterTopologySurface(layers: [rasterImageLayer(order: 0, image: currentImage)])

    #expect(
      rasterDamage(previous, current)
        == [
          .init(row: 1, columnRanges: [3..<5]),
          .init(row: 2, columnRanges: [3..<5]),
        ]
    )
  }

  @Test("stress raster damage topology 019 overlapping recorder fragments merge their union")
  func rasterDamageTopology019OverlappingRecorderFragmentsMergeUnion() throws {
    let recorder = RasterPresentationLayerRecorder()
    let cells = rasterRecorderCells(width: 10)
    recorder.appendCellFragment(from: cells, x: 1, y: 0, width: 5, effects: [])
    recorder.appendCellFragment(from: cells, x: 4, y: 0, width: 4, effects: [])

    let layer = try #require(recorder.layers.first)
    #expect(recorder.layers.count == 1)
    #expect(layer.bounds == .init(x: 1, y: 0, width: 7, height: 1))
  }

  @Test("stress raster damage topology 020 contained recorder fragments stay one layer")
  func rasterDamageTopology020ContainedRecorderFragmentsStayOneLayer() throws {
    let recorder = RasterPresentationLayerRecorder()
    let cells = rasterRecorderCells(width: 10)
    recorder.appendCellFragment(from: cells, x: 1, y: 0, width: 8, effects: [])
    recorder.appendCellFragment(from: cells, x: 3, y: 0, width: 2, effects: [])

    let layer = try #require(recorder.layers.first)
    #expect(recorder.layers.count == 1)
    #expect(layer.bounds == .init(x: 1, y: 0, width: 8, height: 1))
  }

  @Test("stress raster damage topology 021 negative recorder X clamps to the row")
  func rasterDamageTopology021NegativeRecorderXClampsToRow() throws {
    let recorder = RasterPresentationLayerRecorder()
    recorder.appendCellFragment(
      from: rasterRecorderCells(width: 8),
      x: -2,
      y: 0,
      width: 5,
      effects: []
    )

    #expect(try #require(recorder.layers.first).bounds == .init(x: 0, y: 0, width: 3, height: 1))
  }

  @Test("stress raster damage topology 022 recorder right overflow truncates exactly")
  func rasterDamageTopology022RecorderRightOverflowTruncatesExactly() throws {
    let recorder = RasterPresentationLayerRecorder()
    recorder.appendCellFragment(
      from: rasterRecorderCells(width: 8),
      x: 6,
      y: 0,
      width: 5,
      effects: []
    )

    #expect(try #require(recorder.layers.first).bounds == .init(x: 6, y: 0, width: 2, height: 1))
  }

  @Test("stress raster damage topology 023 recorder skips rows outside its matrix")
  func rasterDamageTopology023RecorderSkipsRowsOutsideMatrix() {
    let recorder = RasterPresentationLayerRecorder()
    let cells = rasterRecorderCells(width: 8)
    recorder.appendCellFragment(from: cells, x: 0, y: -1, width: 2, effects: [])
    recorder.appendCellFragment(from: cells, x: 0, y: 1, width: 2, effects: [])

    #expect(recorder.layers.isEmpty)
  }

  @Test("stress raster damage topology 024 recorder omits invisible images")
  func rasterDamageTopology024RecorderOmitsInvisibleImages() {
    let recorder = RasterPresentationLayerRecorder()
    recorder.appendImageAttachment(
      rasterImage("024-width", visible: .init(x: 1, y: 1, width: 0, height: 2)),
      effects: []
    )
    recorder.appendImageAttachment(
      rasterImage("024-height", visible: .init(x: 1, y: 1, width: 2, height: 0)),
      effects: []
    )

    #expect(recorder.layers.isEmpty)
  }

  @Test("stress raster damage topology 025 sparse retained order seeds the next layer")
  func rasterDamageTopology025SparseRetainedOrderSeedsNextLayer() throws {
    let retained = [
      rasterCellLayer(order: 2, rect: .init(x: 0, y: 0, width: 1, height: 1)),
      rasterCellLayer(order: 9, rect: .init(x: 1, y: 0, width: 1, height: 1)),
    ]
    let recorder = RasterPresentationLayerRecorder(layers: retained)
    recorder.appendCellFragment(
      from: rasterRecorderCells(width: 8),
      x: 2,
      y: 0,
      width: 2,
      effects: []
    )

    #expect(recorder.layers.count == 3)
    #expect(try #require(recorder.layers.last).order == 10)
    #expect(try #require(recorder.layers.last).bounds == .init(x: 2, y: 0, width: 2, height: 1))
  }
}

private func rasterDamage(
  _ previous: RasterSurface,
  _ current: RasterSurface
) -> [PresentationDamage.TextRow] {
  RasterSurfaceDamageDiff.diff(previous: previous, current: current)?.textRows ?? []
}

private func rasterImageSurface(
  attachments: [RasterImageAttachment] = []
) -> RasterSurface {
  RasterSurface(
    size: .init(width: 8, height: 4),
    lines: ["", "", "", ""],
    imageAttachments: attachments
  )
}

private func rasterTopologySurface(
  layers: [RasterPresentationLayer]
) -> RasterSurface {
  RasterSurface(
    size: .init(width: 8, height: 4),
    lines: ["........", "........", "........", "........"],
    presentationLayers: layers
  )
}

private func rasterImage(
  _ name: String,
  visible: CellRect,
  compositingSignature: UInt64? = nil
) -> RasterImageAttachment {
  let compositing = compositingSignature.map { signature in
    RasterImageCompositing(
      blendMode: .multiply,
      destinationBackdrop: RasterImageBackdrop(
        bounds: visible,
        cells: Array(
          repeating: RasterImageBackdropCell(backgroundColor: .blue),
          count: max(0, visible.size.width * visible.size.height)
        )
      ),
      cellPixelSize: .init(width: 8, height: 16),
      backdropSignature: signature
    )
  }
  return RasterImageAttachment(
    identity: testIdentity(name),
    bounds: visible,
    visibleBounds: visible,
    source: .path("\(name).png"),
    compositing: compositing
  )
}

private func rasterImageLayer(
  order: Int,
  image: RasterImageAttachment
) -> RasterPresentationLayer {
  RasterPresentationLayer(
    order: order,
    bounds: image.visibleBounds,
    content: .image(image)
  )
}

private func rasterCellLayer(
  order: Int,
  rect: CellRect,
  effects: [DrawEffect] = []
) -> RasterPresentationLayer {
  RasterPresentationLayer(
    order: order,
    bounds: rect,
    content: .cells(RasterSurfaceFragment(bounds: rect, cells: [])),
    effects: effects
  )
}

private func rasterRecorderCells(width: Int) -> [[RasterCell]] {
  [[RasterCell](repeating: .init(character: "x"), count: width)]
}

extension CellRect {
  fileprivate init(x: Int, y: Int, width: Int, height: Int) {
    self.init(
      origin: .init(x: x, y: y),
      size: .init(width: width, height: height)
    )
  }
}
