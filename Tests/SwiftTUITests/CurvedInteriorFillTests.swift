import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct CurvedInteriorFillTests {
  @Test("T267: curved stroke borders inset background fills", arguments: 0..<3, [false, true])
  func curvedBordersInsetBackground(shape: Int, gradient: Bool) throws {
    let width = shape == 0 ? 12 : 14
    func render<S: InsettableShape>(_ shape: S) -> RenderSnapshot {
      let background = LinearGradient(
        colors: [Color.blue, Color.blue],
        startPoint: .leading, endPoint: .trailing)
      func renderBackground<B: ShapeStyle>(_ fill: B) -> RenderSnapshot {
        DefaultRenderer().render(
          EmptyView().frame(width: width, height: 6, alignment: .topLeading)
            .background(fill)
            .overlay { shape.strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2)) },
          context: .init(identity: testIdentity("T267")))
      }
      return gradient ? renderBackground(background) : renderBackground(Color.blue)
    }
    let snapshot: RenderSnapshot
    switch shape {
    case 0: snapshot = render(Circle())
    case 1: snapshot = render(Ellipse())
    default: snapshot = render(Capsule())
    }
    let cells = snapshot.rasterSurface.cells
    let centerStyle = cells[3][width / 2].style
    let interior = try #require(centerStyle?.backgroundColor ?? centerStyle?.foregroundColor)
    #expect(abs(interior.red - Color.blue.red) < 0.00001)
    #expect(abs(interior.green - Color.blue.green) < 0.00001)
    #expect(abs(interior.blue - Color.blue.blue) < 0.00001)
    #expect(cells[3][1].style?.foregroundColor == nil)
    #expect(cells[3][1].style?.backgroundColor == nil)
  }
}
