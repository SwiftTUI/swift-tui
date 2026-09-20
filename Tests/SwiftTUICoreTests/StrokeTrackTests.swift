import Testing

@testable import SwiftTUICore

@Suite
struct StrokeTrackTests {
  /// Draws a track into lines of text with the same three calls the rasterizer
  /// makes: walk the cells, resolve the mask, ask the pen for a glyph.
  private func render(
    width: Int,
    height: Int,
    borderSet: BorderSet = .single,
    roundsCorners: Bool = false,
    sides: Edge.Set = .all,
    dash: [Double] = [],
    dashPhase: Double = 0,
    dashOrigin: Double = 0,
    aspectRatio: Double = 2
  ) -> [String] {
    let track = RectangleStrokeTrack(width: width, height: height, aspectRatio: aspectRatio)
    let pen = StrokePen(borderSet: borderSet, roundsCorners: roundsCorners)
    let pattern = StrokeDashPattern(dash: dash, phase: dashPhase)
    var grid = Array(repeating: Array(repeating: Character(" "), count: width), count: height)
    track.forEachCell { cell in
      let resolved = track.resolve(
        cell,
        sides: sides,
        dash: pattern,
        dashOrigin: dashOrigin,
        samplesEachArm: pen.samplesEachArm
      )
      if let glyph = pen.glyph(for: cell, resolved: resolved) {
        grid[cell.y][cell.x] = glyph
      }
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
    #expect(render(width: 4, height: 3, borderSet: .ascii) == ["+--+", "|  |", "+--+"])
    #expect(render(width: 3, height: 2, borderSet: .none) == ["   ", "   "])
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
}
