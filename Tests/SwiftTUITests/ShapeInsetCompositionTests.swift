import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct ShapeInsetCompositionTests {
  @Test func signedInsetsComposeAndAffectPublicPaths() {
    let rect = Rect(origin: .init(x: 2, y: 3), size: .init(width: 8, height: 6))
    let shape = Rectangle().inset(by: -2).inset(by: 1)
    #expect(shape.insetAmount == -1)
    #expect(
      shape.path(in: rect).boundingRect
        == Rect(
          origin: .init(x: 1, y: 2), size: .init(width: 10, height: 8)))
  }

  @Test func negativeInsetClipAdmitsContentOutsideTheLayoutSlot() {
    let view = Rectangle().fill(Color.red).frame(width: 8, height: 6)
      .frame(width: 4, height: 2)
      .clipShape(Rectangle().inset(by: -1))
      .padding(2)
    let snapshot = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("InsetClip")))
    let painted = snapshot.rasterSurface.cells.flatMap { $0 }.filter {
      $0.style?.backgroundColor == .red
    }
    #expect(painted.count == 24)
  }

  @Test func expandedPaintParticipatesInSurfaceExtentAndIncrementalDamage() {
    let bounds = CellRect(origin: .init(x: 2, y: 2), size: .init(width: 4, height: 2))
    func draw(_ color: Color) -> DrawNode {
      .init(
        identity: testIdentity("SignedInsetPaint"), bounds: bounds,
        commands: [
          .fill(
            bounds: bounds, geometry: .rectangle, insetAmount: -1, style: .color(color), mode: .full
          )
        ])
    }
    let red = draw(.red)
    let blue = draw(.blue)
    #expect(
      blue.subtreeBounds
        == CellRect(
          origin: .init(x: 1, y: 1),
          size: .init(width: 6, height: 4)))
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let previous = rasterizer.rasterize(red)
    let fresh = Rasterizer().rasterize(blue)
    #expect(fresh.size == CellSize(width: 7, height: 5))
    let changed = rasterizer.rasterizeCollectingVisibleIdentities(
      blue, minimumSize: .zero, previousSurface: previous,
      damage: .init(dirtyRows: Set(blue.subtreeBounds.origin.y..<blue.subtreeBounds.maxY)),
      verifyIncrementalRasterDamage: false)
    #expect(changed.surface.cells == fresh.cells)
    #expect(fresh.cells[4][6].style?.backgroundColor == .blue)
  }
}
