import SwiftTUIViews
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Line strokes that share a cell, through the composed renderer. The merge
/// rules have their own tests in `LineArmsTableTests`; these check that
/// borders, shape strokes and dividers all reach the same table.
@MainActor
@Suite
struct StrokeMergeRenderTests {
  private func cells<V: View>(_ view: V, width: Int, height: Int) -> [[RasterCell]] {
    DefaultRenderer().render(
      view.frame(width: width, height: height, alignment: .topLeading),
      context: .init(identity: testIdentity("StrokeMergeRender")),
      proposal: .init(width: width, height: height)
    ).rasterSurface.cells
  }

  private func lines<V: View>(_ view: V, width: Int, height: Int) -> [String] {
    cells(view, width: width, height: height).map { row in String(row.map(\.character)) }
  }

  @Test("a lone divider is drawn to both of its ends")
  func loneDivider() {
    #expect(
      lines(VStack(spacing: 0) { Divider() }, width: 5, height: 1) == ["─────"])
  }

  @Test("a divider under an inset border joins it")
  func dividerUnderABorder() {
    let box = VStack(alignment: .leading, spacing: 0) {
      Text(" title")
      Divider()
      Text(" body")
    }
    .padding(.vertical, 1)
    .border(.foreground)
    #expect(
      lines(box, width: 9, height: 5) == [
        "┌───────┐",
        "│title  │",
        "├───────┤",
        "│body   │",
        "└───────┘",
      ])
  }

  @Test("a divider joins a shape stroke as it joins a border")
  func dividerUnderAStroke() {
    let box = ZStack {
      Rectangle().stroke(style: .single)
      VStack(spacing: 0) { Divider() }
    }
    #expect(
      lines(box, width: 5, height: 3) == [
        "┌───┐",
        "├───┤",
        "└───┘",
      ])
  }

  @Test("a divider keeps the rounded corners of the border it joins")
  func roundedBorderKeepsItsCorners() {
    let box = ZStack {
      Rectangle().stroke(style: .rounded)
      VStack(spacing: 0) { Divider() }
    }
    #expect(
      lines(box, width: 5, height: 3) == [
        "╭───╮",
        "├───┤",
        "╰───╯",
      ])
  }

  @Test("a horizontal and a vertical divider cross")
  func crossingDividers() {
    let cross = ZStack {
      VStack(spacing: 0) { Divider() }
      HStack(spacing: 0) { Divider() }
    }
    #expect(
      lines(cross, width: 5, height: 3) == [
        "  │  ",
        "──┼──",
        "  │  ",
      ])
  }

  @Test("borders on single sides meet in a corner, in the color of the one on top")
  func stackedSides() {
    let view = Text(" ")
      .frame(width: 5, height: 3)
      .border(Color.red, sides: .top)
      .border(Color.blue, sides: .leading)
    let cells = cells(view, width: 5, height: 3)
    #expect(
      cells.map { row in String(row.map(\.character)) } == [
        "┌────",
        "│    ",
        "│    ",
      ])
    #expect(hue(cells[0][0]) == .blue)
    #expect(hue(cells[0][1]) == .red)
    #expect(hue(cells[1][0]) == .blue)
  }

  @Test("borders in neighboring cells do not join")
  func neighborsDoNotJoin() {
    let pair = HStack(spacing: 0) {
      Text(" ").frame(width: 3, height: 3).border(.foreground)
      Text(" ").frame(width: 3, height: 3).border(.foreground)
    }
    #expect(
      lines(pair, width: 6, height: 3) == [
        "┌─┐┌─┐",
        "│ ││ │",
        "└─┘└─┘",
      ])
  }

  @Test("text drawn in box-drawing characters does not join a border")
  func textDoesNotJoin() {
    #expect(
      lines(Text("─────").frame(width: 5, height: 3).border(.foreground), width: 5, height: 3)
        == [
          "┌───┐",
          "│───│",
          "└───┘",
        ])
  }

  @Test("a block border does not join")
  func blockBorder() {
    let box = VStack(spacing: 0) { Divider() }
      .padding(.vertical, 1)
      .border(.foreground, style: .innerHalfBlock)
    #expect(lines(box, width: 5, height: 3)[1] == "▐───▌")
  }

  @Test("a double border takes a light divider as a mixed junction")
  func doubleBorder() {
    let box = VStack(spacing: 0) { Divider() }
      .padding(.vertical, 1)
      .border(.foreground, style: .double)
    #expect(
      lines(box, width: 5, height: 3) == [
        "╔═══╗",
        "╟───╢",
        "╚═══╝",
      ])
  }

  @Test("the deprecated per-side border still draws, for the deprecation window")
  @available(*, deprecated)
  func deprecatedEdgeStyledBorder() {
    let cells = cells(
      Text(" ").frame(width: 5, height: 3)
        .border(BorderEdgeStyle(topBottom: Color.red, leftRight: Color.blue)),
      width: 5, height: 3)
    #expect(
      cells.map { row in String(row.map(\.character)) } == [
        "┌───┐",
        "│   │",
        "└───┘",
      ])
    #expect(hue(cells[0][2]) == .red)
    #expect(hue(cells[1][0]) == .blue)
  }

  private enum Hue: Equatable {
    case red
    case blue
    case other
  }

  /// The renderer maps named colors through the terminal theme, so a cell is
  /// compared by hue and not against `Color.red` itself.
  private func hue(_ cell: RasterCell) -> Hue {
    guard let color = cell.style?.foregroundColor else {
      return .other
    }
    if color.red > color.blue + 0.2 {
      return .red
    }
    return color.blue > color.red + 0.2 ? .blue : .other
  }
}
