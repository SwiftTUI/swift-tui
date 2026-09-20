import SwiftTUIViews
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// `Shape.trim(from:to:)` and dashes on curved shapes, through the composed
/// renderer. The expected rectangle renders are derived in `StrokeTrackTests`.
@MainActor
@Suite
struct StrokeTrimRenderTests {
  private func cells<V: View>(_ view: V, width: Int, height: Int) -> [[RasterCell]] {
    DefaultRenderer().render(
      view.frame(width: width, height: height, alignment: .topLeading),
      context: .init(identity: testIdentity("StrokeTrimRender")),
      proposal: .init(width: width, height: height)
    ).rasterSurface.cells
  }

  private func lines<V: View>(_ view: V, width: Int, height: Int) -> [String] {
    cells(view, width: width, height: height).map { row in String(row.map(\.character)) }
  }

  /// Braille dots lit in a render.
  private func dots(_ rows: [[RasterCell]]) -> Int {
    rows.joined().reduce(0) { total, cell in
      guard let scalar = cell.character.unicodeScalars.first?.value,
        (0x2800...0x28FF).contains(scalar)
      else {
        return total
      }
      return total + Int(scalar - 0x2800).nonzeroBitCount
    }
  }

  @Test("a quarter trim of a rectangle strokes its top edge")
  func rectangleFirstQuarter() {
    #expect(
      lines(Rectangle().trim(from: 0, to: 0.25).stroke(style: .single), width: 9, height: 4) == [
        "╶──────╴ ",
        "         ",
        "         ",
        "         ",
      ])
  }

  @Test("the second half of a rectangle is its bottom and leading edges")
  func rectangleSecondHalf() {
    #expect(
      lines(Rectangle().trim(from: 0.5, to: 1).stroke(style: .single), width: 9, height: 4) == [
        "╷        ",
        "│        ",
        "│        ",
        "└───────╴",
      ])
  }

  @Test("a rounded rectangle is trimmed from the middle of its trailing edge")
  func roundedRectangle() {
    #expect(
      lines(
        RoundedRectangle(cornerRadius: 1).trim(from: 0, to: 0.25).stroke(style: .single),
        width: 9, height: 5) == [
          "         ",
          "         ",
          "        │",
          "        │",
          "     ───╯",
        ])
  }

  @Test("a trim of a trimmed shape keeps a share of what the first trim kept")
  func trimsCompose() {
    #expect(
      lines(
        Rectangle().trim(from: 0, to: 0.5).trim(from: 0, to: 0.5).stroke(style: .single),
        width: 9, height: 4)
        == lines(
          Rectangle().trim(from: 0, to: 0.25).stroke(style: .single), width: 9, height: 4))
  }

  @Test("the whole trim leaves a stroke exactly as it was")
  func wholeTrimIsUntouched() {
    #expect(
      lines(Circle().trim(from: 0, to: 1).stroke(), width: 20, height: 10)
        == lines(Circle().stroke(), width: 20, height: 10))
    #expect(
      lines(Rectangle().trim(from: 0, to: 1).stroke(), width: 9, height: 4)
        == lines(Rectangle().stroke(), width: 9, height: 4))
  }

  @Test("a quarter trim of a circle strokes its lower trailing quadrant")
  func circleFirstQuarter() {
    let rows = cells(Circle().trim(from: 0, to: 0.25).stroke(), width: 20, height: 10)
    var lit: [(x: Int, y: Int)] = []
    for (y, row) in rows.enumerated() {
      for (x, cell) in row.enumerated() where cell.character != " " {
        lit.append((x, y))
      }
    }
    #expect(lit.count >= 3)
    // SwiftUI starts a circle at its trailing point and goes down first.
    #expect(lit.allSatisfy { $0.x >= 9 && $0.y >= 4 })
    let whole = dots(cells(Circle().stroke(), width: 20, height: 10))
    let kept = dots(rows)
    #expect(Double(kept) > 0.15 * Double(whole) && Double(kept) < 0.35 * Double(whole))
  }

  @Test("a curved stroke dashes", arguments: [0, 1, 2])
  func curvedDash(shape: Int) {
    let style = StrokeStyle(dash: [2, 2])
    let solid: [[RasterCell]]
    let dashed: [[RasterCell]]
    switch shape {
    case 0:
      solid = cells(Circle().stroke(), width: 20, height: 10)
      dashed = cells(Circle().stroke(style: style), width: 20, height: 10)
    case 1:
      solid = cells(Ellipse().stroke(), width: 24, height: 8)
      dashed = cells(Ellipse().stroke(style: style), width: 24, height: 8)
    default:
      solid = cells(Capsule().stroke(), width: 24, height: 6)
      dashed = cells(Capsule().stroke(style: style), width: 24, height: 6)
    }
    // Audit render D: the stroke style did not reach the Braille path, so every
    // style drew the same dots.
    let whole = dots(solid)
    let kept = dots(dashed)
    #expect(whole > 0)
    #expect(Double(kept) > 0.35 * Double(whole) && Double(kept) < 0.65 * Double(whole))
  }

  @Test("a dash phase moves a curved stroke's pattern")
  func curvedDashPhase() {
    let base = lines(Circle().stroke(style: StrokeStyle(dash: [2, 2])), width: 20, height: 10)
    let shifted = lines(
      Circle().stroke(style: StrokeStyle(dash: [2, 2], dashPhase: 2)), width: 20, height: 10)
    #expect(base != shifted)
  }

  @Test("a trimmed fill closes the trimmed outline and fills it")
  func trimmedFill() {
    // The first half of a rectangle is its top and trailing edges. Closed with a
    // chord, that is the triangle above the diagonal.
    let rows = cells(
      Rectangle().trim(from: 0, to: 0.5).fill(Color.blue), width: 12, height: 6)
    let whole = cells(Rectangle().fill(Color.blue), width: 12, height: 6)
    func painted(_ rows: [[RasterCell]]) -> Int {
      rows.joined().filter {
        $0.character != " " || $0.style?.backgroundColor != nil
      }.count
    }
    #expect(painted(rows) > 0)
    #expect(painted(rows) < painted(whole))
    let topTrailing = rows[0][10]
    let bottomLeading = rows[5][1]
    #expect(topTrailing.character != " " || topTrailing.style?.backgroundColor != nil)
    #expect(bottomLeading.character == " " && bottomLeading.style?.backgroundColor == nil)
  }
}
