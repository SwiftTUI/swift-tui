import Testing

@testable import SwiftTUICore

@Suite
struct StrokeTrackTests {
  /// Draws a track into lines of text through `forEachGlyph`, the same walk the
  /// rasterizer paints with.
  private func render(
    width: Int,
    height: Int,
    borderSet: BorderSet = .single,
    roundsCorners: Bool = false,
    sides: Edge.Set = .all,
    dash: [Double] = [],
    dashPhase: Double = 0,
    dashOrigin: Double = 0,
    trim: StrokeTrim? = nil,
    roundedStart: Bool = false,
    aspectRatio: Double = 2,
    lineAxis: Axis? = nil
  ) -> [String] {
    let track = RectangleStrokeTrack(
      width: width, height: height, aspectRatio: aspectRatio, lineAxis: lineAxis)
    let pen = StrokePen(borderSet: borderSet, roundsCorners: roundsCorners)
    let pattern = StrokeDashPattern(dash: dash, phase: dashPhase)
    var grid = Array(repeating: Array(repeating: Character(" "), count: width), count: height)
    track.forEachGlyph(
      pen: pen,
      sides: sides,
      mask: StrokeMask(
        dash: pattern, trim: trim, origin: dashOrigin,
        trimOrigin: roundedStart ? dashOrigin : track.leadingCornerVertex)
    ) { cell, glyph in
      grid[cell.y][cell.x] = glyph
    }
    return grid.map { String($0) }
  }

  // MARK: - Track

  @Test("the ring is walked clockwise from the top-leading corner")
  func clockwiseOrder() {
    var visited: [[Int]] = []
    RectangleStrokeTrack(width: 3, height: 3, aspectRatio: 2).forEachCell {
      visited.append([$0.x, $0.y])
    }
    #expect(
      visited == [[0, 0], [1, 0], [2, 0], [2, 1], [2, 2], [1, 2], [0, 2], [0, 1]])
  }

  @Test("cell intervals are contiguous and sum to the track length", arguments: [2.0, 1.5])
  func contiguousIntervals(aspectRatio: Double) {
    let track = RectangleStrokeTrack(width: 9, height: 4, aspectRatio: aspectRatio)
    var cursor = 0.0
    var count = 0
    track.forEachCell { cell in
      #expect(abs(cell.start - cursor) < 1e-9)
      cursor += cell.length
      count += 1
    }
    #expect(count == 2 * (9 + 4) - 4)
    #expect(abs(cursor - track.length) < 1e-9)
    #expect(abs(track.length - (2 * 8 + 2 * aspectRatio * 3)) < 1e-9)
  }

  @Test("a vertical cell is as long as the cell is tall")
  func verticalCellsUseTheAspectRatio() {
    var lengths: [Double] = []
    RectangleStrokeTrack(width: 1, height: 3, aspectRatio: 2).forEachCell {
      lengths.append($0.length)
    }
    #expect(lengths == [2, 2, 2])
  }

  @Test("the aspect ratio snaps to the nearest half")
  func aspectSnapping() {
    #expect(RectangleStrokeTrack.snappedAspectRatio(2.0) == 2)
    #expect(RectangleStrokeTrack.snappedAspectRatio(2.1) == 2)
    #expect(RectangleStrokeTrack.snappedAspectRatio(2.3) == 2.5)
    #expect(RectangleStrokeTrack.snappedAspectRatio(1.7) == 1.5)
    #expect(RectangleStrokeTrack.snappedAspectRatio(0.1) == 0.5)
    #expect(RectangleStrokeTrack.snappedAspectRatio(0) == 2)
    #expect(RectangleStrokeTrack.snappedAspectRatio(.nan) == 2)
  }

  // MARK: - Dash

  @Test("a dash pattern alternates on and off from the start of the track")
  func dashPattern() throws {
    let pattern = try #require(StrokeDashPattern(dash: [2, 1], phase: 0))
    #expect(pattern.isOn(at: 0))
    #expect(pattern.isOn(at: 1.99))
    #expect(!pattern.isOn(at: 2))
    #expect(!pattern.isOn(at: 2.99))
    #expect(pattern.isOn(at: 3))
  }

  @Test("the phase is how far into the pattern the track starts")
  func dashPhase() throws {
    let pattern = try #require(StrokeDashPattern(dash: [2, 1], phase: 2))
    #expect(!pattern.isOn(at: 0))
    #expect(pattern.isOn(at: 1))
    let negative = try #require(StrokeDashPattern(dash: [2, 1], phase: -1))
    #expect(!negative.isOn(at: 0))
    #expect(negative.isOn(at: 1))
  }

  @Test("an odd pattern repeats to make an even one, as Core Graphics does")
  func oddDashCount() throws {
    let pattern = try #require(StrokeDashPattern(dash: [1], phase: 0))
    #expect(pattern.isOn(at: 0.5))
    #expect(!pattern.isOn(at: 1.5))
    #expect(pattern.isOn(at: 2.5))
  }

  @Test("a pattern that cannot dash is a solid stroke")
  func solidPatterns() {
    #expect(StrokeDashPattern(dash: [], phase: 0) == nil)
    #expect(StrokeDashPattern(dash: [0, 0], phase: 0) == nil)
    #expect(StrokeDashPattern(dash: [2, -1], phase: 0) == nil)
    #expect(StrokeDashPattern(dash: [.infinity, 1], phase: 0) == nil)
  }

  // MARK: - Pen

  @Test(
    "the arms lookup reproduces every hand-authored line palette",
    arguments: [
      BorderSet.single, .rounded, .double, .heavy, .singleDouble, .doubleSingle,
    ])
  func linePalettesMatchTheirPresets(borderSet: BorderSet) throws {
    let lines = render(width: 4, height: 3, borderSet: borderSet)
    let top = try #require(borderSet.top.first)
    let bottom = try #require(borderSet.bottom.first)
    #expect(lines[0] == borderSet.topLeading + String([top, top]) + borderSet.topTrailing)
    #expect(lines[1] == borderSet.left + "  " + borderSet.right)
    #expect(
      lines[2] == borderSet.bottomLeading + String([bottom, bottom]) + borderSet.bottomTrailing)
  }

  @Test("an edge palette picks its glyph from the side or corner")
  func edgePalettes() {
    #expect(
      render(width: 4, height: 3, borderSet: .outerHalfBlock) == ["▛▀▀▜", "▌  ▐", "▙▄▄▟"])
    #expect(render(width: 3, height: 2, borderSet: .none) == ["   ", "   "])
  }

  @Test("a palette of three glyphs is a plain line pen, and draws what it always drew")
  func plainLinePalettes() {
    #expect(
      StrokePen(borderSet: .ascii, roundsCorners: false)
        == .plainLine(horizontal: "-", vertical: "|", junction: "+"))
    #expect(
      StrokePen(borderSet: .markdown, roundsCorners: false)
        == .plainLine(horizontal: "-", vertical: "|", junction: "|"))
    #expect(render(width: 4, height: 3, borderSet: .ascii) == ["+--+", "|  |", "+--+"])
    #expect(render(width: 4, height: 3, borderSet: .markdown) == ["|--|", "|  |", "|--|"])
    // An edge that ends at a corner is still drawn to the far side of the cell.
    #expect(
      render(width: 4, height: 3, borderSet: .ascii, sides: [.top, .leading])
        == ["+---", "|   ", "|   "])
    #expect(render(width: 4, height: 3, borderSet: .ascii, sides: .top)[0] == "----")
  }

  @Test("a palette that draws nothing, or differs from side to side, is an edge pen")
  func edgePenClassification() {
    for borderSet in [BorderSet.hidden, .none, .innerHalfBlock, .outerHalfBlock] {
      guard case .edge = StrokePen(borderSet: borderSet, roundsCorners: false) else {
        Issue.record("\(borderSet) is not an edge pen")
        continue
      }
    }
  }

  @Test("the geometry or the join can ask for rounded corners")
  func roundedCorners() {
    #expect(
      render(width: 4, height: 3, roundsCorners: true) == ["╭──╮", "│  │", "╰──╯"])
    // Unicode has no heavy arc, so a heavy stroke keeps its square corners.
    #expect(
      render(width: 4, height: 3, borderSet: .heavy, roundsCorners: true)
        == ["┏━━┓", "┃  ┃", "┗━━┛"])
  }

  // MARK: - Sides

  @Test("an edge that ends at a corner is drawn to the far side of the cell")
  func sides() {
    #expect(render(width: 4, height: 3, sides: .top) == ["────", "    ", "    "])
    #expect(
      render(width: 4, height: 3, sides: [.leading, .trailing]) == ["│  │", "│  │", "│  │"])
    #expect(render(width: 4, height: 3, sides: [.top, .leading]) == ["┌───", "│   ", "│   "])
    #expect(
      render(width: 4, height: 3, borderSet: .outerHalfBlock, sides: [.top, .leading])
        == ["▛▀▀▀", "▌   ", "▌   "])
  }

  @Test("a rectangle one row high or one column wide is a line")
  func lines() {
    #expect(render(width: 5, height: 1) == ["─────"])
    #expect(render(width: 1, height: 3) == ["│", "│", "│"])
    #expect(render(width: 5, height: 1, sides: .bottom) == ["─────"])
    // One cell is one row high and one column wide at once, so only the caller
    // knows which way a 1 x 1 rule runs.
    #expect(render(width: 1, height: 1) == ["─"])
    #expect(render(width: 1, height: 1, lineAxis: .horizontal) == ["─"])
    #expect(render(width: 1, height: 1, lineAxis: .vertical) == ["│"])
    #expect(render(width: 1, height: 1, sides: .leading, lineAxis: .vertical) == ["│"])
    // The axis never overrides the shape of a longer line.
    #expect(render(width: 3, height: 1, lineAxis: .vertical) == ["───"])
    #expect(render(width: 1, height: 2, lineAxis: .horizontal) == ["│", "│"])
    #expect(render(width: 5, height: 1, sides: .leading) == ["     "])
  }

  // MARK: - Dashed strokes

  @Test("the render derived by hand in the redesign proposal")
  func proposalRender() {
    #expect(
      render(width: 9, height: 4, dash: [2, 1]) == [
        "┌─ ── ──╷",
        "╵       ╵",
        "│       │",
        "╶─ ── ── ",
      ])
  }

  @Test("a dash end that falls inside a cell draws a half-line")
  func halfCellResolution() {
    // Half a unit of phase moves every boundary to the middle of a cell.
    #expect(render(width: 7, height: 1, dash: [2, 1], dashPhase: -0.5) == ["╶─╴╶─╴╶"])
  }

  @Test("a phase of one period draws the same cells")
  func phaseIsPeriodic() {
    #expect(
      render(width: 9, height: 4, dash: [2, 1], dashPhase: 3)
        == render(width: 9, height: 4, dash: [2, 1]))
  }

  @Test("the phase moves the pattern the same way around all four edges")
  func phaseCirculates() {
    // 12 x 6 at an aspect ratio of 1 is 32 units round, which a period of 4
    // divides, so the pattern closes with no seam.
    let base = render(width: 12, height: 6, dash: [3, 1], aspectRatio: 1)
    let shifted = render(width: 12, height: 6, dash: [3, 1], dashPhase: 1, aspectRatio: 1)
    // A positive phase starts further into the pattern, so every gap moves
    // toward the start of the track: left along the top, right along the
    // bottom. A phase that only slid each edge the same way would not do that.
    #expect(base[0] == "┌── ─── ─── ")
    #expect(shifted[0] == "┌─ ─── ─── ┐")
    #expect(base[5] == " ─── ─── ──┘")
    #expect(shifted[5] == "└ ─── ─── ─┘")
  }

  @Test("a pen without half-lines dashes in whole cells")
  func wholeCellSampling() {
    #expect(
      render(width: 7, height: 1, borderSet: .double, dash: [2, 1], dashPhase: -0.5)
        == ["══ ══ ═"])
  }

  @Test("a rounded rectangle measures its dash from the middle of the trailing edge")
  func dashOrigin() {
    let track = RectangleStrokeTrack(width: 9, height: 5, aspectRatio: 2)
    #expect(track.trailingEdgeMidpoint == 8 + 2 * 4 / 2)
    let lines = render(
      width: 9, height: 5, dash: [4, 100], dashOrigin: track.trailingEdgeMidpoint)
    // One dash, 4 units long, starting half way down the trailing edge and
    // running clockwise: two vertical cells.
    #expect(lines.map { String($0.suffix(1)) } == [" ", " ", "│", "│", " "])
  }

  // MARK: - Trim

  @Test("a quarter trim of a rectangle is its top edge, from the corner's vertex")
  func trimFirstQuarter() {
    // 9 x 4 at an aspect ratio of 2 is 28 units round, and the top edge is 8 of
    // them, vertex to vertex. A quarter is 7: half of the corner cell, six
    // whole cells and half of the eighth. The arm that points down the leading
    // edge belongs to the end of the path, so the trim does not draw it.
    #expect(
      render(width: 9, height: 4, trim: StrokeTrim(from: 0, to: 0.25)) == [
        "╶──────╴ ",
        "         ",
        "         ",
        "         ",
      ])
  }

  @Test("the second half of a rectangle is its bottom and leading edges")
  func trimSecondHalf() {
    #expect(
      render(width: 9, height: 4, trim: StrokeTrim(from: 0.5, to: 1)) == [
        "╷        ",
        "│        ",
        "│        ",
        "└───────╴",
      ])
  }

  @Test("the whole trim draws the whole ring, and an empty one draws nothing")
  func trimExtremes() {
    #expect(
      render(width: 5, height: 3, trim: StrokeTrim(from: 0, to: 1))
        == render(width: 5, height: 3))
    #expect(
      render(width: 5, height: 3, trim: StrokeTrim(from: 0.5, to: 0.5))
        == ["     ", "     ", "     "])
    #expect(
      render(width: 5, height: 3, trim: StrokeTrim(from: 0.75, to: 0.25))
        == ["     ", "     ", "     "])
  }

  @Test("a dash on a trimmed stroke falls where the untrimmed dash does")
  func trimWithDash() {
    #expect(
      render(width: 9, height: 4, dash: [2, 1], trim: StrokeTrim(from: 0, to: 0.5)) == [
        "╶─ ── ──╷",
        "        ╵",
        "        │",
        "         ",
      ])
  }

  @Test("a rounded rectangle is trimmed from the middle of its trailing edge")
  func trimRoundedRectangle() {
    let track = RectangleStrokeTrack(width: 9, height: 5, aspectRatio: 2)
    #expect(
      render(
        width: 9, height: 5, roundsCorners: true,
        dashOrigin: track.trailingEdgeMidpoint, trim: StrokeTrim(from: 0, to: 0.25),
        roundedStart: true) == [
          "         ",
          "         ",
          "        │",
          "        │",
          "     ───╯",
        ])
  }

  @Test("a dash's seam falls at the start of the path, not at the top-leading corner")
  func dashSeamIsAtTheStartOfThePath() {
    // 9 x 5 is 32 units round. A period of 5 does not divide it, so the pattern
    // has a seam where it restarts. Measured from the middle of the trailing
    // edge, the seam is there: the cell just before it, (8, 1), is 30 to 32
    // units along the path, which is inside a dash, so it is whole. If positions
    // did not wrap round the track, that cell would read as -2 to 0, its second
    // half would fall in a gap, and it would draw `╵`.
    let track = RectangleStrokeTrack(width: 9, height: 5, aspectRatio: 2)
    let lines = render(
      width: 9, height: 5, dash: [4, 1], dashOrigin: track.trailingEdgeMidpoint,
      roundedStart: true)
    #expect(lines[1].last == "│")
    #expect(lines[2].last == "│")
  }

  @Test("a trim clamps its fractions")
  func trimClamps() {
    #expect(StrokeTrim(from: -1, to: 2) == StrokeTrim(from: 0, to: 1))
    #expect(StrokeTrim(from: .nan, to: .infinity) == StrokeTrim(from: 0, to: 1))
    #expect(StrokeTrim(from: 0.6, to: 0.4).isEmpty)
  }
}
