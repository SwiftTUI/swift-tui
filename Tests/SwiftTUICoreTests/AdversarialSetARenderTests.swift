import Testing

@testable import SwiftTUICore

/// Set A's second pass probes interactions between otherwise valid draw operations.
@Suite("Adversarial set A: render boundaries")
struct AdversarialSetARenderTests {
  @Test("set A 126: a wide overwrite repairs two different underlying glyphs")
  func setA126WideOverwriteRepairsBothNeighbors() {
    let bounds = rect(0, 0, 6, 1)
    let surface = render(
      bounds,
      commands: [
        text("A界語Z", in: bounds), text("寿", in: rect(2, 0, 2, 1)),
      ])
    #expect(surface.cells[0].map(\.character) == ["A", " ", "寿", " ", " ", "Z"])
    #expect(surface.cells[0][2].spanWidth == 2)
    #expect(surface.cells[0][3].continuationLeadX == 2)
    #expect(surface.cells[0][1] == .empty)
    #expect(surface.cells[0][4] == .empty)
  }

  @Test("set A 127: painting over a linked continuation removes the entire old glyph")
  func setA127OpaqueFillClearsWideLink() {
    let bounds = rect(0, 0, 5, 1)
    let surface = render(
      bounds,
      commands: [
        linked("A界Z", in: bounds, destination: "https://example.com/old"),
        fill(.color(.red), in: rect(2, 0, 1, 1)),
      ])
    #expect(surface.cells[0][1] == .empty)
    #expect(surface.cells[0][2].character == " ")
    #expect(surface.cells[0][2].continuationLeadX == nil)
    #expect(surface.cells[0][2].hyperlink == nil)
    #expect(surface.cells[0][2].style?.backgroundColor == .red)
    #expect(surface.cells[0][3].hyperlink == "https://example.com/old")
  }

  @Test("set A 128: transparent fill preserves styled linked cells and recorded layers")
  func setA128ClearFillIsIdentity() {
    let bounds = rect(0, 0, 6, 1)
    let command = linked("A界Z", in: bounds, destination: "https://example.com/keep")
    let previous = render(bounds, commands: [command])
    let overlaid = render(bounds, commands: [command, fill(.color(.clear), in: bounds)])
    #expect(overlaid == previous)
    #expect(overlaid.presentationLayers == previous.presentationLayers)
  }

  @Test("set A 129: clipping away a styled run preserves later run positions and styles")
  func setA129ClippedStyledRunKeepsFollowingColumns() {
    let bounds = rect(0, 0, 6, 1)
    let command = DrawCommand.styledPreformattedText(
      bounds: bounds,
      lines: [
        .init(runs: [
          .init(content: "AB", style: .init(foregroundStyle: .color(.red))),
          .init(content: "界", style: .init(foregroundStyle: .color(.green))),
          .init(content: "Z", style: .init(foregroundStyle: .color(.blue))),
        ])
      ], style: .init())
    let surface = render(bounds, commands: [command], clip: rect(2, 0, 3, 1))
    #expect(surface.cells[0][0] == .empty)
    #expect(surface.cells[0][1] == .empty)
    #expect(surface.cells[0][2].character == "界")
    #expect(surface.cells[0][2].style?.foregroundColor == .green)
    #expect(surface.cells[0][3].continuationLeadX == 2)
    #expect(surface.cells[0][4].character == "Z")
    #expect(surface.cells[0][4].style?.foregroundColor == .blue)
  }

  @Test("set A 130: head truncation keeps the tail run's link on both wide cells")
  func setA130TruncatedTailRetainsLinkOwnership() {
    let bounds = rect(0, 0, 4, 1)
    let command = DrawCommand.richText(
      bounds: bounds,
      payload: .init(runs: [
        .init(text: "AAAA", destination: "https://example.com/head"),
        .init(text: "界Z", destination: "https://example.com/tail"),
      ]), lineLimit: 1, truncationMode: .head, wrappingStrategy: .wordBoundary)
    let surface = render(bounds, commands: [command])
    #expect(surface.lines == ["…界Z"])
    #expect(surface.cells[0][0].hyperlink == nil)
    #expect(
      surface.cells[0][1...3].allSatisfy {
        $0.hyperlink == "https://example.com/tail"
      })
    #expect(surface.cells[0][2].continuationLeadX == 1)
  }

  @Test("set A 131: flattening a clipped compositing group preserves the surrounding underlay")
  func setA131ClippedCompositingGroupPreservesOutsideCells() {
    let bounds = rect(0, 0, 8, 3)
    let node = DrawNode(
      identity: testIdentity("setA131"), bounds: bounds,
      commands: [text("AAAAAAAA\nBBBBBBBB\nCCCCCCCC", in: bounds)],
      children: [
        DrawNode(
          identity: testIdentity("setA131", "group"), bounds: bounds,
          clipBounds: rect(2, 1, 3, 1), drawEffects: .init([.compositingGroup]),
          commands: [text("12345678\nabcdefgh\n87654321", in: bounds)])
      ])
    let surface = Rasterizer().rasterize(node, minimumSize: bounds.size)
    #expect(surface.lines == ["AAAAAAAA", "BBcdeBBB", "CCCCCCCC"])
    #expect(surface.cells[1][1].character == "B")
    #expect(surface.cells[1][5].character == "B")
  }

  @Test("set A 132: post commands overdraw descendants while honoring the node clip")
  func setA132PostCommandsRespectClipAndOrder() {
    let bounds = rect(0, 0, 6, 1)
    let node = DrawNode(
      identity: testIdentity("setA132"), bounds: bounds, clipBounds: rect(1, 0, 4, 1),
      commands: [text("AAAAAA", in: bounds)],
      postCommands: [text("ZZZZ", in: rect(3, 0, 4, 1))],
      children: [
        DrawNode(
          identity: testIdentity("setA132", "child"), bounds: bounds,
          commands: [text("BBBBBB", in: bounds)])
      ])
    let surface = Rasterizer().rasterize(node, minimumSize: bounds.size)
    #expect(surface.lines == [" BBZZ"])
    #expect(surface.cells[0][0] == .empty)
    #expect(surface.cells[0][5] == .empty)
  }

  @Test("set A 133: one child's disjoint clip cannot suppress its following sibling")
  func setA133ClipsDoNotLeakAcrossSiblings() {
    let bounds = rect(0, 0, 6, 1)
    let node = DrawNode(
      identity: testIdentity("setA133"), bounds: bounds, clipBounds: rect(1, 0, 4, 1),
      children: [
        DrawNode(
          identity: testIdentity("setA133", "hidden"), bounds: bounds,
          clipBounds: rect(7, 0, 1, 1), commands: [text("XXXXXX", in: bounds)]),
        DrawNode(
          identity: testIdentity("setA133", "visible"), bounds: bounds,
          commands: [text("ABCDEF", in: bounds)]),
      ])
    let result = Rasterizer().rasterizeCollectingVisibleIdentities(
      node, minimumSize: bounds.size, previousSurface: nil, damage: nil)
    #expect(result.surface.lines == [" BCDE"])
    #expect(!result.visibleIdentities.contains(testIdentity("setA133", "hidden")))
    #expect(result.visibleIdentities.contains(testIdentity("setA133", "visible")))
  }

  @Test("set A 134: clipping a translated gradient preserves its original sample coordinates")
  func setA134GradientClipPreservesSamplingCoordinates() {
    let bounds = rect(0, 0, 9, 3)
    let gradientBounds = rect(-3, -1, 12, 4)
    let gradient = AnyShapeStyle(
      LinearGradient(
        colors: [.red, .green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
    let command = fill(gradient, in: gradientBounds)
    let full = render(bounds, commands: [command])
    let clipped = render(bounds, commands: [command], clip: rect(2, 1, 4, 1))
    for x in 2..<6 { #expect(clipped.cells[1][x] == full.cells[1][x]) }
    #expect(clipped.cells[0].allSatisfy { $0 == .empty })
    #expect(clipped.cells[1][1] == .empty)
    #expect(clipped.cells[1][6] == .empty)
    #expect(full.cells[1][2].style != full.cells[1][5].style)
  }

  @Test("set A 135: a constant translucent gradient tints like the corresponding solid fill")
  func setA135ConstantGradientAndSolidTintAgree() throws {
    let bounds = rect(0, 0, 4, 1)
    let tint = Color(red: 0.7, green: 0.2, blue: 0.4, alpha: 0.3)
    let underlay = linked("界AZ", in: bounds, destination: "https://example.com/tint")
    let solid = render(bounds, commands: [underlay, fill(.color(tint), in: bounds)])
    let gradient = render(
      bounds,
      commands: [
        underlay,
        fill(
          AnyShapeStyle(
            LinearGradient(
              colors: [tint, tint], startPoint: .leading, endPoint: .trailing)), in: bounds),
      ])
    for x in 0..<4 {
      #expect(gradient.cells[0][x].character == solid.cells[0][x].character)
      #expect(gradient.cells[0][x].continuationLeadX == solid.cells[0][x].continuationLeadX)
      #expect(gradient.cells[0][x].hyperlink == solid.cells[0][x].hyperlink)
      let lhs = try #require(gradient.cells[0][x].style?.backgroundColor)
      let rhs = try #require(solid.cells[0][x].style?.backgroundColor)
      expectColor(lhs, equals: rhs)
    }
  }

  @Test("set A 136: a radial gradient's transparent outer support leaves existing text intact")
  func setA136RadialSupportDoesNotEraseOutsideCells() {
    let bounds = rect(0, 0, 9, 5)
    let underlay = text("ABCDEFGHI\nJKLMNOPQR\nSTUVWXYZA\nBCDEFGHIJ\nKLMNOPQRS", in: bounds)
    let initial = render(bounds, commands: [underlay])
    let radial = AnyShapeStyle(
      RadialGradient(
        colors: [.red, .clear], center: .center, startRadius: 0, endRadius: 1))
    let result = render(bounds, commands: [underlay, fill(radial, in: bounds)])
    #expect(result.cells[0] == initial.cells[0])
    #expect(result.cells[4] == initial.cells[4])
    #expect(result.cells[2][0] == initial.cells[2][0])
    #expect(result.cells[2][8] == initial.cells[2][8])
    #expect(result.cells[2][4] != initial.cells[2][4])
  }

  @Test("set A 137: a ragged foreign grid cannot erase cells beyond its supplied rows")
  func setA137RaggedForeignGridPreservesUnprovidedCells() {
    let bounds = rect(0, 0, 5, 3)
    let payload = ForeignPayload(
      grid: .init(
        size: .init(width: 3, height: 3),
        cells: [[.init(character: "X")], [.init(character: "Y"), .init(character: "Z")]]))
    let surface = render(
      bounds,
      commands: [
        text("ABCDE\nFGHIJ\nKLMNO", in: bounds),
        .foreignSurface(bounds: rect(1, 0, 3, 3), payload: payload),
      ])
    #expect(surface.lines == ["AXCDE", "FYZIJ", "KLMNO"])
  }

  @Test("set A 138: a negative foreign origin never exposes an orphaned continuation")
  func setA138NegativeForeignOriginRepairsCutGlyph() {
    let bounds = rect(0, 0, 4, 1)
    let payload = ForeignPayload(
      grid: .init(
        size: .init(width: 3, height: 1),
        cells: [
          [
            .init(character: "界", spanWidth: 2),
            .init(character: " ", spanWidth: 0, continuationLeadX: 0),
            .init(character: "Z"),
          ]
        ]))
    let surface = render(
      bounds,
      commands: [
        .foreignSurface(bounds: rect(-1, 0, 3, 1), payload: payload)
      ])
    #expect(surface.cells[0][0] == .empty)
    #expect(surface.cells[0][1].character == "Z")
    #expect(surface.cells[0].allSatisfy { !$0.isContinuation })
  }

  @Test("set A 139: the foreign blend path preserves complete wide glyphs and hyperlinks")
  func setA139ForeignNormalBlendMatchesUnblendedOnEmptySurface() {
    let bounds = rect(0, 0, 6, 2)
    let style = ResolvedTextStyle(foregroundColor: .cyan, backgroundColor: .blue)
    let payload = ForeignPayload(
      grid: .init(
        size: .init(width: 3, height: 1),
        cells: [
          [
            .init(
              character: "界", spanWidth: 2, style: style, hyperlink: "https://example.com/grid"),
            .init(
              character: " ", spanWidth: 0, continuationLeadX: 0, style: style,
              hyperlink: "https://example.com/grid"),
            .init(character: "!", style: style),
          ]
        ]))
    var node = DrawNode(
      identity: testIdentity("setA139"), bounds: bounds,
      commands: [.foreignSurface(bounds: rect(2, 1, 3, 1), payload: payload)])
    let plain = Rasterizer().rasterize(node)
    node.drawEffects = .init([.blendMode(.normal)])
    let blended = Rasterizer().rasterize(node)
    #expect(blended.cells == plain.cells)
    #expect(blended.cells[1][3].continuationLeadX == 2)
    #expect(blended.cells[1][3].hyperlink == "https://example.com/grid")
  }

  @Test("set A 140: independent top and left occluders intersect an image's visible remainder")
  func setA140TwoImageOccludersCompose() throws {
    let bounds = rect(0, 0, 5, 4)
    let surface = render(
      bounds,
      commands: [
        image(in: bounds), fill(.color(.red), in: rect(0, 0, 5, 1)),
        fill(.color(.blue), in: rect(0, 0, 1, 4)),
      ])
    let attachment = try #require(surface.imageAttachments.first)
    #expect(attachment.visibleBounds == bounds)
    #expect(attachment.effectiveVisibleBounds == rect(1, 1, 4, 3))
  }

  @Test("set A 141: a transparent overlay records no image occlusion")
  func setA141TransparentOverlayDoesNotTrimImage() throws {
    let bounds = rect(0, 0, 4, 3)
    let surface = render(bounds, commands: [image(in: bounds), fill(.color(.clear), in: bounds)])
    let attachment = try #require(surface.imageAttachments.first)
    #expect(attachment.unoccludedVisibleBounds == nil)
    #expect(attachment.effectiveVisibleBounds == bounds)
    #expect(surface.presentationLayers.count == 1)
  }

  @Test("set A 142: nested node clips keep an image's logical scale separate from visibility")
  func setA142ImageClipsPreserveLogicalBounds() throws {
    let bounds = rect(0, 0, 6, 4)
    let node = DrawNode(
      identity: testIdentity("setA142"), bounds: bounds, clipBounds: rect(1, 0, 3, 4),
      children: [
        DrawNode(
          identity: testIdentity("setA142", "image"), bounds: bounds,
          clipBounds: rect(2, 1, 4, 2), commands: [image(in: bounds)])
      ])
    let surface = Rasterizer().rasterize(node, minimumSize: bounds.size)
    let attachment = try #require(surface.imageAttachments.first)
    #expect(attachment.bounds == bounds)
    #expect(attachment.visibleBounds == rect(2, 1, 2, 2))
    #expect(attachment.effectiveVisibleBounds == rect(2, 1, 2, 2))
  }

  @Test("set A 143: removing an image in a damaged row clears attachment and retained layer")
  func setA143IncrementalImageRemovalClearsAllRepresentations() {
    let bounds = rect(0, 0, 5, 4)
    let base = text("AAAAA\nBBBBB\nCCCCC\nDDDDD", in: bounds)
    let previous = draw(bounds, commands: [base, image(in: rect(1, 1, 2, 1))])
    let current = draw(bounds, commands: [base])
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let priorSurface = rasterizer.rasterize(previous)
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current, minimumSize: bounds.size, previousSurface: priorSurface,
      damage: .init(dirtyRows: [1]))
    #expect(result.path == .incremental)
    #expect(result.surface == rasterizer.rasterize(current))
    #expect(result.surface.imageAttachments.isEmpty)
    #expect(
      !result.surface.presentationLayers.contains {
        if case .image = $0.content { return true }
        return false
      })
  }

  @Test("set A 144: moving linked text clears its old row during trusted incremental paint")
  func setA144MovingLinkLeavesNoGhostCells() {
    let bounds = rect(0, 0, 6, 4)
    let previous = draw(
      bounds,
      commands: [
        linked("界Z", in: rect(1, 0, 3, 1), destination: "https://example.com/move")
      ])
    let current = draw(
      bounds,
      commands: [
        linked("界Z", in: rect(2, 3, 3, 1), destination: "https://example.com/move")
      ])
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current, minimumSize: bounds.size, previousSurface: rasterizer.rasterize(previous),
      damage: .init(dirtyRows: [0, 3]))
    #expect(result.path == .incremental)
    #expect(result.surface == rasterizer.rasterize(current))
    #expect(result.surface.cells[0].allSatisfy { $0 == .empty })
    #expect(result.surface.cells[3][3].continuationLeadX == 2)
    #expect(result.surface.cells[3][4].hyperlink == "https://example.com/move")
  }

  @Test("set A 145: making a covering fill transparent restores the underlying link")
  func setA145TransparentTransitionRestoresUnderlay() {
    let bounds = rect(0, 0, 5, 3)
    let underlay = linked("A界Z", in: rect(0, 1, 5, 1), destination: "https://example.com/reveal")
    let previous = draw(bounds, commands: [underlay, fill(.color(.blue), in: rect(0, 1, 5, 1))])
    let current = draw(bounds, commands: [underlay, fill(.color(.clear), in: rect(0, 1, 5, 1))])
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current, minimumSize: bounds.size, previousSurface: rasterizer.rasterize(previous),
      damage: .init(dirtyRows: [1]))
    #expect(result.path == .incremental)
    #expect(result.surface == rasterizer.rasterize(current))
    #expect(result.surface.cells[1][1].character == "界")
    #expect(result.surface.cells[1][2].hyperlink == "https://example.com/reveal")
    #expect(result.surface.cells[0].allSatisfy { $0 == .empty })
  }

  @Test("set A 146: a hyperlink-only change damages the complete occupied wide span")
  func setA146HyperlinkOnlyDamageIncludesContinuation() {
    let bounds = rect(0, 0, 5, 1)
    let previous = render(
      bounds,
      commands: [
        linked("界", in: rect(1, 0, 2, 1), destination: "https://example.com/one")
      ])
    let current = render(
      bounds,
      commands: [
        linked("界", in: rect(1, 0, 2, 1), destination: "https://example.com/two")
      ])
    #expect(previous.lines == current.lines)
    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [.init(row: 0, columnRanges: [1..<3])]))
  }

  @Test("set A 147: shifted wide glyph damage merges overlapping spans without filling gaps")
  func setA147ShiftedWideGlyphDamageKeepsDisjointChange() {
    let size = CellSize(width: 8, height: 1)
    let previous = RasterSurface(size: size, lines: ["A界 BC D"])
    let current = RasterSurface(size: size, lines: ["A 界BC!D"])
    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [.init(row: 0, columnRanges: [1..<4, 6..<7])]))
  }

  @Test("set A 148: translucent background composition is independent of source color encoding")
  func setA148BackgroundCompositionPreservesSourceProfile() throws {
    let linear = Color(red: 0.45, green: 0.2, blue: 0.65, alpha: 0.4, profile: .linearSRGB)
    let encoded = linear.converted(to: .sRGB, gamutMapping: .preserve)
    let underlay = ResolvedTextStyle(backgroundColor: Color(red: 0.1, green: 0.3, blue: 0.2))
    let a = ResolvedTextStyle(backgroundColor: linear).composited(over: underlay)
    let b = ResolvedTextStyle(backgroundColor: encoded).composited(over: underlay)
    let lhs = try #require(a.backgroundColor)
    let rhs = try #require(b.backgroundColor)
    // The translucent-background branch rebuilds the overlay from RGB alone,
    // interpreting linear-sRGB components as encoded sRGB before mixing.
    withKnownIssue(
      "STUI-957: background composition discards the translucent overlay's color profile"
    ) {
      #expect(lhs.deltaE(to: rhs) < 0.0001)
    }
    #expect(abs(lhs.alpha - rhs.alpha) < 0.000001)
  }

  @Test("set A 149: source-over computes unpremultiplied channels with partial backdrop alpha")
  func setA149PartialAlphaSourceOverMatchesArithmetic() {
    let source = Color(red: 0.8, green: 0.2, blue: 0.4, alpha: 0.25, profile: .linearSRGB)
    let backdrop = Color(red: 0.1, green: 0.6, blue: 0.3, alpha: 0.5, profile: .linearSRGB)
    let actual = source.composited(over: backdrop, mode: .normal, workingSpace: .linearSRGB)
    // Alpha = 1/4 + (1/2)(3/4) = 5/8. RGB divides the premultiplied sum by 5/8.
    expectColor(
      actual,
      equals: Color(
        red: 0.38, green: 0.44, blue: 0.34, alpha: 0.625, profile: .linearSRGB))
  }

  @Test("set A 150: regrouping source-over layers preserves color and alpha")
  func setA150LinearSourceOverIsAssociative() {
    let top = Color(red: 0.7, green: 0.2, blue: 0.4, alpha: 0.2, profile: .linearSRGB)
    let middle = Color(red: 0.2, green: 0.8, blue: 0.1, alpha: 0.45, profile: .linearSRGB)
    let base = Color(red: 0.1, green: 0.3, blue: 0.9, alpha: 0.6, profile: .linearSRGB)
    let grouped = top.composited(over: middle).composited(over: base)
    let ungrouped = top.composited(over: middle.composited(over: base))
    expectColor(grouped, equals: ungrouped)
    #expect(abs(grouped.alpha - 0.824) < 0.000001)
  }

  private struct ForeignPayload: ForeignSurfacePayload {
    let grid: ForeignGrid
  }

  private func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CellRect {
    .init(origin: .init(x: x, y: y), size: .init(width: width, height: height))
  }

  private func text(_ content: String, in bounds: CellRect) -> DrawCommand {
    .preformattedText(
      bounds: bounds, lines: content.split(separator: "\n").map(String.init),
      style: .init())
  }

  private func linked(_ content: String, in bounds: CellRect, destination: String) -> DrawCommand {
    .richText(
      bounds: bounds,
      payload: .init(runs: [.init(text: content, destination: .init(destination))]),
      lineLimit: nil, truncationMode: .tail, wrappingStrategy: .wordBoundary)
  }

  private func fill(_ style: AnyShapeStyle, in bounds: CellRect) -> DrawCommand {
    .fill(bounds: bounds, geometry: .rectangle, insetAmount: 0, style: style, mode: .full)
  }

  private func image(in bounds: CellRect) -> DrawCommand {
    .image(
      bounds: bounds, identity: testIdentity("setARenderImage"),
      payload: .init(source: .path("set-a-render-fixture.png")))
  }

  private func draw(_ bounds: CellRect, commands: [DrawCommand], clip: CellRect? = nil) -> DrawNode
  {
    .init(
      identity: testIdentity("setARender"), bounds: bounds, clipBounds: clip, commands: commands)
  }

  private func render(
    _ bounds: CellRect, commands: [DrawCommand], clip: CellRect? = nil
  ) -> RasterSurface {
    Rasterizer().rasterize(draw(bounds, commands: commands, clip: clip), minimumSize: bounds.size)
  }

  private func expectColor(_ actual: Color, equals expected: Color) {
    #expect(abs(actual.red - expected.red) < 0.000001)
    #expect(abs(actual.green - expected.green) < 0.000001)
    #expect(abs(actual.blue - expected.blue) < 0.000001)
    #expect(abs(actual.alpha - expected.alpha) < 0.000001)
  }
}
