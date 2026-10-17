@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetACanvasCompositionTests {
  @Test func setA926TransparentHalfPixelsPreserveThePreviouslyPaintedOppositeHalf() {
    // Hypothesis: a partial half-block overwrites the glyph that carried the other half's foreground color.
    let top = CanvasPixelGridDrawing(
      width: 1, height: 2, pixels: [.red, nil], mode: .verticalHalfBlock)
    let bottom = CanvasPixelGridDrawing(
      width: 1, height: 2, pixels: [nil, .blue], mode: .verticalHalfBlock)
    let complete = CanvasPixelGridDrawing(
      width: 1, height: 2, pixels: [.red, .blue], mode: .verticalHalfBlock)
    let expected = render([complete], size: .init(width: 1, height: 1))
    #expect(expected.cells[0][0].character == "▀")
    #expect(expected.cells[0][0].style?.foregroundColor == .red)
    #expect(expected.cells[0][0].style?.backgroundColor == .blue)
    for (order, drawings) in [[top, bottom], [bottom, top]].enumerated() {
      let actual = render(drawings, size: .init(width: 1, height: 1))
      let actualHalves = halves(actual.cells[0][0])
      #expect(order == 0 ? actualHalves.bottom == .blue : actualHalves.top == .red)
      let halvesMatch = actualHalves == halves(expected.cells[0][0])
      do {
        #expect(
          halvesMatch,
          "order \(order), glyph '\(actual.cells[0][0].character)': top present \(actualHalves.top != nil), bottom present \(actualHalves.bottom != nil); expected red top and blue bottom"
        )
      }
    }
  }

  @Test func setA927SparsePixelBuffersKeepTheDeclaredRowStrideAndIgnoreExcessEntries() {
    // Hypothesis: missing pixels shrink the row stride or excess pixels escape the authored logical extent.
    let drawing = CanvasPixelGridDrawing(width: 3, height: 2, pixels: [.red, nil, .blue, .green])
    let sparse = render([drawing], size: .init(width: 4, height: 3), underlay: .white)
    #expect(sparse.cells[0][0].style?.backgroundColor == .red)
    #expect(sparse.cells[0][1].style?.backgroundColor == .white)
    #expect(sparse.cells[0][2].style?.backgroundColor == .blue)
    #expect(sparse.cells[1][0].style?.backgroundColor == .green)
    #expect(sparse.cells[1][1].style?.backgroundColor == .white)
    var excess = drawing
    excess.height = 1
    #expect(
      render([excess], size: .init(width: 4, height: 3), underlay: .white).cells[1][0].style?
        .backgroundColor == .white)
    #expect(sparse.cells[2][3].style?.backgroundColor == .white)
  }

  @Test func setA928EqualHalfColorCompactionPreservesSingleLayerAlpha() {
    // Hypothesis: collapsing two identical half-pixels into a background fill composites their opacity twice.
    let color = Color(red: 1, green: 0, blue: 0, alpha: 0.4)
    let half = CanvasPixelGridDrawing(
      width: 1, height: 2, pixels: [color, color], mode: .verticalHalfBlock)
    let full = CanvasPixelGridDrawing(width: 1, height: 1, pixels: [color])
    let a = render([half], size: .init(width: 1, height: 1), underlay: .blue)
    let b = render([full], size: .init(width: 1, height: 1), underlay: .blue)
    let twice = render([full, full], size: .init(width: 1, height: 1), underlay: .blue)
    #expect(a.cells == b.cells)
    #expect(a.cells[0][0].character == " ")
    // Default terminal backgrounds use the style-mixing path;
    // explicit BlendMode.normal uses a different color-compositing operation.
    // A separate double-layer control witnesses that opacity is meaningful here.
    #expect(a.cells != twice.cells)
  }

  @Test func setA929TheLastStyledSampleReplacesBothChannelsForItsWholeCell() {
    // Hypothesis: the last sample replaces only foreground, retaining an earlier sample's background channel.
    let surface = render(size: .init(width: 1, height: 1), underlay: .yellow) { context in
      context.setPixel(at: .zero, foreground: .red, background: .blue)
      context.setPixel(at: .init(x: 0.5, y: 0), foreground: .green)
    }
    #expect(surface.cells[0][0].character == "⠉")
    #expect(surface.cells[0][0].style?.foregroundColor == .green)
    #expect(surface.cells[0][0].style?.backgroundColor == .yellow)
  }

  @Test func setA930FinalContextColorsReachEarlierUnstyledSamplesOnly() {
    // Hypothesis: fallback styles are captured at sample time, or the final fallback overwrites explicit sample styles.
    let surface = render(size: .init(width: 3, height: 1)) { context in
      context.foreground = .red
      context.setPixel(at: .zero)
      context.setPixel(at: .init(x: 1, y: 0), foreground: .green)
      context.foreground = .blue
      context.background = .yellow
      context.setPixel(at: .init(x: 2, y: 0))
    }
    #expect(surface.cells[0][0].style == surface.cells[0][2].style)
    #expect(surface.cells[0][0].style?.foregroundColor == .blue)
    #expect(surface.cells[0][0].style?.backgroundColor == .yellow)
    #expect(surface.cells[0][1].style?.foregroundColor == .green)
    #expect(surface.cells[0][1].style?.backgroundColor == nil)
  }

  @Test func setA931SampleLayerStaysAboveDirectCellsRegardlessOfAuthorCallOrder() {
    // Hypothesis: author order accidentally changes the documented direct-cell-then-grid raster layer order.
    let first = render(size: .init(width: 1, height: 1)) { context in
      context.setPixel(at: .zero, foreground: .red)
      context.setCell(at: .zero, character: "X", foreground: .green, background: .blue)
    }
    let second = render(size: .init(width: 1, height: 1)) { context in
      context.setCell(at: .zero, character: "X", foreground: .green, background: .blue)
      context.setPixel(at: .zero, foreground: .red)
    }
    #expect(first.cells == second.cells)
    #expect(first.cells[0][0].character == "⠁")
    #expect(first.cells[0][0].style?.foregroundColor == .red)
    #expect(first.cells[0][0].style?.backgroundColor == .blue)
  }

  @Test func setA932ClearingTheLastSampleRevealsItsIndependentDirectGlyph() {
    // Hypothesis: a zero sample mask still emits a blank glyph and covers the direct-cell layer beneath it.
    let surface = render(size: .init(width: 1, height: 1)) { context in
      context.setCell(at: .zero, character: "D", foreground: .blue)
      context.setPixel(at: .zero, foreground: .red)
      context.clearPixel(at: .zero)
    }
    #expect(surface.cells[0][0].character == "D")
    #expect(surface.cells[0][0].style?.foregroundColor == .blue)
  }

  @Test func setA933ClearingADirectWriteDoesNotPaintAnOpaqueReplacementSpace() {
    // Hypothesis: clearCell leaves a stored blank write instead of removing that drawing's contribution.
    let bounds = rect(0, 0, 2, 1)
    let underlay = DrawCommand.preformattedText(bounds: bounds, lines: ["AB"], style: .init())
    let drawing = CanvasClosureDrawing { context in
      context.setCell(at: .zero, character: "X", foreground: .red)
      context.clearCell(at: .zero)
      context.setCell(at: .init(x: 1, y: 0), character: "Y")
    }
    let surface = render([drawing], size: bounds.size, prefix: [underlay])
    #expect(surface.lines == ["AY"])
  }

  @Test func setA934DefaultBackgroundDoesNotFillUntouchedCanvasCells() {
    // Hypothesis: a context background is treated as a canvas-wide clear instead of styling only lit sample cells.
    let surface = render(size: .init(width: 3, height: 2), underlay: .blue) { context in
      context.background = .red
      context.setSample(.init(x: 2, y: 0))
    }
    #expect(surface.cells[0][1].style?.backgroundColor == .red)
    #expect(surface.cells[0][0].style?.backgroundColor == .blue)
    #expect(surface.cells[1][1].style?.backgroundColor == .blue)
  }

  @Test func setA935ClippingDoesNotRebaseAuthorCoordinatesOrShrinkTheCanvasContext() {
    // Hypothesis: surface clipping changes the size or coordinate origin supplied to author drawing code.
    let drawing = CanvasClosureDrawing { context in
      guard context.size == .init(width: 5, height: 3) else {
        context.setCell(at: .zero, character: "!")
        return
      }
      let glyphs = Array("ABCDEFGHIJKLMNO")
      for y in 0..<3 {
        for x in 0..<5 {
          context.setCell(at: .init(x: x, y: y), character: glyphs[y * 5 + x])
        }
      }
    }
    let bounds = rect(0, 0, 4, 3)
    let command = DrawCommand.canvas(
      bounds: rect(-2, -1, 5, 3),
      payload: .init(drawing: drawing), foregroundStyle: .color(.white))
    let node = DrawNode(identity: testIdentity("SetA935"), bounds: bounds, commands: [command])
    let control = Rasterizer().rasterize(node, minimumSize: bounds.size)
    var clipped = node
    clipped.clipBounds = rect(0, 0, 2, 1)
    let surface = Rasterizer().rasterize(clipped, minimumSize: bounds.size)
    #expect(control.cells[0][0].character == "H")
    #expect(control.cells[0][1].character == "I")
    #expect(surface.cells[0][0] == control.cells[0][0])
    #expect(surface.cells[0][1] == control.cells[0][1])
    #expect(surface.cells[0][2] == .empty)
    #expect(surface.cells[1].allSatisfy { $0 == .empty })
  }

  @Test func setA936CanvasOpacityIsAppliedOnceToEachAuthoredColorSource() throws {
    // Hypothesis: explicit sample/direct colors bypass or double the opacity applied to context fallback colors.
    let drawing = CanvasClosureDrawing { context in
      context.foreground = .red
      context.setPixel(at: .zero)
      context.setPixel(at: .init(x: 1, y: 0), foreground: .red)
      context.setCell(at: .init(x: 2, y: 0), character: "X", foreground: .red)
      context.fillCell(.red, at: .init(x: 3, y: 0))
    }
    let surface = render([drawing], size: .init(width: 4, height: 1), opacity: 0.25)
    for x in 0..<3 {
      #expect(abs(try #require(surface.cells[0][x].style?.foregroundColor).alpha - 0.25) < 1e-12)
    }
    #expect(abs(try #require(surface.cells[0][3].style?.backgroundColor).alpha - 0.25) < 1e-12)
  }

  @Test func setA937LiveGridChangeReinterpretsTheSameDrawingInput() throws {
    // Hypothesis: retained Canvas equality keys only the drawing and overlooks its changed packing grid.
    let h = try runtime(937, mode: .grid)
    defer { h.shutdown() }
    #expect(try markedCell(h).character == "⠁")
    try h.clickText("Change canvas")
    #expect(try markedCell(h).character == "▘")
  }

  @Test func setA938ChangedKeyedInputRepaintsTheExistingCanvasFrame() throws {
    // Hypothesis: CanvasInputDrawing's erased equality serves the previous closure input after a state change.
    let h = try runtime(938, mode: .input)
    defer { h.shutdown() }
    #expect(try markedCell(h).character == "A")
    try h.clickText("Change canvas")
    #expect(try markedCell(h).character == "Z")
  }

  @Test func setA939ResizedCanvasPassesItsNewContextSizeToAnEqualDrawing() throws {
    // Hypothesis: an equal drawing keeps a cached context extent when its allocated frame changes.
    let h = try runtime(939, mode: .size)
    defer { h.shutdown() }
    #expect(try markedCell(h).character == "3")
    try h.clickText("Change canvas")
    #expect(try markedCell(h).character == "6")
  }

  @Test func setA940EqualCanvasDrawingObservesAChangedAmbientForeground() throws {
    // Hypothesis: retained canvas pixels keep their previously resolved foreground after an environment-only change.
    let h = try runtime(940, mode: .foreground)
    defer { h.shutdown() }
    let old = try #require(markedCell(h).style?.foregroundColor)
    try h.clickText("Change canvas")
    let new = try #require(markedCell(h).style?.foregroundColor)
    #expect(old.red > old.blue)
    #expect(new.blue > new.red)
  }

  @Test func setA941DisjointDirtyRowsCannotReapplyCanvasLayersToTheirCleanMiddle() {
    // Hypothesis: the direct or grid loop repaints the dirty hull, reapplying alpha to unchanged intervening rows.
    let bounds = rect(0, 0, 2, 5)
    func tree(_ changed: Bool) -> DrawNode {
      let drawing = CanvasClosureDrawing { context in
        for y in 0..<5 {
          context.fillCell(Color.blue.opacity(0.4), at: .init(x: 0, y: y))
          context.setPixel(at: .init(x: 0, y: Double(y)), foreground: .red.opacity(0.4))
          context.setCell(
            at: .init(x: 1, y: y), character: changed && (y == 0 || y == 4) ? "B" : "A")
        }
      }
      return DrawNode(
        identity: testIdentity("SetA941"), bounds: bounds,
        commands: [
          .canvas(bounds: bounds, payload: .init(drawing: drawing), foregroundStyle: .color(.white))
        ])
    }
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let previous = rasterizer.rasterize(tree(false), minimumSize: bounds.size)
    let current = tree(true)
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current, minimumSize: bounds.size,
      previousSurface: previous, damage: .init(dirtyRows: [0, 4]),
      verifyIncrementalRasterDamage: false)
    #expect(result.path == .incremental)
    #expect(result.surface.cells[2] == previous.cells[2])
    #expect(result.surface.cells == rasterizer.rasterize(current, minimumSize: bounds.size).cells)
  }

  @Test func setA942PointerSampleMappingUsesCellCoordinatesWithoutReapplyingHostPixels() {
    // Hypothesis: pointer provenance causes reported pixel metrics to be applied a second time during sample mapping.
    let location = Point(x: 1.75, y: 2.625)
    for grid in grids {
      let context = context(grid, size: .init(width: 4, height: 4))
      let pointer = PointerLocation.subCell(
        location: location, source: .nativePixels,
        metrics: .init(width: 13, height: 29, source: .reported))
      let expected = GridSample(
        x: Int((location.x * Double(grid.subdivisionsX)).rounded(.down)),
        y: Int((location.y * Double(grid.subdivisionsY)).rounded(.down)))
      #expect(context.gridSample(for: pointer) == expected)
    }
  }

  @Test func setA943CellSpaceCircleUsesIndependentHorizontalAndVerticalGridScales() {
    // Hypothesis: a continuous cell-space radius is scaled by one grid axis and distorts the other's cardinal extent.
    var value = context(.braille2x4, size: .init(width: 6, height: 6))
    value.strokeCircle(center: .init(x: 3, y: 3), radius: 1)
    let points = samples(value.canvas)
    #expect(points.map(\.x).min() == 4)
    #expect(points.map(\.x).max() == 8)
    #expect(points.map(\.y).min() == 8)
    #expect(points.map(\.y).max() == 16)
    for point in [
      GridSample(x: 4, y: 12), .init(x: 8, y: 12), .init(x: 6, y: 8), .init(x: 6, y: 16),
    ] {
      #expect(points.contains(point))
    }
  }

  @Test func setA944FractionalRectanglesExcludeTheExactUpperSampleBoundary() {
    // Hypothesis: rounding both rectangle endpoints outward includes one extra sample at an exact upper edge.
    var value = context(.quadrant2x2, size: .init(width: 3, height: 2))
    value.fillRect(.init(origin: .init(x: 0.25, y: 0.25), size: .init(width: 1.25, height: 0.75)))
    #expect(value.canvas.mask(x: 0, y: 0) == 15)
    #expect(value.canvas.mask(x: 1, y: 0) == 5)
    #expect(value.canvas.mask(x: 2, y: 0) == 0)
    #expect((0..<3).allSatisfy { value.canvas.mask(x: $0, y: 1) == 0 })
  }

  @Test func setA945ElongatedEllipseOutlineHasNoDisconnectedSampleIslands() throws {
    // Hypothesis: parametric ellipse sampling fails to bridge steep neighboring samples on elongated outlines.
    var value = CanvasGridBuffer(size: .init(width: 22, height: 12), grid: .fullCell)
    value.strokeEllipse(centerX: 10, centerY: 5, radiusX: 9, radiusY: 2)
    let lit = Set(samples(value))
    let first = try #require(lit.first)
    var visited: Set<GridSample> = [first]
    var pending = [first]
    while let point = pending.popLast() {
      for dx in -1...1 {
        for dy in -1...1 {
          let neighbor = GridSample(x: point.x + dx, y: point.y + dy)
          if lit.contains(neighbor), visited.insert(neighbor).inserted { pending.append(neighbor) }
        }
      }
    }
    #expect(lit.count > 20)
    #expect(visited == lit)
    #expect(!lit.contains(.init(x: 10, y: 5)))
  }

  @Test func setA946OffscreenEllipseClippingEqualsCroppingAWholeTranslatedOutline() {
    // Hypothesis: clipping an ellipse changes its angular stepping or inserts a spurious viewport-edge connector.
    var small = CanvasGridBuffer(size: .init(width: 7, height: 5), grid: .fullCell)
    var large = CanvasGridBuffer(size: .init(width: 19, height: 15), grid: .fullCell)
    small.strokeEllipse(centerX: -1, centerY: 1, radiusX: 5, radiusY: 3)
    large.strokeEllipse(centerX: 5, centerY: 6, radiusX: 5, radiusY: 3)
    #expect(!samples(small).isEmpty)
    for y in 0..<5 {
      for x in 0..<7 { #expect(small.mask(x: x, y: y) == large.mask(x: x + 6, y: y + 5)) }
    }
  }

  @Test func setA947QuadrantGlyphsPreserveAllFourAuthoredPhysicalPositions() {
    // Hypothesis: quadrant mask packing swaps bottom-left and top-right or a three-quadrant complement.
    let glyphs: [Character?] = [
      nil, "▘", "▝", "▀", "▖", "▌", "▞", "▛",
      "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█",
    ]
    for mask in 0..<16 {
      var buffer = CanvasGridBuffer(size: .init(width: 1, height: 1), grid: .quadrant2x2)
      for bit in 0..<4 where mask & (1 << bit) != 0 { buffer.setPixel(x: bit % 2, y: bit / 2) }
      #expect(buffer.character(x: 0, y: 0) == glyphs[mask])
    }
  }

  @Test func setA948OctantCompatibilityKeepsBrailleCoverageButDistinctPayloadIdentity() {
    // Hypothesis: octant's provisional Braille encoding uses row-major bits or collapses the distinct public grid key.
    let drawing = CanvasClosureDrawing { context in
      for point in [GridSample(x: 0, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 3)] {
        context.setSample(point)
      }
    }
    let braille = render([drawing], size: .init(width: 1, height: 1), grid: .braille2x4)
    let octant = render([drawing], size: .init(width: 1, height: 1), grid: .octant2x4)
    #expect(braille.cells[0][0].character == "⡑")
    #expect(octant.cells == braille.cells)
    #expect(
      CanvasPayload(drawing: drawing, grid: .octant2x4)
        != CanvasPayload(drawing: drawing, grid: .braille2x4))
  }

  @Test func setA949CopiedContextsOwnTheirStylesAndDirectWritesAsWellAsSamples() {
    // Hypothesis: copying CanvasContext isolates the mask but aliases its independently stored style or direct-cell rows.
    var original = context(.braille2x4, size: .init(width: 2, height: 1))
    original.setCell(at: .zero, character: "A", background: .blue)
    original.setPixel(at: .zero, foreground: .red)
    var copy = original
    copy.setCell(at: .zero, character: "B", background: .green)
    copy.setPixel(at: .init(x: 0.5, y: 0), foreground: .yellow)
    copy.background = .white
    #expect(original.directCells[0][0]?.character == "A")
    #expect(original.directCells[0][0]?.background == .blue)
    #expect(original.gridCellStyles[0][0]?.foregroundColor == .red)
    #expect(original.canvas.mask(x: 0, y: 0) == 1)
    #expect(original.background == nil)
    #expect(copy.canvas.mask(x: 0, y: 0) == 9)
  }

  @Test func setA950LiveOpacityChangeInvalidatesEqualExplicitCanvasPaint() throws {
    // Hypothesis: an opacity-only ancestor change never reaches explicit colors stored in an equal canvas drawing.
    let h = try runtime(950, mode: .opacity)
    defer { h.shutdown() }
    let old = try #require(markedCell(h).style?.foregroundColor)
    try h.clickText("Change canvas")
    let new = try #require(markedCell(h).style?.foregroundColor)
    #expect(old != new)
    #expect(new.red < old.red || new.alpha < old.alpha)
  }

  private let grids: [CanvasGrid] = [
    .braille2x4, .octant2x4, .sextant2x3, .quadrant2x2,
    .verticalHalfBlock, .horizontalHalfBlock, .fullCell,
  ]

  private func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CellRect {
    .init(origin: .init(x: x, y: y), size: .init(width: width, height: height))
  }

  private func context(_ grid: CanvasGrid, size: CellSize) -> CanvasContext {
    .init(canvas: .init(size: size, grid: grid), foreground: .white, background: nil)
  }

  private func render(
    size: CellSize, underlay: Color? = nil,
    _ draw: @escaping @Sendable (inout CanvasContext) -> Void
  ) -> RasterSurface {
    render([CanvasClosureDrawing(draw)], size: size, underlay: underlay)
  }

  private func render(
    _ drawings: [any CanvasDrawing], size: CellSize, grid: CanvasGrid = .braille2x4,
    underlay: Color? = nil, opacity: Double = 1, prefix: [DrawCommand] = []
  ) -> RasterSurface {
    let bounds = CellRect(origin: .zero, size: size)
    var commands = prefix
    if let underlay {
      commands.append(
        .fill(
          bounds: bounds, geometry: .rectangle, insetAmount: 0, style: .color(underlay), mode: .full
        ))
    }
    for drawing in drawings {
      var payload = CanvasPayload(drawing: drawing, grid: grid)
      payload.opacity = opacity
      commands.append(.canvas(bounds: bounds, payload: payload, foregroundStyle: .color(.white)))
    }
    return Rasterizer().rasterize(
      DrawNode(identity: testIdentity("SetACanvas"), bounds: bounds, commands: commands),
      minimumSize: size)
  }

  private struct HalfColors: Equatable {
    let top: Color?
    let bottom: Color?
  }

  private func halves(_ cell: RasterCell) -> HalfColors {
    switch cell.character {
    case "▀": .init(top: cell.style?.foregroundColor, bottom: cell.style?.backgroundColor)
    case "▄": .init(top: cell.style?.backgroundColor, bottom: cell.style?.foregroundColor)
    default: .init(top: cell.style?.backgroundColor, bottom: cell.style?.backgroundColor)
    }
  }

  private func samples(_ buffer: CanvasGridBuffer) -> [GridSample] {
    var result: [GridSample] = []
    for y in 0..<buffer.pixelHeight {
      for x in 0..<buffer.pixelWidth {
        let sx = buffer.grid.subdivisionsX
        let sy = buffer.grid.subdivisionsY
        let bit: UInt16
        switch buffer.grid.style {
        case .braille2x4, .octant2x4:
          let brailleBits: [[UInt16]] = [[1, 8], [2, 16], [4, 32], [64, 128]]
          bit = brailleBits[y % sy][x % sx]
        default: bit = 1 << (y % sy * sx + x % sx)
        }
        if buffer.mask(x: x / sx, y: y / sy) & bit != 0 { result.append(.init(x: x, y: y)) }
      }
    }
    return result
  }

  private func runtime(_ id: Int, mode: SetACanvasRuntimeRoot.Mode) throws -> StressRuntimeHarness<
    SetACanvasRuntimeRoot
  > {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetACanvas\(id)"), size: .init(width: 24, height: 6)
    ) {
      SetACanvasRuntimeRoot(mode: mode)
    }
  }

  private func markedCell(_ harness: StressRuntimeHarness<SetACanvasRuntimeRoot>) throws
    -> RasterCell
  {
    let surface = try #require(harness.runLoop.previousPresentedRasterSurface)
    for row in surface.cells {
      if let marker = row.firstIndex(where: { $0.character == "@" }), marker + 1 < row.count {
        return row[marker + 1]
      }
    }
    throw SetACanvasMissingMarker.missing
  }
}

private enum SetACanvasMissingMarker: Error { case missing }

private struct SetACanvasRuntimeRoot: View {
  enum Mode: Equatable, Sendable { case input, grid, size, foreground, opacity }
  let mode: Mode
  @State var changed = false

  var body: some View {
    let drawingMode = mode
    VStack(alignment: .leading, spacing: 0) {
      Button("Change canvas") { changed.toggle() }.buttonStyle(.plain)
      HStack(spacing: 0) {
        Text("@")
        Canvas(
          mode == .input && changed, grid: mode == .grid && changed ? .quadrant2x2 : .braille2x4
        ) { context, input in
          switch drawingMode {
          case .input: context.setCell(at: .zero, character: input ? "Z" : "A")
          case .size: context.setCell(at: .zero, character: Character(String(context.size.width)))
          case .opacity: context.setPixel(at: .zero, foreground: .red)
          case .grid, .foreground: context.setPixel(at: .zero)
          }
        }
        .foregroundStyle(mode == .foreground && changed ? Color.blue : Color.red)
        .opacity(mode == .opacity && changed ? 0.25 : 1)
        .frame(width: mode == .size ? (changed ? 6 : 3) : 3, height: 1)
      }
    }
  }
}
