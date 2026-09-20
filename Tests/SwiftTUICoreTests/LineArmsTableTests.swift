import Testing

@testable import SwiftTUICore

@Suite
struct LineArmsTableTests {
  private func ink(
    _ glyph: Character, _ arms: LineArms?, soft: LineArms = LineArms(), rounds: Bool = false,
    weight: LineWeight = .light
  ) -> RectangleStrokeTrack.Ink {
    RectangleStrokeTrack.Ink(
      cell: .init(
        x: 0, y: 0,
        incoming: .init(direction: .west, side: .top),
        outgoing: .init(direction: .east, side: .top),
        start: 0, length: 1, isCorner: false),
      glyph: glyph, hardArms: arms, softArms: soft, roundsCorner: rounds, fallbackWeight: weight)
  }

  /// The first cell of a rule: it draws `─`, but only its east arm is hard.
  private var ruleStart: RectangleStrokeTrack.Ink {
    ink("─", LineArms(east: .light), soft: LineArms(west: .light))
  }

  @Test("the first stroke in a cell draws its own glyph")
  func firstStroke() {
    let table = LineArmsTable()
    let horizontal = ink("─", LineArms(east: .light, west: .light))
    #expect(table.glyph(merging: horizontal, atX: 3, y: 1, current: " ") == "─")
  }

  @Test("a second stroke merges with the first")
  func crossing() {
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("─", LineArms(east: .light, west: .light)), atX: 3, y: 1, current: " ")
    let vertical = ink("│", LineArms(north: .light, south: .light))
    #expect(table.glyph(merging: vertical, atX: 3, y: 1, current: "─") == "┼")
    // A different cell is untouched.
    #expect(table.glyph(merging: vertical, atX: 4, y: 1, current: " ") == "│")
  }

  @Test("a soft cap gives way, so a rule that ends under a border is a tee")
  func softCapGivesWay() {
    let table = LineArmsTable()
    _ = table.glyph(merging: ruleStart, atX: 0, y: 2, current: " ")
    let border = ink("│", LineArms(north: .light, south: .light))
    #expect(table.glyph(merging: border, atX: 0, y: 2, current: "─") == "├")
  }

  @Test("the merge does not depend on which stroke came first")
  func orderIndependent() {
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("│", LineArms(north: .light, south: .light)), atX: 0, y: 2, current: " ")
    #expect(
      table.glyph(merging: ink("─", LineArms(east: .light)), atX: 0, y: 2, current: "│") == "├")
  }

  @Test("two single-side borders meet in a corner")
  func stackedSides() {
    let table = LineArmsTable()
    // The top border's first cell draws `─` with a hard east arm, and the
    // leading border's first cell draws `│` with a hard south arm.
    _ = table.glyph(merging: ruleStart, atX: 0, y: 0, current: " ")
    let leading = ink("│", LineArms(south: .light), soft: LineArms(north: .light))
    #expect(table.glyph(merging: leading, atX: 0, y: 0, current: "─") == "┌")
  }

  @Test("a cap gives way only to a line that crosses it")
  func capsOnOneAxisStay() {
    // Two rules that start in the same cell are still one whole `─`.
    let table = LineArmsTable()
    _ = table.glyph(merging: ruleStart, atX: 0, y: 0, current: " ")
    #expect(table.glyph(merging: ruleStart, atX: 0, y: 0, current: "─") == "─")
    // And the cap still gives way to a border drawn after both.
    let border = ink("│", LineArms(north: .light, south: .light))
    #expect(table.glyph(merging: border, atX: 0, y: 0, current: "─") == "├")
  }

  @Test("a rule one cell long gives way to the border it lands on")
  func allSoftRule() {
    let dot = ink("─", LineArms(), soft: LineArms(east: .light, west: .light))
    let table = LineArmsTable()
    #expect(table.glyph(merging: dot, atX: 0, y: 0, current: " ") == "─")
    _ = table.glyph(
      merging: ink("│", LineArms(north: .light, south: .light)), atX: 5, y: 0, current: " ")
    #expect(table.glyph(merging: dot, atX: 5, y: 0, current: "│") == "│")
  }

  @Test("a cell that something painted over does not merge")
  func paintedOver() {
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("─", LineArms(east: .light, west: .light)), atX: 1, y: 1, current: " ")
    // The cell now holds a letter, so text was painted over the line.
    let vertical = ink("│", LineArms(north: .light, south: .light))
    #expect(table.glyph(merging: vertical, atX: 1, y: 1, current: "x") == "│")
  }

  @Test("text that looks like a line does not merge")
  func textIsNotALine() {
    // Nothing recorded arms for this cell, whatever glyph it holds.
    let table = LineArmsTable()
    let vertical = ink("│", LineArms(north: .light, south: .light))
    #expect(table.glyph(merging: vertical, atX: 1, y: 1, current: "─") == "│")
  }

  @Test("an edge pen does not merge, and it ends the merge in its cell")
  func edgePen() {
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("─", LineArms(east: .light, west: .light)), atX: 1, y: 1, current: " ")
    #expect(table.glyph(merging: ink("▀", nil), atX: 1, y: 1, current: "─") == "▀")
    let vertical = ink("│", LineArms(north: .light, south: .light))
    #expect(table.glyph(merging: vertical, atX: 1, y: 1, current: "▀") == "│")
  }

  @Test("an edge pen ends the merge even when it paints the glyph a line wrote")
  func edgePenPaintsALineGlyph() {
    // A custom set can put `─` on one side and not be a line pen. Nothing of
    // the rule under it is left to join.
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("─", LineArms(east: .light, west: .light)), atX: 1, y: 1, current: " ")
    #expect(table.glyph(merging: ink("─", nil), atX: 1, y: 1, current: "─") == "─")
    let vertical = ink("│", LineArms(north: .light, south: .light))
    #expect(table.glyph(merging: vertical, atX: 1, y: 1, current: "─") == "│")
  }

  @Test("where two strokes draw the same arm, it takes the weight of the one on top")
  func sharedArm() {
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("─", LineArms(east: .light, west: .light)), atX: 0, y: 0, current: " ")
    // A heavy corner over a light line. East is heavy now, and west is still
    // light: LEFT LIGHT AND RIGHT DOWN HEAVY.
    let corner = ink("┏", LineArms(east: .heavy, south: .heavy), weight: .heavy)
    #expect(table.glyph(merging: corner, atX: 0, y: 0, current: "─") == "┲")
  }

  @Test("the stroke on top wins a shared arm, and light mixes with heavy")
  func weights() {
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("─", LineArms(east: .light, west: .light)), atX: 0, y: 0, current: " ")
    let heavy = ink("┃", LineArms(north: .heavy, south: .heavy), weight: .heavy)
    #expect(table.glyph(merging: heavy, atX: 0, y: 0, current: "─") == "╂")
  }

  @Test("a mix Unicode has no glyph for takes the weight of the stroke on top")
  func missingMix() {
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("━", LineArms(east: .heavy, west: .heavy), weight: .heavy), atX: 0, y: 0,
      current: " ")
    // Heavy and double never mix.
    let double = ink("║", LineArms(north: .double, south: .double), weight: .double)
    #expect(table.glyph(merging: double, atX: 0, y: 0, current: "━") == "╬")
  }

  @Test("a rounded corner survives a merge that leaves two light arms")
  func roundedCorner() {
    let table = LineArmsTable()
    _ = table.glyph(
      merging: ink("─", LineArms(east: .light), soft: LineArms(west: .light), rounds: true),
      atX: 0, y: 0, current: " ")
    let leading = ink("│", LineArms(south: .light), soft: LineArms(north: .light), rounds: true)
    #expect(table.glyph(merging: leading, atX: 0, y: 0, current: "─") == "╭")
  }

  @Test("a stroke that covers every arm in the cell draws as it would alone")
  func squareOverRounded() {
    let table = LineArmsTable()
    let corner = LineArms(east: .light, south: .light)
    _ = table.glyph(merging: ink("╭", corner, rounds: true), atX: 0, y: 0, current: " ")
    #expect(table.glyph(merging: ink("┌", corner), atX: 0, y: 0, current: "╭") == "┌")
  }
}
