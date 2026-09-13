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
}
