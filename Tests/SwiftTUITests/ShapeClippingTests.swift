import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private struct HalfClip: InsettableShape {
  var fraction: Double = 0.5
  func path(in rect: Rect) -> Path {
    Path(
      Rect(
        origin: rect.origin,
        size: .init(width: rect.size.width * fraction, height: rect.size.height)))
  }
}

/// A triangle that leaves its last edge, back to the start, to the fill unless it
/// `closes`.
private struct Wedge: Shape {
  var closes: Bool

  func path(in rect: Rect) -> Path {
    var path = Path()
    path.move(to: rect.origin)
    path.addLine(to: Point(x: rect.maxX, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x + rect.size.width / 2, y: rect.maxY))
    if closes { path.close() }
    return path
  }
}

@MainActor
struct ShapeClippingTests {
  @Test("nested masks intersect, wide glyphs stay atomic and cell damage remains incremental")
  func nestedAndIncremental() {
    let snapshot = DefaultRenderer().render(
      Text("界界界界\nabcdefgh\nabcdefgh\nabcdefgh")
        .frame(width: 8, height: 4)
        .clipShape(HalfClip()).clipShape(Rectangle().inset(by: 1)))
    #expect(
      snapshot.rasterSurface.cells.map { String($0.map(\.character)) }
        == ["        ", " bcd    ", " bcd    ", "        "])
    let wide = DefaultRenderer().render(Text("界界").clipShape(HalfClip().inset(by: 0)))
    #expect(wide.rasterSurface.cells[0][0].character == "界")
    #expect(wide.rasterSurface.cells[0][2].character == " ")
    let cut = DefaultRenderer().render(Text("界a").clipShape(HalfClip(fraction: 0.25)))
    #expect(cut.rasterSurface.cells[0].allSatisfy { $0.character == " " })
    let replay = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
      .rasterizeCollectingVisibleIdentities(
        snapshot.drawTree, minimumSize: .zero,
        previousSurface: snapshot.rasterSurface, damage: .init(textRows: [.init(row: 1)]))
    #expect(replay.path == .incremental)
    #expect(replay.surface == snapshot.rasterSurface)
  }

  @Test("curved image masks preserve source placement and full/repaint equivalence")
  func imageFragments() {
    let snapshot = DefaultRenderer().render(
      Image(data: [1, 2, 3]).resizable().frame(width: 12, height: 8).clipShape(Ellipse()))
    let fragments = snapshot.rasterSurface.imageAttachments
    #expect(fragments.count > 1)
    var covered: Set<CellPoint> = []
    for fragment in fragments {
      #expect(fragment.bounds == .init(origin: .zero, size: .init(width: 12, height: 8)))
      #expect(fragment.source == .data([1, 2, 3]))
      for y in fragment.visibleBounds.origin.y..<fragment.visibleBounds.maxY {
        for x in fragment.visibleBounds.origin.x..<fragment.visibleBounds.maxX {
          #expect(covered.insert(.init(x: x, y: y)).inserted)
        }
      }
    }
    #expect(covered.contains(.init(x: 6, y: 4)))
    #expect(!covered.contains(.zero))
    let replay = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
      .rasterizeCollectingVisibleIdentities(
        snapshot.drawTree, minimumSize: .zero,
        previousSurface: snapshot.rasterSurface, damage: .init(textRows: [.init(row: 3)]))
    #expect(replay.path == .fresh)
    #expect(replay.surface == snapshot.rasterSurface)
    let introduced = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
      .rasterizeCollectingVisibleIdentities(
        snapshot.drawTree, minimumSize: .zero,
        previousSurface: .init(
          size: snapshot.rasterSurface.size, cells: snapshot.rasterSurface.cells),
        damage: .init(textRows: (0..<8).map { .init(row: $0) }))
    #expect(introduced.path == .fresh)
    #expect(introduced.surface == snapshot.rasterSurface)
  }

  @Test("empty masks suppress paint without changing layout or interaction geometry")
  func emptyAndInteraction() throws {
    let plain = DefaultRenderer().render(Button("Press") {}.frame(width: 8, height: 4))
    let masked = DefaultRenderer().render(
      Button("Press") {}.frame(width: 8, height: 4)
        .clipShape(Rectangle().inset(by: Int.max)))
    #expect(masked.rasterSurface.size == plain.rasterSurface.size)
    #expect(masked.rasterSurface.cells.flatMap { $0 }.allSatisfy { $0 == .empty })
    #expect(
      masked.semanticSnapshot.interactionRegions.map(\.rect)
        == plain.semanticSnapshot.interactionRegions.map(\.rect))
    #expect(!plain.semanticSnapshot.interactionRegions.isEmpty)
  }

  @Test("open subpaths clip, cell-fill and hit-test as the region a fill paints")
  func openSubpathsCloseLikeFill() throws {
    func rows(_ view: some View) -> [String] {
      DefaultRenderer().render(view).rasterSurface.cells.map { String($0.map(\.character)) }
    }
    let text = Text(
      Array(repeating: String(repeating: "x", count: 12), count: 6).joined(separator: "\n"))
    #expect(
      rows(text.frame(width: 12, height: 6).clipShape(Wedge(closes: false)))
        == rows(text.frame(width: 12, height: 6).clipShape(Wedge(closes: true))))
    let tile = TileStyle(.init(rows: ["x"]), foreground: Color.red)
    let tiled = rows(Wedge(closes: false).fill(tile).frame(width: 12, height: 6))
    #expect(tiled == rows(Wedge(closes: true).fill(tile).frame(width: 12, height: 6)))
    let solid = rows(Wedge(closes: false).fill(Color.red).frame(width: 12, height: 6))
    for (tileRow, solidRow) in zip(tiled, solid) {
      for (tile, paint) in zip(tileRow, solidRow) where tile == "x" {
        #expect(paint != " " && paint != "\u{2800}")
      }
    }

    var context = ResolveContext(identity: testIdentity("OpenContentShape"))
    context.localPointerHandlerRegistry = LocalPointerHandlerRegistry()
    context.localGestureRegistry = LocalGestureRegistry()
    context.localGestureStateRegistry = LocalGestureStateRegistry()
    let region = try #require(
      DefaultRenderer().render(
        Text("XXXXXXXX\nXXXXXXXX\nXXXXXXXX\nXXXXXXXX")
          .contentShape(
            Wedge(closes: false).path(in: .init(origin: .zero, size: .init(width: 8, height: 4)))
          )
          .gesture(TapGesture().onEnded {}),
        context: context,
        proposal: .init(width: 8, height: 4)
      ).semanticSnapshot.interactionRegions.first)
    func hits(_ x: Double, _ y: Double) -> Bool {
      region.contains(
        .subCell(
          location: Point(x: x, y: y), source: .nativePixels,
          metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)))
    }
    #expect(hits(4, 1))
    // Left of the implicit closing edge from (4, 4) back to (0, 0).
    #expect(!hits(0.5, 3))
  }
}
