import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

@Suite
struct AdversarialSetARasterTranslationTests {
  @Test func setA826ThirdStrokeRecoversArmsHiddenByUnsupportedWeightFallback() {
    // Hypothesis: a heavy/double fallback destroys the original arm weights needed by a third stroke.
    let bounds = rect(0, 0, 7, 5)
    let vertical = rule(rect(3, 0, 1, 5), stroke: .heavy, vertical: true)
    let double = rule(rect(0, 2, 7, 1), stroke: .init(borderSet: .double))
    let light = rule(rect(0, 2, 7, 1))
    let fallback = raster(root(bounds, commands: [vertical, double]), size: bounds.size)
    let recovered = raster(root(bounds, commands: [vertical, double, light]), size: bounds.size)
    #expect(fallback.cells[2][3].character == "╬")
    #expect(recovered.cells[2][3].character == "╂")
    #expect(recovered.cells[1][3].character == "┃")
    #expect(recovered.cells[2][2].character == "─")
  }

  @Test func setA827FullSquareCoverClearsEarlierRoundedCornerIntent() {
    // Hypothesis: merging a second complete ring retains the first ring's rounded-corner flag.
    let bounds = rect(0, 0, 6, 4)
    let square = stroke(bounds)
    let rounded = stroke(bounds, stroke: .rounded)
    let covered = raster(root(bounds, commands: [rounded, square]), size: bounds.size)
    let reverse = raster(root(bounds, commands: [square, rounded]), size: bounds.size)
    #expect(covered.lines == ["┌────┐", "│    │", "│    │", "└────┘"])
    #expect(reverse.lines == ["╭────╮", "│    │", "│    │", "╰────╯"])
  }

  @Test func setA828CompositingLayerDoesNotJoinAnOuterLayersLineArms() {
    // Hypothesis: a compositing group's line-arm table aliases its parent's table and invents a junction.
    let bounds = rect(0, 0, 5, 5)
    let horizontal = rule(rect(0, 2, 5, 1))
    let vertical = node(
      "isolated", rect(2, 0, 1, 5), commands: [rule(rect(2, 0, 1, 5), vertical: true)])
    var isolated = vertical
    isolated.drawEffects = .init([.compositingGroup])
    let joined = raster(
      root(bounds, commands: [horizontal], children: [vertical]), size: bounds.size)
    let separate = raster(
      root(bounds, commands: [horizontal], children: [isolated]), size: bounds.size)
    #expect(joined.cells[2][2].character == "┼")
    #expect(separate.cells[2][2].character == "│")
    #expect(separate.cells[2][1].character == "─")
  }

  @Test func setA829FourIndependentBorderSidesCloseWithoutOutwardCaps() {
    // Hypothesis: caps from separately drawn sides survive later orthogonal arms and turn corners into tees.
    let bounds = rect(0, 0, 6, 4)
    func side(_ sides: Edge.Set) -> DrawCommand {
      .border(
        bounds: bounds, stroke: .single, foreground: nil, background: nil,
        blend: nil, blendPhase: 0, sides: sides)
    }
    let forward = raster(
      root(bounds, commands: [side(.top), side(.trailing), side(.bottom), side(.leading)]),
      size: bounds.size)
    let reverse = raster(
      root(bounds, commands: [side(.leading), side(.bottom), side(.trailing), side(.top)]),
      size: bounds.size)
    #expect(forward.lines == ["┌────┐", "│    │", "│    │", "└────┘"])
    #expect(reverse.cells == forward.cells)
  }

  @Test func setA830WideTextOverwriteInvalidatesTheCoveredStrokeProvenance() {
    // Hypothesis: replacing two stroke cells with one wide glyph leaves their old arms available to later lines.
    let bounds = rect(0, 0, 5, 5)
    let drawing = root(
      bounds,
      commands: [
        rule(rect(0, 2, 5, 1)), text("界", rect(1, 2, 2, 1)),
        rule(rect(2, 0, 1, 5), vertical: true),
      ])
    let surface = raster(drawing, size: bounds.size)
    #expect(surface.cells[2][2].character == "│")
    #expect(surface.cells[2][1].character == " ")
    #expect(surface.cells[2][1].spanWidth == 1)
    #expect(surface.cells[2][2].continuationLeadX == nil)
    #expect(surface.cells[2][0].character == "─")
  }

  @Test func setA831AsymmetricBorderPaletteKeepsItsBottomAndTrailingWeights() {
    // Hypothesis: recognizing the top/leading line glyphs silently replaces the other authored palette edges.
    let bounds = rect(0, 0, 6, 4)
    var palette = BorderSet.single
    palette.bottom = "━"
    palette.right = "║"
    let surface = raster(
      root(bounds, commands: [stroke(bounds, stroke: .init(borderSet: palette))]), size: bounds.size
    )
    #expect(surface.cells[0][2].character == "─")
    #expect(surface.cells[1][0].character == "│")
    let bottom = surface.cells[3][2].character
    let trailing = surface.cells[1][5].character
    do {
      #expect(bottom == "━")
      #expect(trailing == "║")
    }
  }

  @Test func setA832RemovingACrossbarRebuildsTheSurvivingRingFromEmptyArms() {
    // Hypothesis: an incremental repaint keeps the removed crossbar's junction arms in the surviving border.
    let bounds = rect(0, 0, 7, 5)
    let base = fill(.color(.blue), bounds)
    let old = root(bounds, commands: [base, stroke(bounds), rule(rect(0, 2, 7, 1))])
    let new = root(bounds, commands: [base, stroke(bounds)])
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let previous = rasterizer.rasterize(old, minimumSize: bounds.size)
    #expect(previous.cells[2][0].character == "├")
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      new, minimumSize: bounds.size, previousSurface: previous,
      damage: .init(dirtyRows: [1, 2, 3]), verifyIncrementalRasterDamage: false)
    #expect(result.path == .incremental)
    #expect(result.surface.cells == raster(new, size: bounds.size).cells)
    #expect(result.surface.cells[2][0].character == "│")
    #expect(result.surface.cells[2][3].style?.backgroundColor == .blue)
  }

  @Test func setA833StaticStrokeMasksCannotBeClassifiedAsRowInvariant() throws {
    // Hypothesis: static-stroke row invariance ignores dash and trim masks, copying the wrong perimeter row.
    let ring = rect(2, 1, 8, 16)
    let styles: [StrokeStyle] = [
      .init(dash: [3, 3]),
      StrokeStyle.single.trimmed(to: .init(from: 0.2, to: 0.65)),
    ]
    for style in styles {
      let chrome = node("masked-ring", ring, commands: [stroke(ring, stroke: style)])
      let previous = scrolling(first: 10, before: [chrome])
      let current = scrolling(first: 11, before: [chrome])
      let result = translate(previous, current)
      let servedRows = result.plan?.translatedRows ?? []
      let expected = raster(current)
      #expect(
        Set(expected.cells[3..<15].map { String([$0[2].character, $0[9].character]) }).count > 1)
      let cellsMatch = result.output.surface.cells == expected.cells
      do {
        #expect(
          cellsMatch,
          "mask \(style), served \(servedRows); \(firstDifference(result.output.surface, expected))"
        )
      }
    }
  }

  @Test func setA834NestedStationaryClipEdgesMustRepaintInsideTheScrollBand() throws {
    // Hypothesis: a stationary inner clip is mistaken for the outer viewport, serving rows across its own edge.
    let clip = rect(2, 6, 8, 5)
    func window(_ shift: Int) -> DrawNode {
      node(
        "inner", rect(2, 4 + shift, 8, 9), clip: clip,
        commands: [text("A\nB\nC\nD\nE\nF\nG\nH\nI", rect(2, 4 + shift, 8, 9))])
    }
    let previous = scrolling(first: 10, after: [window(0)])
    let current = scrolling(first: 11, after: [window(-1)])
    let result = translate(previous, current)
    let expected = raster(current)
    #expect(expected.cells[5][2].character == " ")
    #expect(expected.cells[10][2].character == "H")
    let cellsMatch = result.output.surface.cells == expected.cells
    do {
      #expect(cellsMatch, "\(firstDifference(result.output.surface, expected))")
    }
  }

  @Test func setA835AClipMovingWithItsContentPreservesTheTranslatedProjection() throws {
    // Hypothesis: moving a clipping boundary demotes or clips translated content using its previous coordinates.
    func clipped(_ y: Int) -> DrawNode {
      node(
        "moving-clip", rect(2, y, 8, 6), clip: rect(2, y + 1, 8, 4),
        commands: [text("A\nB\nC\nD\nE\nF", rect(2, y, 8, 6))])
    }
    let previous = scrolling(first: 10, after: [clipped(6)])
    let current = scrolling(first: 11, after: [clipped(5)])
    let result = translate(previous, current)
    #expect(try #require(result.plan).translatedRows.contains(7))
    #expect(result.output.surface.cells == raster(current).cells)
    #expect(result.output.surface.cells[6][2].character == "B")
    #expect(result.output.surface.cells[10][2].character == " ")
  }

  @Test func setA836ReversedEqualBoundsCommandsCannotReuseTheOldTopPaint() {
    // Hypothesis: FIFO command matching accepts translated payloads while losing their changed paint order.
    func overlay(_ y: Int, reverse: Bool) -> DrawNode {
      let bounds = rect(2, y, 2, 4)
      let commands = [fill(.color(.red), bounds), fill(.color(.blue), bounds)]
      return node(
        "ordered-paints", bounds, commands: reverse ? Array(commands.reversed()) : commands)
    }
    let old = scrolling(first: 10, after: [overlay(7, reverse: false)])
    let new = scrolling(first: 11, after: [overlay(6, reverse: true)])
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][2].style?.backgroundColor == .red)
  }

  @Test func setA837ReorderedOverlappingChildrenCannotServeTheFormerFrontSibling() {
    // Hypothesis: identity pairing ignores a sibling z-order reversal when both subtrees are translated twins.
    func overlays(_ y: Int, reverse: Bool) -> [DrawNode] {
      let bounds = rect(2, y, 2, 4)
      let pair = [
        node("red", bounds, commands: [fill(.color(.red), bounds)]),
        node("blue", bounds, commands: [fill(.color(.blue), bounds)]),
      ]
      return reverse ? Array(pair.reversed()) : pair
    }
    let old = scrolling(first: 10, after: overlays(7, reverse: false))
    let new = scrolling(first: 11, after: overlays(6, reverse: true))
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][2].style?.backgroundColor == .red)
  }

  @Test func setA838OneTranslatedCommandCannotConsumeTwoTranslucentLayers() {
    // Hypothesis: matching duplicate bounds/payloads consumes one old command twice and misses a removed alpha layer.
    func layers(_ y: Int, count: Int) -> DrawNode {
      let bounds = rect(2, y, 2, 4)
      return node(
        "alpha-count", bounds,
        commands: Array(repeating: fill(.color(.red.opacity(0.5)), bounds), count: count))
    }
    let old = scrolling(first: 10, after: [layers(7, count: 2)])
    let new = scrolling(first: 11, after: [layers(6, count: 1)])
    let result = translate(old, new)
    let expected = raster(new)
    #expect(
      raster(old).cells[7][2].style?.backgroundColor != expected.cells[6][2].style?.backgroundColor)
    #expect(result.output.surface.cells == expected.cells)
  }

  @Test func setA839ForeignGridChangesCannotRideIdentityOnlyTranslationEquality() {
    // Hypothesis: a foreign grid with changed cells is treated as a translated twin because payload equality is opaque.
    func foreign(_ y: Int, glyph: Character) -> DrawNode {
      let bounds = rect(2, y, 2, 4)
      let grid = ForeignGrid(
        size: bounds.size,
        cells: Array(repeating: Array(repeating: RasterCell(character: glyph), count: 2), count: 4))
      return node(
        "foreign", bounds,
        commands: [.foreignSurface(bounds: bounds, payload: GridPayload(grid: grid))])
    }
    let old = scrolling(first: 10, after: [foreign(7, glyph: "A")])
    let new = scrolling(first: 11, after: [foreign(6, glyph: "Z")])
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][2].character == "Z")
  }

  @Test func setA840CanvasPayloadChangesRepaintInsteadOfMovingTheOldDirectCells() {
    // Hypothesis: an opaque author drawing is copied under scroll even when its current direct-cell output changed.
    func canvas(_ y: Int, glyph: Character) -> DrawNode {
      let bounds = rect(2, y, 2, 4)
      return node(
        "canvas", bounds,
        commands: [
          .canvas(
            bounds: bounds,
            payload: .init(drawing: GlyphDrawing(glyph: glyph)), foregroundStyle: .color(.red))
        ])
    }
    let old = scrolling(first: 10, after: [canvas(7, glyph: "A")])
    let new = scrolling(first: 11, after: [canvas(6, glyph: "Z")])
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][2].character == "Z")
  }

  @Test func setA841TranslatedLinkPayloadChangeCannotKeepTheFormerDestination() {
    // Hypothesis: translation equality checks visible rich-text bytes but omits hyperlink destination payloads.
    func link(_ y: Int, destination: String) -> DrawNode {
      let bounds = rect(2, y, 2, 4)
      return node(
        "link", bounds, commands: [linked("X\nX\nX\nX", bounds, destination: destination)])
    }
    let old = scrolling(first: 10, after: [link(7, destination: "https://example.com/old")])
    let new = scrolling(first: 11, after: [link(6, destination: "https://example.com/new")])
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][2].hyperlink == "https://example.com/new")
  }

  @Test func setA842TranslatedSemanticPaintObservesItsNewEnvironment() {
    // Hypothesis: equal semantic commands are copied despite a changed environment resolving them to a new color.
    func semantic(_ y: Int, color: Color) -> DrawNode {
      let bounds = rect(2, y, 2, 4)
      var value = node("semantic", bounds, commands: [fill(.semantic(.foreground), bounds)])
      value.environmentSnapshot.style.foregroundStyle = .color(color)
      return value
    }
    let old = scrolling(first: 10, after: [semantic(7, color: .red)])
    let new = scrolling(first: 11, after: [semantic(6, color: .blue)])
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][2].style?.backgroundColor == .blue)
  }

  @Test func setA843StaticGradientBehindMovingTextKeepsItsScreenSampleRows() {
    // Hypothesis: a static semantic style hiding a positional gradient is wrongly admitted as row-invariant chrome.
    let bounds = rect(2, 1, 8, 16)
    var gradient = node("gradient", bounds, commands: [fill(.semantic(.foreground), bounds)])
    gradient.environmentSnapshot.style.foregroundStyle = AnyShapeStyle(
      LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
    let old = scrolling(first: 10, before: [gradient])
    let new = scrolling(first: 11, before: [gradient])
    let expected = raster(new)
    #expect(expected.cells[6][2].style != expected.cells[7][2].style)
    #expect(translate(old, new).output.surface.cells == expected.cells)
  }

  @Test func setA844MovedCompositingEffectsKeepTheirPresentationLayerBoundsCurrent() {
    // Hypothesis: moving cell buffers leaves a compositing-significant retained layer at its previous bounds.
    func group(_ y: Int) -> DrawNode {
      let bounds = rect(2, y, 2, 4)
      var value = node("effect", bounds, commands: [text("X\nY\nZ\nW", bounds)])
      value.drawEffects = .init([.compositingGroup, .blendMode(.multiply)])
      return value
    }
    let old = scrolling(first: 10, after: [group(7)])
    let new = scrolling(first: 11, after: [group(6)])
    let result = translate(old, new)
    let expected = raster(new)
    #expect(!expected.presentationLayers.filter { !$0.effects.isEmpty }.isEmpty)
    #expect(result.output.path != .incrementalTranslated)
    #expect(result.output.surface.cells == expected.cells)
    #expect(
      result.output.surface.presentationLayers.filter { !$0.effects.isEmpty }.map(\.bounds)
        == expected.presentationLayers.filter { !$0.effects.isEmpty }.map(\.bounds))
  }

  @Test func setA845DownwardBlitReadsEveryRowFromTheUnmodifiedPreviousSurface() throws {
    // Hypothesis: positive-dy copying reads already moved rows and duplicates one row through the destination band.
    let old = scrolling(first: 20)
    let new = scrolling(first: 17)
    let result = translate(old, new, dy: 3)
    let plan = try #require(result.plan)
    #expect(plan.translatedRows.count > 4)
    #expect(result.output.path == .incrementalTranslated)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(
      result.output.surface.cells[9][6].character != result.output.surface.cells[12][6].character)
    let damage = try #require(result.output.presentationDamage)
    #expect(Set(plan.translatedRows).isSubset(of: damage.dirtyRows))
  }

  @Test func setA846ClampingAPartlyOffscreenBandKeepsAbsoluteSourceRows() throws {
    // Hypothesis: viewport clamping rebases copied rows to the unclamped origin and shifts the wrong source buffers.
    let old = scrolling(first: 10)
    let new = scrolling(first: 11)
    let requestedBand = rect(-3, -4, 13, 20)
    let result = translate(old, new, band: requestedBand)
    let plan = try #require(result.plan)
    #expect(plan.band == rect(0, 0, 10, 16))
    #expect(result.output.path == .incrementalTranslated)
    #expect(result.output.surface.cells == raster(new).cells)
  }

  @Test func setA847ResizingTheRasterDeclinesAPlanForTheOldSurfaceGeometry() {
    // Hypothesis: a sound plan for the old width serves short row buffers into the expanded surface.
    let old = scrolling(first: 10)
    let newSize = CellSize(width: 15, height: 18)
    let new = scrolling(first: 11, size: newSize)
    let result = translate(old, new, currentSize: newSize)
    #expect(result.plan != nil)
    #expect(result.output.path != .incrementalTranslated)
    #expect(result.output.surface.size == newSize)
    #expect(result.output.surface.cells == raster(new, size: newSize).cells)
  }

  @Test func setA848WideLinkedGlyphAcrossTheBandEdgeCannotSplitItsOwnership() {
    // Hypothesis: flank verification ignores link/continuation metadata on a glyph whose lead is outside the band.
    func wideRows(first: Int) -> [DrawNode] {
      (0..<14).map { index in
        let dataset = first + index
        let bounds = rect(1, 2 + index, 2, 1)
        return node(
          "wide-\(dataset)", bounds,
          commands: [linked("界", bounds, destination: "https://example.com/\(dataset)")])
      }
    }
    let old = scrolling(first: 10, before: wideRows(first: 10))
    let new = scrolling(first: 11, before: wideRows(first: 11))
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][1].hyperlink == "https://example.com/16")
    #expect(result.output.surface.cells[7][2].hyperlink == "https://example.com/16")
    #expect(result.output.surface.cells[7][2].continuationLeadX == 1)
  }

  @Test func setA849PostCommandReorderingCannotBeHiddenByMatchingChildTwins() {
    // Hypothesis: translated child matching bypasses reversed post-paint commands and keeps the old overdraw color.
    func wrapper(_ y: Int, reverse: Bool) -> DrawNode {
      let bounds = rect(2, y, 2, 4)
      let paints = [fill(.color(.red), bounds), fill(.color(.blue), bounds)]
      var value = node(
        "post-wrapper", bounds,
        children: [node("under-post", bounds, commands: [text("A\nB\nC\nD", bounds)])])
      value.postCommands = reverse ? Array(paints.reversed()) : paints
      return value
    }
    let old = scrolling(first: 10, after: [wrapper(7, reverse: false)])
    let new = scrolling(first: 11, after: [wrapper(6, reverse: true)])
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][2].style?.backgroundColor == .red)
  }

  @Test func setA850ChangedFlankStyleRepaintsDespiteUnchangedVisibleGlyphs() {
    // Hypothesis: whole-row copying verifies old flank glyphs but misses a current foreground-only flank change.
    func flank(_ color: Color) -> DrawNode {
      let bounds = rect(0, 7, 1, 1)
      return node(
        "flank", bounds,
        commands: [
          .preformattedText(
            bounds: bounds, lines: ["X"],
            style: .init(foregroundStyle: .color(color)))
        ])
    }
    let old = scrolling(first: 10, after: [flank(.red)])
    let new = scrolling(first: 11, after: [flank(.blue)])
    let result = translate(old, new)
    #expect(result.output.surface.cells == raster(new).cells)
    #expect(result.output.surface.cells[7][0].character == "X")
    #expect(result.output.surface.cells[7][0].style?.foregroundColor == .blue)
  }

  private var size: CellSize { .init(width: 12, height: 18) }
  private var band: CellRect { rect(2, 2, 8, 14) }

  private func firstDifference(_ actual: RasterSurface, _ expected: RasterSurface) -> String {
    guard actual.cells.count == expected.cells.count else { return "different row counts" }
    for y in actual.cells.indices {
      guard actual.cells[y].count == expected.cells[y].count else {
        return "different column counts at row \(y)"
      }
      for x in actual.cells[y].indices where actual.cells[y][x] != expected.cells[y][x] {
        let a = actual.cells[y][x]
        let e = expected.cells[y][x]
        return
          "cell (\(x),\(y)): actual '\(a.character)' span \(a.spanWidth), expected '\(e.character)' span \(e.spanWidth)"
      }
    }
    return "equal cells"
  }

  private func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CellRect {
    .init(origin: .init(x: x, y: y), size: .init(width: width, height: height))
  }

  private func text(_ content: String, _ bounds: CellRect) -> DrawCommand {
    .preformattedText(
      bounds: bounds, lines: content.split(separator: "\n").map(String.init), style: .init())
  }

  private func linked(_ content: String, _ bounds: CellRect, destination: String) -> DrawCommand {
    .richText(
      bounds: bounds, payload: .init(runs: [.init(text: content, destination: .init(destination))]),
      lineLimit: nil, truncationMode: .tail, wrappingStrategy: .wordBoundary)
  }

  private func fill(_ paint: AnyShapeStyle, _ bounds: CellRect) -> DrawCommand {
    .fill(bounds: bounds, geometry: .rectangle, insetAmount: 0, style: paint, mode: .full)
  }

  private func rule(_ bounds: CellRect, stroke: StrokeStyle = .single, vertical: Bool = false)
    -> DrawCommand
  {
    .rule(
      bounds: bounds, style: .color(.white), strokeStyle: stroke,
      stackAxis: vertical ? .horizontal : .vertical)
  }

  private func stroke(_ bounds: CellRect, stroke: StrokeStyle = .single) -> DrawCommand {
    .stroke(
      bounds: bounds, geometry: .rectangle, insetAmount: 0, style: .color(.white),
      strokeStyle: stroke, strokeBorder: false)
  }

  private func node(
    _ id: String, _ bounds: CellRect, clip: CellRect? = nil,
    commands: [DrawCommand] = [], children: [DrawNode] = []
  ) -> DrawNode {
    .init(
      identity: testIdentity("setARasterTranslation", id), bounds: bounds,
      clipBounds: clip, commands: commands, children: children)
  }

  private func root(_ bounds: CellRect, commands: [DrawCommand] = [], children: [DrawNode] = [])
    -> DrawNode
  {
    node("root", bounds, commands: commands, children: children)
  }

  private func scrolling(
    first: Int, before: [DrawNode] = [], after: [DrawNode] = [],
    size overrideSize: CellSize? = nil
  ) -> DrawNode {
    let rows = (0..<14).map { index in
      let dataset = first + index
      let bounds = rect(4, 2 + index, 4, 1)
      return node("row-\(dataset)", bounds, commands: [text("r\(dataset)", bounds)])
    }
    let list = node("list", band, clip: band, children: rows)
    return root(.init(origin: .zero, size: overrideSize ?? size), children: before + [list] + after)
  }

  private func raster(_ node: DrawNode, size overrideSize: CellSize? = nil) -> RasterSurface {
    Rasterizer().rasterize(node, minimumSize: overrideSize ?? size)
  }

  private func translate(
    _ previous: DrawNode, _ current: DrawNode, dy: Int = -1,
    band overrideBand: CellRect? = nil, currentSize: CellSize? = nil
  )
    -> (output: Rasterizer.RasterizationResult, plan: RasterTranslationPlan?)
  {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let previousSurface = rasterizer.rasterize(previous, minimumSize: size)
    let plan = FrameTailPresentationDamageResolver.translationPlan(
      candidate: .init(
        routeIdentity: testIdentity("setARasterTranslation", "list"),
        band: overrideBand ?? band, dy: dy), surfaceSize: previousSurface.size,
      previousDraw: previous, currentDraw: current)
    // Full damage makes fallback painting sound independently of the planner. Disable
    // automatic repair so the fresh-raster assertions can observe an unsound served row.
    let output = rasterizer.rasterizeCollectingVisibleIdentities(
      current, minimumSize: currentSize ?? size, previousSurface: previousSurface,
      damage: .init(dirtyRows: Set(0..<max(size.height, currentSize?.height ?? 0))),
      verifyIncrementalRasterDamage: false, translation: plan)
    return (output, plan)
  }

  private struct GridPayload: ForeignSurfacePayload {
    let grid: ForeignGrid
  }

  private struct GlyphDrawing: CanvasDrawing {
    let glyph: Character

    func draw(into context: inout CanvasContext) {
      for y in 0..<4 {
        for x in 0..<2 { context.setCell(at: .init(x: x, y: y), character: glyph) }
      }
    }
  }
}
