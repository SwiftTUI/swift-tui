import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Ellipse cell masks at reported pixel metrics")
struct EllipseMetricContainmentTests {
  @Test("Tile fills and clipping use the pixel-corrected ellipse", arguments: 0..<4)
  func tileAndClipMasks(metricIndex: Int) {
    let fixtures: [(Int, Int, [String])] = [
      (
        8, 16,
        [
          "   ######   ", " ########## ", "########### ",
          "########### ", " #########  ", "    ###     ",
        ]
      ),
      (
        9, 16,
        [
          "   ######   ", " ########## ", "############",
          "############", " ########## ", "    ####    ",
        ]
      ),
      (
        8, 19,
        [
          "  ########  ", " ########## ", "########### ",
          "########### ", " ########## ", "   ######   ",
        ]
      ),
      (
        9, 19,
        [
          "  ########  ", "########### ", "############",
          "############", " ########## ", "  #######   ",
        ]
      ),
    ]
    let (width, height, expected) = fixtures[metricIndex]
    var environment = EnvironmentValues()
    environment.cellPixelMetrics = .init(width: width, height: height, source: .reported)
    let tiled = DefaultRenderer().render(
      Ellipse().fill(TileStyle(.init(rows: ["#"]), foreground: Color.white))
        .frame(width: 12, height: 6), context: .init(environmentValues: environment))
    let clipped = DefaultRenderer().render(
      Text(Array(repeating: "############", count: 6).joined(separator: "\n"))
        .clipShape(Ellipse()), context: .init(environmentValues: environment))
    let solid = DefaultRenderer().render(
      Ellipse().fill(Color.white).frame(width: 12, height: 6),
      context: .init(environmentValues: environment))

    #expect(tiled.rasterSurface.cells.map { String($0.map(\.character)) } == expected)
    #expect(clipped.rasterSurface.cells.map { String($0.map(\.character)) } == expected)
    // A cell-center mask is intentionally stricter than any-dot Braille
    // coverage, but every retained cell must lie within the solid silhouette.
    for (y, row) in expected.enumerated() {
      for (x, character) in row.enumerated() where character == "#" {
        let scalar = solid.rasterSurface.cells[y][x].character.unicodeScalars.first?.value ?? 0
        #expect(scalar > 0x2800 && scalar <= 0x28FF)
      }
    }
  }
}
