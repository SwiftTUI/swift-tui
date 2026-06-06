// Plain import: a first-class custom Shape conformer compiles with only
// `path(in:)` (or only `geometry`).
import SwiftTUIViews
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

private func brailleDotCount(_ cell: RasterCell) -> Int {
  guard let scalar = cell.character.unicodeScalars.first?.value,
    scalar >= 0x2800,
    scalar <= 0x28FF
  else {
    return 0
  }
  return Int(scalar - 0x2800).nonzeroBitCount
}

private func litCellCount(_ artifacts: FrameArtifacts) -> Int {
  var count = 0
  for row in artifacts.rasterSurface.cells {
    for cell in row where brailleDotCount(cell) > 0 {
      count += 1
    }
  }
  return count
}

/// A first-class custom shape defined by `path(in:)` only — the SwiftUI
/// authoring surface. `path(in:)` receives the unit rect at resolve time.
private struct CustomTriangle: InsettableShape {
  func path(in rect: Rect) -> Path {
    var path = Path()
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: rect.maxX, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x + rect.size.width / 2, y: rect.maxY))
    path.close()
    return path
  }
}

/// The same triangle, but defined by `geometry` directly (the forward-default
/// bridge from `path(in:)` should produce identical rendering).
private struct DirectTriangle: InsettableShape {
  var geometry: ShapeGeometry {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addLine(to: Point(x: 1, y: 0))
    path.addLine(to: Point(x: 0.5, y: 1))
    path.close()
    return .path(BoxedPath(path), .nonZero)
  }
}

@MainActor
@Suite("Custom path Shape authoring + composition")
struct PathCustomShapeTests {

  @Test("path(in:) bridges to .path geometry identically to a direct geometry")
  func forwardDefaultBridge() {
    let viaPath = DefaultRenderer().render(
      CustomTriangle().fill(Color.white).frame(width: 12, height: 6),
      context: .init(identity: testIdentity("ViaPathInRect"))
    )
    let viaGeometry = DefaultRenderer().render(
      DirectTriangle().fill(Color.white).frame(width: 12, height: 6),
      context: .init(identity: testIdentity("ViaGeometry"))
    )
    #expect(viaPath.rasterSurface == viaGeometry.rasterSurface)
  }

  @Test("a path(in:) shape composes with fill / stroke / strokeBorder / foregroundStyle")
  func composesWithModifierAlgebra() {
    let filled = DefaultRenderer().render(
      CustomTriangle().fill(Color.white).frame(width: 12, height: 6),
      context: .init(identity: testIdentity("CustomFill"))
    )
    let stroked = DefaultRenderer().render(
      CustomTriangle().stroke(Color.white).frame(width: 12, height: 6),
      context: .init(identity: testIdentity("CustomStroke"))
    )
    let bordered = DefaultRenderer().render(
      CustomTriangle().strokeBorder(Color.white).frame(width: 12, height: 6),
      context: .init(identity: testIdentity("CustomStrokeBorder"))
    )
    let inheritedFg = DefaultRenderer().render(
      CustomTriangle().fill().foregroundStyle(Color.red).frame(width: 12, height: 6),
      context: .init(identity: testIdentity("CustomInheritedFg"))
    )
    #expect(litCellCount(filled) > 0)
    #expect(litCellCount(stroked) > 0)
    #expect(litCellCount(bordered) > 0)
    #expect(litCellCount(inheritedFg) > 0)
    // The hollow stroke lights fewer cells than the solid fill.
    #expect(litCellCount(filled) > litCellCount(stroked))
  }

  @Test("inherited foregroundStyle fill equals an explicit-color fill")
  func inheritedForegroundMatchesExplicit() {
    let inherited = DefaultRenderer().render(
      CustomTriangle().fill().foregroundStyle(Color.red).frame(width: 12, height: 6),
      context: .init(identity: testIdentity("InheritedRed"))
    )
    let explicit = DefaultRenderer().render(
      CustomTriangle().fill(Color.red).frame(width: 12, height: 6),
      context: .init(identity: testIdentity("ExplicitRed"))
    )
    #expect(inherited.rasterSurface == explicit.rasterSurface)
  }

  @Test("a custom-path strokeBorder masks the background to the path interior")
  func pathBorderMasksBackground() {
    let artifacts = DefaultRenderer().render(
      EmptyView()
        .frame(width: 12, height: 6, alignment: .topLeading)
        .background(Color.blue)
        .overlay { CustomTriangle().strokeBorder(Color.white) },
      context: .init(identity: testIdentity("PathBorderMask"))
    )
    let cells = artifacts.rasterSurface.cells
    // A cell well inside the (inset) triangle keeps the masked background.
    #expect(cells[2][6].style?.backgroundColor != nil)
    // The bottom-left corner is outside the triangle → background masked away.
    #expect(cells[5][0].style?.backgroundColor == nil)
  }

  @Test("nested inset(by:) accumulates byte-stably for a custom path")
  func insetAccumulates() {
    let nested = DefaultRenderer().render(
      CustomTriangle().inset(by: 1).inset(by: 1).fill(Color.white).frame(width: 16, height: 8),
      context: .init(identity: testIdentity("CustomNestedInset"))
    )
    let summed = DefaultRenderer().render(
      CustomTriangle().inset(by: 2).fill(Color.white).frame(width: 16, height: 8),
      context: .init(identity: testIdentity("CustomSummedInset"))
    )
    #expect(nested.rasterSurface == summed.rasterSurface)
    // Inset shrinks the shape: fewer lit cells than the un-inset fill.
    let full = DefaultRenderer().render(
      CustomTriangle().fill(Color.white).frame(width: 16, height: 8),
      context: .init(identity: testIdentity("CustomNoInset"))
    )
    #expect(litCellCount(full) > litCellCount(summed))
  }
}
