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
}
