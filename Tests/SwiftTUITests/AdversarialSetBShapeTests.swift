// Adversarial set B, pass 2: shapes, strokes and trims (141–150).
//
// The analytic primitives, their `path(in:)` bridge, trim intervals, dash
// patterns and the stroke painter each quantize geometry at a different
// stage. The divergence register fixes the start point and direction of a
// trimmed outline, the dash unit and the rule that a zero-opacity node paints
// nothing; these probes check that the fill route, the path route and the
// stroke route agree with that contract and with each other.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: shapes and strokes")
struct AdversarialSetBShapeTests {
  private func cells<V: View>(_ view: V, _ name: String, width: Int, height: Int)
    -> [[RasterCell]]
  {
    DefaultRenderer().render(
      view.frame(width: width, height: height, alignment: .topLeading),
      context: .init(identity: testIdentity("SetBShapes", name)),
      proposal: .init(width: width, height: height)
    ).rasterSurface.cells
  }

  private func lines(_ cells: [[RasterCell]]) -> [String] {
    cells.map { String($0.map(\.character)) }
  }

  private func dots(_ row: [RasterCell]) -> Int {
    row.reduce(0) { total, cell in
      guard let scalar = cell.character.unicodeScalars.first?.value,
        (0x2800...0x28FF).contains(scalar)
      else { return total }
      return total + Int(scalar - 0x2800).nonzeroBitCount
    }
  }

  private func painted(_ cells: [[RasterCell]]) -> Set<[Int]> {
    var result = Set<[Int]>()
    for (y, row) in cells.enumerated() {
      for (x, cell) in row.enumerated()
      where cell.character != " " || cell.style?.backgroundColor != nil {
        result.insert([x, y])
      }
    }
    return result
  }

  // A trimmed circle starts at the middle of its trailing edge and runs
  // clockwise, for a fill exactly as for a stroke: the first half covers the
  // bottom half of the frame on both routes.
  @Test func setB141TrimmedCircleFillStartsWhereTheStrokeStarts() {
    let fill = cells(
      Circle().trim(from: 0, to: 0.5).fill(Color.red), "setB141-fill", width: 20, height: 10)
    let stroke = cells(
      Circle().trim(from: 0, to: 0.5).stroke(Color.red), "setB141-stroke", width: 20, height: 10)
    let fillRows = fill.indices.filter { dots(fill[$0]) > 0 }
    let strokeRows = stroke.indices.filter { dots(stroke[$0]) > 0 }
    #expect(!fillRows.isEmpty, "\(lines(fill))")
    #expect(!strokeRows.isEmpty, "\(lines(stroke))")
    #expect(strokeRows.allSatisfy { $0 >= 4 }, "stroke rows \(strokeRows)\n\(lines(stroke))")
    withKnownIssue("a trimmed circle fill starts at the leading edge, half a turn from the stroke")
    {
      #expect(fillRows.allSatisfy { $0 >= 4 }, "fill rows \(fillRows)\n\(lines(fill))")
      #expect(!fillRows.contains(0) && !fillRows.contains(1), "\(lines(fill))")
    }
  }

  // `path(in:)` of the rounded primitives starts at the middle of the trailing
  // edge, matching the ratified trim start point used by the stroke route.
  @Test func setB142RoundedPrimitivePathsStartAtTheTrailingEdgeMidpoint() throws {
    let rect = Rect(origin: .zero, size: Size(width: 20, height: 10))
    func start(_ path: Path) -> Point? {
      if case .move(let point)? = path.elements.first { return point }
      return nil
    }
    let circle = try #require(start(Circle().path(in: rect)))
    let ellipse = try #require(start(Ellipse().path(in: rect)))
    let rounded = try #require(start(RoundedRectangle(cornerRadius: 2).path(in: rect)))
    let capsule = try #require(start(Capsule().path(in: rect)))
    withKnownIssue(
      "path(in:) of the rounded primitives starts at the leading edge or the top, not the trailing midpoint"
    ) {
      #expect(circle.x == 15 && circle.y == 5, "\(circle)")
      #expect(ellipse.x == 20 && ellipse.y == 5, "\(ellipse)")
      #expect(rounded.x == 20 && rounded.y == 5, "\(rounded)")
      #expect(capsule.x == 20 && capsule.y == 5, "\(capsule)")
    }
    // A rectangle starts at its top-leading corner.
    let rectangle = try #require(start(Rectangle().path(in: rect)))
    #expect(rectangle.x == 0 && rectangle.y == 0, "\(rectangle)")
  }

  // Trimming a fill stretches the outline to its frame but keeps its shape: a
  // nearly whole trimmed rounded rectangle paints the same cells as the
  // untrimmed one, give or take the sub-cell gap at the trim start.
  @Test func setB143TrimmedRoundedRectangleFillKeepsItsCorners() {
    let plain = painted(
      cells(
        RoundedRectangle(cornerRadius: 1).fill(Color.red), "setB143-plain", width: 12, height: 6))
    let trimmed = painted(
      cells(
        RoundedRectangle(cornerRadius: 1).trim(from: 0, to: 0.999).fill(Color.red),
        "setB143-trimmed", width: 12, height: 6))
    let missing = plain.subtracting(trimmed)
    #expect(trimmed.contains([0, 1]) && trimmed.contains([0, 4]))
    withKnownIssue(
      "a trimmed rounded rectangle fill is the unit path scaled, so its corners round like an ellipse"
    ) {
      #expect(
        missing.count <= 2,
        "cells lost by trimming: \(missing.sorted { $0.lexicographicallyPrecedes($1) })")
      #expect(
        trimmed.contains([1, 0]) && trimmed.contains([2, 0]),
        "\(trimmed.sorted { $0.lexicographicallyPrecedes($1) })")
    }

    let capsulePlain = painted(
      cells(Capsule().fill(Color.red), "setB143-capsule", width: 12, height: 6))
    let capsuleTrimmed = painted(
      cells(
        Capsule().trim(from: 0, to: 0.999).fill(Color.red), "setB143-capsule-trimmed", width: 12,
        height: 6))
    #expect(capsulePlain.subtracting(capsuleTrimmed).count <= 2)
  }

  // Trim fractions clamp to 0...1 and a non-finite fraction reads as the
  // nearer end, so `to: -∞` is an empty interval and `from: +∞` likewise. The
  // stroke and the fill of one trimmed shape agree on whether anything paints.
  @Test func setB144NonFiniteTrimBoundsAreEmptyIntervalsOnEveryRoute() {
    let toMinusInfinity = lines(
      cells(
        Rectangle().trim(from: 0, to: -.infinity).stroke(Color.red), "setB144-a", width: 9,
        height: 4))
    let fromInfinity = lines(
      cells(
        Rectangle().trim(from: .infinity, to: 1).stroke(Color.red), "setB144-b", width: 9, height: 4
      ))
    let nanStroke = painted(
      cells(
        Rectangle().trim(from: .nan, to: 0.5).stroke(Color.red), "setB144-c", width: 9, height: 4))
    let nanFill = painted(
      cells(Rectangle().trim(from: .nan, to: 0.5).fill(Color.red), "setB144-d", width: 9, height: 4)
    )
    do {
      #expect(
        toMinusInfinity.allSatisfy { $0.trimmingCharacters(in: " ").isEmpty }, "\(toMinusInfinity)")
      #expect(fromInfinity.allSatisfy { $0.trimmingCharacters(in: " ").isEmpty }, "\(fromInfinity)")
      #expect(
        nanStroke.isEmpty == nanFill.isEmpty, "stroke \(nanStroke.count) fill \(nanFill.count)")
    }

    // Finite out-of-range fractions clamp: (−1, 2) is the whole outline.
    let whole = lines(cells(Rectangle().stroke(Color.red), "setB144-e", width: 9, height: 4))
    let clamped = lines(
      cells(Rectangle().trim(from: -1, to: 2).stroke(Color.red), "setB144-f", width: 9, height: 4))
    #expect(clamped == whole, "\(clamped)")
  }

  // Mixing clamps its fraction; a NaN fraction must yield an endpoint instead
  // of reaching the color-space preconditions.
  @Test func setB145NaNMixingFractionsDoNotTrap() async {
    await withKnownIssue(
      "a NaN fraction survives the clamp and trips the color-space preconditions"
    ) {
      await #expect(processExitsWith: .success) {
        let interpolated = Color.red.interpolated(to: .blue, progress: .nan)
        #expect(interpolated.red.isFinite && interpolated.alpha.isFinite, "\(interpolated)")
      }
      await #expect(processExitsWith: .success) {
        let mixed = Color.red.mixed(with: .blue, amount: .nan)
        #expect(mixed.red.isFinite, "\(mixed)")
      }
      await #expect(processExitsWith: .success) {
        let lightened = Color.red.lightened(by: .nan)
        #expect(lightened.red.isFinite, "\(lightened)")
      }
    }
    // Finite fractions outside 0...1 clamp to the endpoints (within the
    // perceptual round trip's precision).
    let below = Color.red.interpolated(to: .blue, progress: -3)
    let above = Color.red.interpolated(to: .blue, progress: 7)
    #expect(below.isApproximately(.red), "\(below)")
    #expect(above.isApproximately(.blue), "\(above)")
  }

  // An exact 6×6×6 cube color maps to its own index: xterm's cube levels are
  // 0, 95, 135, 175, 215 and 255, not six equal steps.
  @Test func setB146ANSI256CubeLevelsMapToTheirOwnIndices() {
    let renderer = TerminalCellTextRenderer(capabilityProfile: .ansi256)
    let expectations: [(hex: UInt32, code: Int)] = [
      (0x000000, 16), (0x5F5F5F, 59), (0x878787, 102), (0xAFAFAF, 145), (0xD7D7D7, 188),
      (0xFFFFFF, 231), (0x5F0000, 52), (0x0000FF, 21), (0xFF5F00, 202),
    ]
    let misplaced: Set<UInt32> = [0x5F5F5F, 0x878787, 0xFFFFFF, 0x5F0000, 0xFF5F00]
    for entry in expectations {
      let code = renderer.ansi256Code(for: Color(hexRGB: entry.hex))
      withKnownIssue(
        "the cube index is rounded on six equal steps, so xterm's 0x5F and 0x87 levels land one index high"
      ) {
        #expect(code == entry.code, "\(String(entry.hex, radix: 16)) → \(code)")
      } when: {
        misplaced.contains(entry.hex)
      }
    }
  }

  // Pure white is cube index 231; the light gray ramp ends at 255 (#EEEEEE),
  // so a color brighter than #EEEEEE must not render darker than #FEFEFE.
  @Test func setB147WhiteQuantizesToTheCubeWhiteNotTheGrayRamp() {
    let renderer = TerminalCellTextRenderer(capabilityProfile: .ansi256)
    let nearWhite = renderer.ansi256Code(for: Color(hexRGB: 0xFFFFFE))
    #expect(nearWhite == 231, "\(nearWhite)")
    let white = renderer.ansi256Code(for: Color.white)
    let translucentWhite = renderer.ansi256Code(for: Color.white.opacity(0.5))
    withKnownIssue(
      "Color.white is hand-mapped to gray-ramp index 255 (#EEEEEE); any other white reaches 231"
    ) {
      #expect(white == 231, "\(white)")
      #expect(translucentWhite == white, "\(translucentWhite) vs \(white)")
    }
    let black = renderer.ansi256Code(for: Color.black)
    #expect(black == 16, "\(black)")
    let nearBlack = renderer.ansi256Code(for: Color(hexRGB: 0x010101))
    #expect(nearBlack == 16 || nearBlack == 232, "\(nearBlack)")
  }

  // A stroke whose style resolves to nothing paints nothing, like a fill of
  // the same style, and a clear stroke leaves the cells beneath it intact.
  @Test func setB148InvisibleStrokesPaintNoGlyphs() {
    let blank = ["    ", "    "]
    let invisible = lines(
      cells(
        Rectangle().stroke(SemanticShapeStyle.foreground.opacity(0), style: .single), "setB148-a",
        width: 4, height: 2))
    let invisibleFill = lines(
      cells(
        Rectangle().fill(SemanticShapeStyle.foreground.opacity(0)), "setB148-b", width: 4, height: 2
      ))
    #expect(invisibleFill == blank, "\(invisibleFill)")
    let clearOverText = lines(
      cells(
        ZStack {
          Text("abcd\nefgh")
          Rectangle().stroke(Color.clear, style: .single)
        }, "setB148-c", width: 4, height: 2))
    let circle = cells(
      Circle().stroke(SemanticShapeStyle.foreground.opacity(0)), "setB148-d", width: 8, height: 4)
    withKnownIssue(
      "the stroke painter has no transparent-style guard: invisible strokes still write glyphs"
    ) {
      #expect(invisible == blank, "\(invisible)")
      #expect(clearOverText == ["abcd", "efgh"], "\(clearOverText)")
      #expect(circle.allSatisfy { dots($0) == 0 }, "\(lines(circle))")
    }
  }

  // `inset(by:)` with a negative amount grows the shape past its frame, as in
  // SwiftUI; it is not silently clamped to zero.
  @Test func setB149NegativeInsetGrowsTheShape() {
    let grown = painted(
      cells(
        Rectangle().inset(by: -1).fill(Color.red).frame(width: 4, height: 2),
        "setB149-grown", width: 6, height: 4))
    let plain = painted(
      cells(
        Rectangle().fill(Color.red).frame(width: 4, height: 2),
        "setB149-plain", width: 6, height: 4))
    #expect(plain.count == 8, "\(plain.sorted { $0.lexicographicallyPrecedes($1) })")
    #expect(grown.isSuperset(of: plain))
    withKnownIssue("a negative inset is clamped to zero instead of growing the shape") {
      #expect(grown.count > plain.count, "grown \(grown.count) plain \(plain.count)")
    }

    let shrunk = painted(
      cells(Rectangle().inset(by: 1).fill(Color.red), "setB149-shrunk", width: 6, height: 4))
    #expect(shrunk.count == 8, "\(shrunk.sorted { $0.lexicographicallyPrecedes($1) })")
  }

  // Degenerate dash patterns never trap and resolve by the documented rules:
  // an all-zero, negative or non-finite pattern is solid, an odd pattern is
  // doubled, and a phase wraps around the pattern length.
  @Test func setB150DegenerateDashPatternsResolveWithoutTrapping() {
    #expect(StrokeDashPattern(dash: [], phase: 0) == nil)
    #expect(StrokeDashPattern(dash: [0], phase: 0) == nil)
    #expect(StrokeDashPattern(dash: [0, 0], phase: 0) == nil)
    #expect(StrokeDashPattern(dash: [-1, 2], phase: 0) == nil)
    #expect(StrokeDashPattern(dash: [.nan], phase: 0) == nil)
    #expect(StrokeDashPattern(dash: [.infinity, 1], phase: 0) == nil)
    let solid = lines(
      cells(Rectangle().stroke(Color.red, style: .single), "setB150-solid", width: 9, height: 4))
    for (name, dash) in [
      ("zero", [0.0]), ("zeros", [0.0, 0.0]), ("negative", [-1.0, 2.0]), ("nan", [Double.nan]),
    ] {
      let dashed = lines(
        cells(
          Rectangle().stroke(Color.red, style: StrokeStyle(dash: dash)), "setB150-\(name)",
          width: 9, height: 4))
      #expect(dashed == solid, "\(name): \(dashed)")
    }

    let phased = StrokeDashPattern(dash: [2, 1], phase: -3)
    let unphased = StrokeDashPattern(dash: [2, 1], phase: 0)
    #expect(phased != nil && unphased != nil)
    for position in stride(from: 0.0, through: 6.0, by: 0.5) {
      #expect(phased?.isOn(at: position) == unphased?.isOn(at: position), "position \(position)")
    }
    let hugePhase = lines(
      cells(
        Rectangle().stroke(Color.red, style: StrokeStyle(dash: [2, 1], dashPhase: 3e9)),
        "setB150-huge", width: 9, height: 4))
    let zeroPhase = lines(
      cells(
        Rectangle().stroke(Color.red, style: StrokeStyle(dash: [2, 1])), "setB150-zero", width: 9,
        height: 4))
    #expect(hugePhase == zeroPhase, "\(hugePhase)")
    let nanPhase = lines(
      cells(
        Rectangle().stroke(Color.red, style: StrokeStyle(dash: [2, 1], dashPhase: .nan)),
        "setB150-nanphase", width: 9, height: 4))
    #expect(nanPhase == zeroPhase, "\(nanPhase)")
  }
}

extension Color {
  fileprivate func isApproximately(_ other: Color, tolerance: Double = 1e-6) -> Bool {
    abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
      && abs(blue - other.blue) <= tolerance && abs(alpha - other.alpha) <= tolerance
  }
}

extension String {
  fileprivate func trimmingCharacters(in character: Character) -> String {
    var text = self
    while text.last == character { text.removeLast() }
    while text.first == character { text.removeFirst() }
    return text
  }
}
