import SwiftTUIViews
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Rectangle strokes and rules through the composed renderer. The track, the
/// mask and the pen have their own tests in `StrokeTrackTests`; these check
/// that the rasterizer draws through them.
@MainActor
@Suite
struct StrokeTrackRenderTests {
  private func lines<V: View>(_ view: V, width: Int, height: Int) -> [String] {
    DefaultRenderer().render(
      view.frame(width: width, height: height, alignment: .topLeading),
      context: .init(identity: testIdentity("StrokeTrackRender")),
      proposal: .init(width: width, height: height)
    ).rasterSurface.cells.map { row in String(row.map(\.character)) }
  }

  @Test("a solid rectangle stroke draws the ring it always drew")
  func solidStroke() {
    #expect(
      lines(Rectangle().stroke(style: .single), width: 5, height: 3)
        == ["┌───┐", "│   │", "└───┘"])
    #expect(
      lines(Rectangle().stroke(style: .heavy), width: 5, height: 3)
        == ["┏━━━┓", "┃   ┃", "┗━━━┛"])
    #expect(
      lines(Rectangle().stroke(style: .innerHalfBlock), width: 5, height: 3)
        == ["▗▄▄▄▖", "▐   ▌", "▝▀▀▀▘"])
  }

  @Test("a dashed rectangle stroke draws the render derived in the proposal")
  func dashedStroke() {
    let style = StrokeStyle(borderSet: .single, dash: [2, 1])
    #expect(
      lines(Rectangle().stroke(style: style), width: 9, height: 4) == [
        "┌─ ── ──╷",
        "╵       ╵",
        "│       │",
        "╶─ ── ── ",
      ])
  }

  @Test("stroke and strokeBorder dash the same cells")
  func strokeBorderMatchesStroke() {
    let style = StrokeStyle(borderSet: .single, dash: [2, 1])
    #expect(
      lines(Rectangle().strokeBorder(style: style), width: 9, height: 4)
        == lines(Rectangle().stroke(style: style), width: 9, height: 4))
  }

  @Test("the dash phase moves the pattern")
  func dashPhase() {
    let base = lines(
      Rectangle().stroke(style: StrokeStyle(borderSet: .single, dash: [2, 1])),
      width: 9, height: 4)
    let shifted = lines(
      Rectangle().stroke(style: StrokeStyle(borderSet: .single, dash: [2, 1], dashPhase: 1)),
      width: 9, height: 4)
    #expect(base != shifted)
    // Every gap on the top edge moves one cell toward the start of the track,
    // and the top-trailing corner, which was half drawn, is now whole.
    #expect(shifted[0] == "┌ ── ── ┐")
  }

  @Test("a rounded rectangle rounds its corners whatever the palette's own corners")
  func roundedGeometry() {
    // Audit render E1: this drew square corners, because the corner came from
    // the palette and the radius was ignored.
    #expect(
      lines(RoundedRectangle(cornerRadius: 3).stroke(style: .single), width: 5, height: 3)
        == ["╭───╮", "│   │", "╰───╯"])
    // Unicode has no heavy arc.
    #expect(
      lines(RoundedRectangle(cornerRadius: 3).stroke(style: .heavy), width: 5, height: 3)
        == ["┏━━━┓", "┃   ┃", "┗━━━┛"])
  }

  @Test("a round join rounds the corners of a rectangle")
  func roundJoin() {
    let style = StrokeStyle(borderSet: .single, lineJoin: .round)
    #expect(
      lines(Rectangle().stroke(style: style), width: 5, height: 3)
        == ["╭───╮", "│   │", "╰───╯"])
  }

  @Test("a rounded rectangle measures its dash from the middle of its trailing edge")
  func roundedRectangleDashOrigin() {
    // One dash, 4 units long. On a 9 x 5 ring at an aspect ratio of 2 it covers
    // the two cells below the middle of the trailing edge.
    let style = StrokeStyle(borderSet: .single, dash: [4, 100])
    let rendered = lines(
      RoundedRectangle(cornerRadius: 1).stroke(style: style), width: 9, height: 5)
    #expect(rendered == ["         ", "         ", "        │", "        │", "         "])
  }

  @Test("a rule dashes like any other stroke")
  func dashedRule() {
    let style = StrokeStyle(borderSet: .single, dash: [1, 1])
    #expect(
      lines(VStack { Divider(strokeStyle: style) }, width: 6, height: 1) == ["─ ─ ─ "])
    #expect(lines(VStack { Divider() }, width: 6, height: 1) == ["──────"])
  }

  @Test("an unpainted dash segment leaves the cell as it was")
  func gapsAreNotPainted() throws {
    let style = StrokeStyle(borderSet: .single, dash: [2, 1])
    let cells = DefaultRenderer().render(
      Rectangle().fill(Color.blue)
        .overlay { Rectangle().stroke(Color.white, style: style) }
        .frame(width: 9, height: 4, alignment: .topLeading),
      context: .init(identity: testIdentity("StrokeTrackRenderGaps")),
      proposal: .init(width: 9, height: 4)
    ).rasterSurface.cells
    // (2, 0) is a gap and (1, 0) is a dash. Both keep the fill's background,
    // and only the dash has the stroke's glyph.
    #expect(cells[0][2].character == " ")
    #expect(cells[0][1].character == "─")
    let gapBackground = try #require(cells[0][2].style?.backgroundColor)
    let dashBackground = try #require(cells[0][1].style?.backgroundColor)
    #expect(gapBackground == dashBackground)
  }

  // MARK: - View.border

  private func bordered(_ style: StrokeStyle, sides: Edge.Set = .all) -> some View {
    EmptyView().frame(width: 9, height: 4).border(style: style, sides: sides)
  }

  @Test(
    "a border and a rectangle stroke draw the same cells",
    arguments: [
      StrokeStyle.single, .heavy, .double, .innerHalfBlock, .ascii,
      StrokeStyle(borderSet: .single, lineJoin: .round),
      StrokeStyle(borderSet: .single, dash: [2, 1]),
      StrokeStyle(borderSet: .heavy, dash: [3, 2], dashPhase: 1.5),
      StrokeStyle(borderSet: .double, dash: [2, 1]),
    ])
  func borderMatchesStroke(style: StrokeStyle) {
    #expect(
      lines(bordered(style), width: 9, height: 4)
        == lines(Rectangle().stroke(style: style), width: 9, height: 4))
  }

  @Test("a dashed border draws the render derived in the proposal")
  func dashedBorder() {
    #expect(
      lines(bordered(StrokeStyle(borderSet: .single, dash: [2, 1])), width: 9, height: 4) == [
        "┌─ ── ──╷",
        "╵       ╵",
        "│       │",
        "╶─ ── ── ",
      ])
  }

  @Test("the dashed set dashes round the perimeter, without its gap glyph")
  func dashedSet() {
    // The set used to restart its `─·` cycle on every edge, so the top and
    // bottom edges both ran left to right and a phase could not circulate.
    let expected = [
      "┌ ─ ─ ─ ╴",
      "╷       ╵",
      "╷       ╵",
      "╶ ─ ─ ─ ┘",
    ]
    #expect(
      lines(EmptyView().frame(width: 9, height: 4).border(style: .dashed), width: 9, height: 4)
        == expected)
    // Audit render B: the same set through a shape stroke drew a solid ring.
    #expect(
      lines(Rectangle().stroke(style: StrokeStyle(borderSet: .dashed)), width: 9, height: 4)
        == expected)
  }

  @Test("the dash phase moves a border's pattern round all four edges")
  func borderDashPhase() {
    let base = lines(
      bordered(StrokeStyle(borderSet: .single, dash: [2, 1])), width: 9, height: 4)
    let shifted = lines(
      bordered(StrokeStyle(borderSet: .single, dash: [2, 1], dashPhase: 1)), width: 9, height: 4)
    #expect(base != shifted)
    #expect(shifted[0] == "┌ ── ── ┐")
  }

  @Test("sides is a mask on the same track")
  func borderSides() {
    #expect(
      lines(bordered(.single, sides: .top), width: 9, height: 4)
        == ["─────────", "         ", "         ", "         "])
    #expect(
      lines(bordered(.single, sides: [.top, .leading]), width: 9, height: 4)
        == ["┌────────", "│        ", "│        ", "│        "])
  }

  @Test("the default border and the default stroke have square corners, as in SwiftUI")
  func defaultsAreSquare() {
    let square = ["┌───┐", "│   │", "└───┘"]
    #expect(lines(EmptyView().frame(width: 5, height: 3).border(), width: 5, height: 3) == square)
    #expect(lines(Rectangle().stroke(), width: 5, height: 3) == square)
    #expect(lines(Rectangle().strokeBorder(), width: 5, height: 3) == square)
    #expect(StrokeStyle() == .single)
  }

  @Test("rounded corners are asked for: by the preset, the join or the geometry")
  func roundedIsExplicit() {
    let rounded = ["╭───╮", "│   │", "╰───╯"]
    #expect(
      lines(EmptyView().frame(width: 5, height: 3).border(style: .rounded), width: 5, height: 3)
        == rounded)
    #expect(
      lines(
        EmptyView().frame(width: 5, height: 3).border(style: StrokeStyle(lineJoin: .round)),
        width: 5, height: 3) == rounded)
    #expect(lines(RoundedRectangle(cornerRadius: 1).stroke(), width: 5, height: 3) == rounded)
  }

  @Test("the deprecated set: spelling still draws, for the deprecation window")
  @available(*, deprecated)
  func deprecatedSetSpelling() {
    // The examples repository builds against both the last tag and framework
    // main, so `set:` has to outlive the release that adds `style:`.
    #expect(
      lines(EmptyView().frame(width: 5, height: 3).border(set: .double), width: 5, height: 3)
        == ["╔═══╗", "║   ║", "╚═══╝"])
    #expect(
      lines(
        EmptyView().frame(width: 5, height: 3).border(Color.red, set: .rounded),
        width: 5, height: 3) == ["╭───╮", "│   │", "╰───╯"])
  }

  @Test("two stacked borders show the lower one through the upper one's gaps")
  func twoColorMarchingAnts() throws {
    // The recipe in Animating-Views. The dashes are complementary: 9 x 4 is 28
    // units round, which the period of 4 divides, and every arm is on in exactly
    // one of the two borders. Together they draw the whole ring.
    let lower = StrokeStyle(borderSet: .single, dash: [2, 2])
    let upper = StrokeStyle(borderSet: .single, dash: [2, 2], dashPhase: 2)
    let cells = DefaultRenderer().render(
      EmptyView().frame(width: 9, height: 4)
        .border(Color.white, style: lower)
        .border(Color.black, style: upper),
      context: .init(identity: testIdentity("StrokeTrackRenderTwoColor")),
      proposal: .init(width: 9, height: 4)
    ).rasterSurface.cells
    #expect(
      cells.map { row in String(row.map(\.character)) }
        == ["┌───────┐", "│       │", "│       │", "└───────┘"])
    // The first two units belong to the lower border and the next two to the
    // upper one.
    #expect(cells[0][0].style?.foregroundColor == Color.white)
    #expect(cells[0][1].style?.foregroundColor == Color.white)
    #expect(cells[0][2].style?.foregroundColor == Color.black)
    #expect(cells[0][3].style?.foregroundColor == Color.black)
  }

  @Test(
    "a dashed Divider draws the cells a dashed one-row stroke draws",
    arguments: [
      StrokeStyle(borderSet: .single, dash: [1, 1]),
      StrokeStyle(borderSet: .heavy, dash: [1, 1]),
      StrokeStyle(borderSet: .dashed),
      StrokeStyle(borderSet: .single, dash: [3, 2], dashPhase: 1),
    ])
  func dividerMatchesStroke(style: StrokeStyle) {
    // STUI-519: a rule and a shape stroke both read only the first glyph of a
    // dashed set, so both drew solid. One walk draws them now.
    let rule = lines(VStack { Divider(strokeStyle: style) }, width: 10, height: 1)
    #expect(rule == lines(Rectangle().stroke(style: style), width: 10, height: 1))
    #expect(rule == lines(Rectangle().strokeBorder(style: style), width: 10, height: 1))
    #expect(rule != lines(VStack { Divider() }, width: 10, height: 1))
  }
}
