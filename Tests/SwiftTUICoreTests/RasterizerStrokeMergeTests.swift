import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

// Line strokes that share a cell merge into the glyph that shows both. The
// merge rules have their own tests in `LineArmsTableTests`; these check that
// the rasterizer feeds every line painter through one table, in a fresh raster
// and in an incremental one.

@Suite
struct RasterizerStrokeMergeTests {
  private let size = CellSize(width: 8, height: 5)

  @Test("a rule that ends under a ring joins it")
  func ruleJoinsARing() {
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5)),
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
        ]),
      minimumSize: size)
    #expect(
      surface.lines == [
        "┌──────┐",
        "│      │",
        "├──────┤",
        "│      │",
        "└──────┘",
      ])
  }

  @Test("the merge does not depend on which stroke is drawn first")
  func drawOrder() {
    let ringFirst = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5)),
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
        ]),
      minimumSize: size)
    let ruleFirst = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5)),
        ]),
      minimumSize: size)
    #expect(ringFirst.lines == ruleFirst.lines)
  }

  @Test("the junction takes the color of the stroke on top")
  func junctionColor() {
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5), color: .red),
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1), color: .blue),
        ]),
      minimumSize: size)
    #expect(surface.cells[2][0].character == "├")
    #expect(surface.cells[2][0].style?.foregroundColor == Color.blue)
    #expect(surface.cells[1][0].style?.foregroundColor == Color.red)
  }

  @Test("two rings that cross draw a crossing, and their corners stay corners")
  func crossingRings() {
    let size = CellSize(width: 6, height: 4)
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "a", bounds: mergeRect(0, 0, 4, 3)),
          mergeRing(id: "b", bounds: mergeRect(2, 1, 4, 3)),
        ]),
      minimumSize: size)
    #expect(
      surface.lines == [
        "┌──┐",
        "│ ┌┼─┐",
        "└─┼┘ │",
        "  └──┘",
      ])
  }

  @Test("a heavy ring takes a light rule as a mixed junction")
  func mixedWeights() {
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5), stroke: .heavy),
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
        ]),
      minimumSize: size)
    #expect(surface.lines[2] == "┠──────┨")
  }

  @Test("the ASCII palette merges in its own glyphs")
  func asciiPalette() {
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5), stroke: .ascii),
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1), stroke: .ascii),
        ]),
      minimumSize: size)
    #expect(
      surface.lines == [
        "+------+",
        "|      |",
        "+------+",
        "|      |",
        "+------+",
      ])
  }

  @Test("where alphabets meet, the junction is in the alphabet of the stroke on top")
  func mixedAlphabets() {
    let asciiOnTop = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5), stroke: .ascii),
        ]),
      minimumSize: size)
    #expect(asciiOnTop.lines[2] == "+──────+")
    let boxDrawingOnTop = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5), stroke: .ascii),
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
        ]),
      minimumSize: size)
    #expect(boxDrawingOnTop.lines[2] == "├──────┤")
  }

  @Test("a line that something painted over does not merge")
  func paintedOver() {
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
          // Text covers the rule before the ring arrives. The cells no longer
          // hold what the rule wrote, so its arms are out of date.
          mergeText(id: "text", bounds: mergeRect(0, 2, 8, 1), text: "━━━━━━━━"),
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5)),
        ]),
      minimumSize: size)
    #expect(surface.lines[2] == "│━━━━━━│")
  }

  @Test("text that looks like a line does not merge")
  func textIsNotALine() {
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeText(id: "text", bounds: mergeRect(0, 2, 8, 1), text: "────────"),
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5)),
        ]),
      minimumSize: size)
    #expect(surface.lines[2] == "│──────│")
  }

  @Test("an edge pen does not merge")
  func edgePen() {
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5), stroke: .innerHalfBlock),
        ]),
      minimumSize: size)
    #expect(surface.lines[2] == "▐──────▌")
  }

  @Test("a stroke that is clipped away leaves no arms behind")
  func clippedStroke() {
    // The first rule is clipped to the ring's interior, so it never reaches
    // the ring. If it recorded arms in the ring's cells all the same, the
    // table would no longer match the surface there, and the second rule
    // would find nothing to join.
    var clipped = mergeRule(id: "clipped", bounds: mergeRect(0, 2, 8, 1))
    clipped.clipBounds = mergeRect(1, 2, 6, 1)
    let surface = Rasterizer().rasterize(
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 5)),
          clipped,
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
        ]),
      minimumSize: size)
    #expect(surface.lines[2] == "├──────┤")
  }

  @Test(
    "an incremental raster draws the junctions a fresh raster draws",
    arguments: [
      // The label above the rule changes: the rule's row is dirty and both
      // junctions are repainted from an empty table.
      (changes: "upper", rows: [0, 1, 2]),
      // The label below the ring's last row changes: the rule's row is clean
      // and keeps the junctions the previous frame drew.
      (changes: "lower", rows: [3, 4, 5]),
    ])
  func incrementalMatchesFresh(changes: String, rows: [Int]) {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let size = CellSize(width: 8, height: 6)
    func tree(upper: String, lower: String) -> DrawNode {
      mergeRoot(
        size: size,
        children: [
          mergeRing(id: "ring", bounds: mergeRect(0, 0, 8, 6)),
          mergeText(id: "upper", bounds: mergeRect(1, 1, 6, 1), text: upper),
          mergeRule(id: "rule", bounds: mergeRect(0, 2, 8, 1)),
          mergeText(id: "lower", bounds: mergeRect(1, 4, 6, 1), text: lower),
        ])
    }
    let previous = tree(upper: "one", lower: "two")
    let current =
      changes == "upper" ? tree(upper: "three", lower: "two") : tree(upper: "one", lower: "four")

    let previousSurface = rasterizer.rasterize(previous, minimumSize: size)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current, minimumSize: size, previousSurface: nil, damage: nil)
    let verified = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: size,
      previousSurface: previousSurface,
      damage: .init(textRows: rows.map { .init(row: $0) }))

    #expect(
      verified.incrementalMismatch == nil,
      "incremental raster diverged: \(verified.incrementalMismatch?.evidence ?? "")")
    #expect(verified.surface == fresh.surface)
    #expect(verified.path == .incremental)
    #expect(verified.surface.lines[2] == "├──────┤")
  }
}

// MARK: - Fixtures

private func mergeRect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CellRect {
  CellRect(origin: .init(x: x, y: y), size: .init(width: width, height: height))
}

private func mergeRoot(size: CellSize, children: [DrawNode]) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeMergeRoot"),
    bounds: .init(origin: .zero, size: size),
    children: children
  )
}

private func mergeRing(
  id: String, bounds: CellRect, stroke: StrokeStyle = .single, color: Color = .white
) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeMerge", id),
    bounds: bounds,
    commands: [
      .stroke(
        bounds: bounds,
        geometry: .rectangle,
        insetAmount: 0,
        style: AnyShapeStyle(color),
        strokeStyle: stroke,
        strokeBorder: true
      )
    ]
  )
}

private func mergeRule(
  id: String, bounds: CellRect, stroke: StrokeStyle = .single, color: Color = .white
) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeMerge", id),
    bounds: bounds,
    commands: [
      .rule(bounds: bounds, style: AnyShapeStyle(color), strokeStyle: stroke, stackAxis: .vertical)
    ]
  )
}

private func mergeText(id: String, bounds: CellRect, text: String) -> DrawNode {
  DrawNode(
    identity: testIdentity("StrokeMerge", id),
    bounds: bounds,
    commands: [
      .text(
        bounds: bounds,
        content: text,
        style: .init(),
        lineLimit: nil,
        truncationMode: .tail,
        wrappingStrategy: .wordBoundary
      )
    ]
  )
}
