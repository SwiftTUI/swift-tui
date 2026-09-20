/// The line arms each cell holds, for one raster pass.
///
/// A cell holds one glyph. When two line strokes reach the same cell, the glyph
/// has to show both: `─` over `│` is `┼`, and a `Divider` that ends under a
/// border is `├`. Each line stroke records the arms it draws here, and a later
/// stroke merges with them.
///
/// An arm is hard or soft. A hard arm is one the track and the mask call for. A
/// soft arm is a cap: it draws the end cell of an open track to its edge, so a
/// lone `Divider` is `─` to both ends. A cap gives way to a line that crosses
/// it, which is any hard arm on the other axis. That is what makes a `Divider`
/// end under a border `├` and not `┼`, and it makes stacked single-side borders
/// meet in `┌`. Two rules that end in the same cell on the same axis keep their
/// caps.
///
/// The arms are recorded by strokes. They are never read back from a glyph, so
/// `Text` that contains box-drawing characters does not merge. An entry also
/// remembers the glyph it wrote: if the cell holds anything else when the next
/// stroke arrives, something painted over it, and the entry is ignored. Text
/// that paints the very glyph the stroke wrote cannot be told apart. The line
/// is still under it, so the next stroke joins that line.
///
/// One table serves one raster pass and one layer. It is a reference type so
/// that the painters can take it as an optional argument, as they take the
/// presentation recorder. A painter called without one draws as it always did,
/// and the last stroke to reach a cell wins.
internal final class LineArmsTable {
  private struct Entry {
    var hard: LineArms
    var soft: LineArms
    var roundsCorner: Bool
    var glyph: Character
  }

  private var entries: [CellPoint: Entry] = [:]

  internal init() {}

  /// The glyph a stroke draws in a cell, merged with any line stroke that drew
  /// there earlier in the pass.
  ///
  /// - Parameters:
  ///   - ink: What the stroke draws when it has the cell to itself.
  ///   - current: The glyph the cell holds now.
  internal func glyph(
    merging ink: RectangleStrokeTrack.Ink,
    atX x: Int,
    y: Int,
    current: Character
  ) -> Character {
    let point = CellPoint(x: x, y: y)
    guard let incoming = ink.hardArms else {
      // An edge pen does not merge, and it paints over whatever was there.
      entries[point] = nil
      return ink.glyph
    }
    guard let existing = entries[point], existing.glyph == current else {
      entries[point] = Entry(
        hard: incoming, soft: ink.softArms, roundsCorner: ink.roundsCorner, glyph: ink.glyph)
      return ink.glyph
    }

    // The incoming stroke is on top, so its weight wins where both draw an arm.
    var hard = existing.hard
    var soft = existing.soft
    for direction in LineDirection.allCases {
      if incoming[direction] != .none {
        hard[direction] = incoming[direction]
      }
      if ink.softArms[direction] != .none {
        soft[direction] = ink.softArms[direction]
      }
    }
    for direction in LineDirection.allCases where hard[direction] != .none {
      soft[direction] = .none
    }

    // A stroke that covers every arm in the cell draws as it would alone, so a
    // square border over a rounded one has square corners.
    let roundsCorner =
      hard == incoming ? ink.roundsCorner : existing.roundsCorner || ink.roundsCorner
    let drawn = Self.drawnArms(hard: hard, soft: soft)
    // Unicode has no glyph for some mixes: heavy with double, a double
    // half-line, or light and double on one axis. Every arm then takes the
    // weight of the stroke on top. The alphabet is the top stroke's too, so an
    // ASCII border over a `─` is `+`.
    let glyph =
      ink.alphabet.glyph(
        for: drawn, roundedCorner: roundsCorner, fallbackWeight: ink.fallbackWeight)
      ?? ink.glyph
    entries[point] = Entry(hard: hard, soft: soft, roundsCorner: roundsCorner, glyph: glyph)
    return glyph
  }

  /// The hard arms, and each cap that no hard arm crosses.
  private static func drawnArms(hard: LineArms, soft: LineArms) -> LineArms {
    let crossesHorizontal = hard.north != .none || hard.south != .none
    let crossesVertical = hard.east != .none || hard.west != .none
    var drawn = hard
    for direction in LineDirection.allCases where soft[direction] != .none {
      if !(direction.isHorizontal ? crossesHorizontal : crossesVertical) {
        drawn[direction] = soft[direction]
      }
    }
    return drawn
  }
}
