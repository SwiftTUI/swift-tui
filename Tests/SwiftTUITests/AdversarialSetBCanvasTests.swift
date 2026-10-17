// Adversarial set B, pass 3: canvas, path rasterization, clipping and mesh
// gradients (261–270).
//
// The register ratifies that a fill, a clip mask and a hit test agree on a
// path's region, that canvas operations quantize only at the selected grid
// boundary, and that a Canvas applies opacity after its drawing resolves
// colors, direct cell writes included. These probes put the three path routes
// side by side on one cell, draw at the exact edge of a quantized circle,
// write a wide glyph and an uncoloured glyph through the direct-cell route,
// sample a wide ellipse stroke, compare smooth and flat mesh sampling, paint a
// gradient foreground, and hand the canvas negative extents.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: canvas and paths")
struct AdversarialSetBCanvasTests {
  private func cells<V: View>(_ view: V, _ name: String, width: Int, height: Int)
    -> [[RasterCell]]
  {
    DefaultRenderer().render(
      view.frame(width: width, height: height, alignment: .topLeading),
      context: .init(identity: testIdentity("SetBCanvas", name)),
      proposal: .init(width: width, height: height)
    ).rasterSurface.cells
  }

  private func mask(_ cell: RasterCell) -> Int {
    guard let scalar = cell.character.unicodeScalars.first?.value,
      (0x2800...0x28FF).contains(scalar)
    else { return 0 }
    return Int(scalar - 0x2800)
  }

  // A custom path that covers the right half of a cell is treated the same by
  // the fill, the clip mask and the hit test: all three claim the cell or
  // none does.
  @Test func setB261CustomPathFillAndClipAgreeOnAHalfCoveredCell() {
    let right = cells(SetBRightHalf().fill(Color.red), "rightFill", width: 1, height: 1)
    let rightClip = cells(Text("x").clipShape(SetBRightHalf()), "rightClip", width: 1, height: 1)
    let fillPaints = mask(right[0][0]) != 0
    let clipKeeps = rightClip[0][0].character == "x"
    withKnownIssue(
      "the fill lights the half-cell's subpixels while the clip samples one point in the empty half"
    ) {
      #expect(fillPaints == clipKeeps, "fill paints \(fillPaints), clip keeps \(clipKeeps)")
    }
    let left = cells(SetBLeftHalf().fill(Color.red), "leftFill", width: 1, height: 1)
    let leftClip = cells(Text("x").clipShape(SetBLeftHalf()), "leftClip", width: 1, height: 1)
    #expect(mask(left[0][0]) != 0, "\(left[0][0])")
    #expect(leftClip[0][0].character == "x", "\(leftClip[0][0])")
  }

  // A filled circle wholly inside the first cell never lights a sample in the
  // next cell.
  @Test func setB262FilledCircleStaysInsideItsExtent() {
    let grid = cells(
      Canvas { context in context.fillCircle(center: Point(x: 0.5, y: 0.5), radius: 0.25) },
      "circle", width: 2, height: 1)
    #expect(mask(grid[0][0]) != 0, "\(grid[0])")
    withKnownIssue(
      "the rounded radius spans one sample past the disc, into the neighbouring cell (adjacent to STUI-992)"
    ) {
      #expect(mask(grid[0][1]) == 0, "cell 1 mask \(mask(grid[0][1]))")
    }
    let spanning = cells(
      Canvas { context in context.fillRect(Rect(origin: .zero, size: Size(width: 0.5, height: 1)))
      },
      "halfRect", width: 2, height: 1)
    #expect(mask(spanning[0][1]) == 0, "\(spanning[0])")
  }

  // A wide glyph written through `setCell` owns two cells like every other
  // text route: a span of two with a continuation cell.
  @Test func setB263DirectCellWideGlyphOwnsItsContinuation() {
    let canvas = cells(
      Canvas { context in
        context.setCell(at: .zero, character: "界", foreground: nil, background: nil)
      }, "wide", width: 2, height: 1)
    let text = cells(Text("界"), "wideText", width: 2, height: 1)
    #expect(text[0][0].spanWidth == 2 && text[0][1].continuationLeadX == 0, "\(text[0])")
    withKnownIssue("setCell writes with width 1, so the wide glyph has no continuation") {
      #expect(canvas[0][0].spanWidth == 2, "\(canvas[0][0])")
      #expect(canvas[0][1].continuationLeadX == 0, "\(canvas[0][1])")
    }
  }

  // Ancestor opacity reaches a direct cell write that names no colours, the
  // same way it reaches a Braille sample.
  @Test func setB264AncestorOpacityReachesUncolouredDirectCells() throws {
    let sample = cells(
      Canvas { context in context.setPixel(at: .zero) }.opacity(0.5), "sample", width: 1, height: 1)
    let sampleAlpha = try #require(sample[0][0].style?.foregroundColor?.alpha, "\(sample[0][0])")
    #expect(abs(sampleAlpha - 0.5) < 1e-9, "\(sampleAlpha)")
    let direct = cells(
      Canvas { context in
        context.setCell(at: .zero, character: "x", foreground: nil, background: nil)
      }.opacity(0.5), "direct", width: 1, height: 1)
    #expect(direct[0][0].character == "x", "\(direct[0][0])")
    withKnownIssue(
      "a direct cell without colours is written with a nil style and ignores the opacity factor"
    ) {
      let alpha = direct[0][0].style?.foregroundColor?.alpha
      #expect(
        alpha != nil && abs((alpha ?? 1) - 0.5) < 1e-9, "\(String(describing: direct[0][0].style))")
    }
  }

  // A stroked ellipse is continuous: adjacent samples are at most one pixel
  // apart, so a wide, short ellipse has no gaps along its top and bottom.
  @Test func setB265WideEllipseStrokeHasNoGaps() {
    var canvas = BrailleCanvas(width: 40, height: 2)
    canvas.strokeEllipse(centerX: 39, centerY: 3, radiusX: 39, radiusY: 3)
    let row = 6
    let missing = (30...48).filter { x in
      !canvas.cell(x: x / 2, y: row / 4).contains(x: x % 2, y: row % 4)
    }
    withKnownIssue(
      "strokeEllipse point-samples 4(rx+ry) angles without joining neighbours (adjacent to STUI-992)"
    ) {
      #expect(missing.isEmpty, "unlit subpixels on row \(row): \(missing)")
    }
    let view = cells(Ellipse().stroke(Color.red), "ellipse", width: 40, height: 2)
    let litColumns = (0..<40).filter {
      mask(view[1][$0]) & 0x20 != 0 || mask(view[1][$0]) & 0x04 != 0
    }
    #expect(litColumns.count > 10, "\(litColumns)")
  }

  // `smoothsColors` selects a different interpolation: a smoothed 2×2 mesh
  // does not sample identically to the bilinear one.
  @Test func setB266SmoothedMeshSamplesDifferFromBilinear() {
    func sample(smooth: Bool) -> Color {
      PreparedMeshGradient(
        input: .init(
          width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
          colors: [.black, Color(hexRGB: 0xFF0000), Color(hexRGB: 0x00FF00), .white],
          background: .clear, smoothsColors: smooth, colorSpace: .device),
        bounds: .init(origin: .zero, size: .init(width: 8, height: 4))
      ).color(atCellX: 1, y: 0)
    }
    let smooth = sample(smooth: true)
    let flat = sample(smooth: false)
    let distance =
      abs(smooth.red - flat.red) + abs(smooth.green - flat.green) + abs(smooth.blue - flat.blue)
    withKnownIssue(
      "edge derivatives are one-sided full differences, so a 2×2 Hermite patch is exactly bilinear"
    ) {
      #expect(distance > 1e-3, "smooth \(smooth) flat \(flat)")
    }
    #expect(smooth.red.isFinite && flat.red.isFinite)
  }

  // A gradient foreground style on a Canvas resolves across the canvas, not
  // to one colour sampled at its origin.
  @Test func setB267GradientForegroundOnACanvasVariesAcrossIt() throws {
    let gradient = LinearGradient(
      colors: [Color(hexRGB: 0xFF0000), Color(hexRGB: 0x0000FF)],
      startPoint: UnitPoint(x: 0, y: 0.5), endPoint: UnitPoint(x: 1, y: 0.5))
    let row = cells(
      Canvas(grid: .fullCell) { context in
        context.fillRect(Rect(origin: .zero, size: Size(width: 4, height: 1)))
      }
      .foregroundStyle(gradient), "gradient", width: 4, height: 1)
    let first = try #require(row[0][0].style?.foregroundColor, "\(row[0][0])")
    let last = try #require(row[0][3].style?.foregroundColor, "\(row[0][3])")
    withKnownIssue("the canvas foreground is resolved once at the bounds origin") {
      #expect(first != last, "both cells are \(first)")
      #expect(last.blue > first.blue, "first \(first) last \(last)")
    }
    let rectangle = cells(Rectangle().fill(gradient), "rectangle", width: 4, height: 1)
    #expect(rectangle[0][0].style?.backgroundColor != rectangle[0][3].style?.backgroundColor)
  }

  // Negative extents are standardized like CoreGraphics rects, not dropped.
  @Test func setB268NegativeExtentsAreStandardized() {
    let rect = cells(
      Canvas { context in
        context.fillRect(Rect(origin: Point(x: 1, y: 0), size: Size(width: -1, height: 1)))
      }, "negativeRect", width: 2, height: 1)
    let circle = cells(
      Canvas { context in context.fillCircle(center: Point(x: 0.5, y: 0.5), radius: -0.5) },
      "negativeRadius", width: 1, height: 1)
    withKnownIssue("a negative width is rejected and a negative radius becomes a single centre dot")
    {
      #expect(mask(rect[0][0]) == 0xFF, "cell 0 mask \(mask(rect[0][0]))")
      #expect(mask(circle[0][0]).nonzeroBitCount >= 4, "mask \(mask(circle[0][0]))")
    }
    let positive = cells(
      Canvas { context in
        context.fillRect(Rect(origin: .zero, size: Size(width: 1, height: 1)))
      }, "positiveRect", width: 2, height: 1)
    #expect(mask(positive[0][0]) == 0xFF && mask(positive[0][1]) == 0, "\(positive[0])")
  }

  // An even-odd donut keeps its hole on every route: solid fill, clip mask
  // and `Path.contains` agree, and the non-zero rule fills it everywhere.
  @Test func setB269EvenOddHoleAgreesAcrossFillClipAndContains() {
    for rule in [FillRule.evenOdd, .nonZero] {
      let donut = SetBDonut(rule: rule)
      let fill = cells(donut.fill(Color.red), "donut-\(rule)", width: 6, height: 3)
      let clip = cells(
        Text("xxxxxx\nxxxxxx\nxxxxxx").clipShape(donut), "donutClip-\(rule)", width: 6, height: 3)
      let holeFilled = mask(fill[1][2]) != 0
      let holeKept = clip[1][2].character == "x"
      let contained = donut.unitPath.contains(Point(x: 0.375, y: 0.458), fillRule: rule)
      let expectation = rule == .nonZero
      #expect(holeFilled == expectation, "\(rule): fill \(fill[1])")
      #expect(holeKept == expectation, "\(rule): clip \(clip[1])")
      #expect(contained == expectation, "\(rule): contains")
      // The ring itself is always painted and kept.
      #expect(mask(fill[0][0]) != 0, "\(rule): \(fill[0])")
      #expect(clip[0][0].character == "x", "\(rule): \(clip[0])")
    }
  }

  // Points quantize at the selected grid boundary: the same half-cell point
  // lands in the lower-right sample of every grid, a rect that ends exactly on
  // a boundary stays inside it, and a line to the boundary touches the next
  // cell.
  @Test func setB270PointsQuantizeAtTheSelectedGridBoundary() {
    let expectations: [(grid: CanvasGrid, glyph: Character)] = [
      (.braille2x4, "\u{2820}"), (.quadrant2x2, "▗"), (.verticalHalfBlock, "▄"),
      (.horizontalHalfBlock, "▐"), (.fullCell, "█"),
    ]
    for entry in expectations {
      let grid = cells(
        Canvas(grid: entry.grid) { context in context.setPixel(at: Point(x: 0.5, y: 0.5)) },
        "grid-\(entry.glyph)", width: 1, height: 1)
      #expect(grid[0][0].character == entry.glyph, "\(entry.grid): \(grid[0][0].character)")
    }
    let rect = cells(
      Canvas { context in
        context.fillRect(Rect(origin: .zero, size: Size(width: 1, height: 0.25)))
      }, "boundaryRect", width: 2, height: 1)
    #expect(mask(rect[0][0]) == 0x09, "\(mask(rect[0][0]))")
    #expect(mask(rect[0][1]) == 0, "\(mask(rect[0][1]))")
    let line = cells(
      Canvas { context in context.line(from: .zero, to: Point(x: 1, y: 0)) },
      "boundaryLine", width: 2, height: 1)
    #expect(mask(line[0][0]) == 0x09, "\(mask(line[0][0]))")
    #expect(mask(line[0][1]) == 0x01, "\(mask(line[0][1]))")
  }
}

private struct SetBRightHalf: Shape {
  func path(in rect: Rect) -> Path {
    Path(
      Rect(
        origin: Point(x: rect.origin.x + rect.size.width / 2, y: rect.origin.y),
        size: Size(width: rect.size.width / 2, height: rect.size.height)))
  }
}

private struct SetBLeftHalf: Shape {
  func path(in rect: Rect) -> Path {
    Path(
      Rect(
        origin: rect.origin, size: Size(width: rect.size.width / 2, height: rect.size.height)))
  }
}

private struct SetBDonut: Shape {
  let rule: FillRule

  var unitPath: Path {
    var path = Path()
    path.addRect(Rect(origin: .zero, size: Size(width: 1, height: 1)))
    path.addRect(Rect(origin: Point(x: 0.25, y: 0.25), size: Size(width: 0.5, height: 0.5)))
    return path
  }

  var geometry: ShapeGeometry { .path(BoxedPath(unitPath), rule) }
}
