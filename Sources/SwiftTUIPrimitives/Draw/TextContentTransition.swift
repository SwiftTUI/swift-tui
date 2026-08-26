/// The draw-layer model of a `Text` content transition.
///
/// The public `ContentTransition` value in `SwiftTUIViews` maps onto this
/// type when a `Text` resolves; the animation controller and the draw
/// extractor never see the public type. `nil` on a node means `.identity`
/// (the text cuts to its new string).
package struct TextContentTransition: Hashable, Sendable {
  package enum Kind: Hashable, Sendable {
    /// The old string dims out to the midpoint, then the new string dims in.
    case opacity
    /// Changed digit columns count through the intermediate digits toward
    /// their target; other changed columns cross-fade.
    case numericText
  }

  package var kind: Kind
  /// `numericText(countsDown:)`: roll each changed digit downward.
  package var countsDown: Bool
  /// `numericText(value:)`: the sign of the change between two values picks
  /// the direction; `nil` for the `countsDown:` form.
  package var value: Double?

  package init(kind: Kind, countsDown: Bool = false, value: Double? = nil) {
    self.kind = kind
    self.countsDown = countsDown
    self.value = value
  }
}

/// One drawn column of a rolling text run.
package struct TextRollColumn: Equatable, Sendable {
  package var character: Character
  /// The column's own opacity factor, multiplied into the run's style.
  package var opacity: Double

  package init(character: Character, opacity: Double) {
    self.character = character
    self.opacity = opacity
  }
}

/// The animatable slot value of a `Text` node that carries a content
/// transition: its string, and — while a roll is in flight — the string it
/// is rolling from and the phase of the roll.
///
/// At rest the value is `(previous: nil, text, phase: 1)`. The controller
/// starts a roll when a node's at-rest value changes its `text` inside an
/// animated transaction; `AnyAnimatable` interpolates two values through
/// ``rolling(to:progress:)`` rather than the generic `animatableData`
/// arithmetic, so the sampled value carries both strings.
///
/// Equality is on `previous`, `text`, and `phase` only: a change in the
/// transition's `value:` or direction with an unchanged string must not
/// start a roll.
package struct TextRollValue: Sendable, Animatable {
  /// The string being rolled from, or `nil` at rest.
  package var previous: String?
  /// The string being displayed (at rest) or rolled toward (in flight).
  package var text: String
  package var transition: TextContentTransition
  /// The resolved direction of this roll.
  package var countsDown: Bool
  /// `1` at rest; the eased progress of the roll in flight.
  package var phase: Double

  package init(
    previous: String? = nil,
    text: String,
    transition: TextContentTransition,
    countsDown: Bool? = nil,
    phase: Double = 1
  ) {
    self.previous = previous
    self.text = text
    self.transition = transition
    self.countsDown = countsDown ?? transition.countsDown
    self.phase = phase
  }

  package var animatableData: Double {
    get { phase }
    set { phase = newValue }
  }

  /// Whether draw extraction has intermediate glyphs to render.
  package var isRolling: Bool {
    previous != nil && phase < 1
  }

  /// The roll from this value's displayed string toward `target` at the
  /// given eased `progress`. A value that is itself mid-roll hands over the
  /// string it is displaying, so a retarget continues from what is on
  /// screen instead of jumping back to the original string.
  package func rolling(to target: TextRollValue, progress: Double) -> TextRollValue {
    var result = target
    result.previous = isRolling ? renderedText : text
    result.countsDown = resolvedDirection(to: target)
    result.phase = progress.isFinite ? min(max(progress, 0), 1) : 1
    return result
  }

  /// `numericText(value:)` picks the direction from the sign of the change;
  /// the `countsDown:` form and `.opacity` use the target's own flag.
  private func resolvedDirection(to target: TextRollValue) -> Bool {
    if let from = transition.value, let to = target.transition.value, from != to {
      return to < from
    }
    return target.transition.countsDown
  }

  /// The string of the columns drawn at the current phase.
  package var renderedText: String {
    String(renderedColumns().map(\.character))
  }

  /// The columns to draw at the current phase: the new string's layout with
  /// each changed digit column stepped toward its target and each other
  /// changed column cross-faded. Unchanged columns are untouched.
  ///
  /// Every column is one character of the new string or a same-width
  /// substitute, so the rendered run lays out exactly like the new string;
  /// the roll never re-wraps. Only ASCII digits roll (a digit paired with a
  /// full-width or other numeral takes the cross-fade path).
  package func renderedColumns() -> [TextRollColumn] {
    let new = Array(text)
    guard let previous, phase < 1 else {
      return new.map { TextRollColumn(character: $0, opacity: 1) }
    }
    let old = Array(previous)
    switch transition.kind {
    case .opacity:
      if phase < 0.5 {
        return old.map { TextRollColumn(character: $0, opacity: 1 - 2 * phase) }
      }
      return new.map { TextRollColumn(character: $0, opacity: 2 * phase - 1) }
    case .numericText:
      return numericColumns(old: old, new: new)
    }
  }

  private func numericColumns(old: [Character], new: [Character]) -> [TextRollColumn] {
    // Align on the longest common prefix and suffix; pair the remaining
    // region right-aligned so a length change keeps the units column in
    // place (`99 → 100` rolls both nines and fades the leading `1` in).
    var prefix = 0
    while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
      prefix += 1
    }
    var suffix = 0
    while suffix < old.count - prefix, suffix < new.count - prefix,
      old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
    {
      suffix += 1
    }
    let oldRegion = old[prefix..<(old.count - suffix)]
    let newRegion = new[prefix..<(new.count - suffix)]
    let shift = newRegion.count - oldRegion.count

    var columns: [TextRollColumn] = []
    columns.reserveCapacity(new.count)
    for index in 0..<prefix {
      columns.append(TextRollColumn(character: new[index], opacity: 1))
    }
    for (offset, target) in newRegion.enumerated() {
      let pairedOffset = offset - shift
      guard pairedOffset >= 0, pairedOffset < oldRegion.count else {
        // An added column fades in at the new string's width.
        columns.append(TextRollColumn(character: target, opacity: phase))
        continue
      }
      let source = oldRegion[oldRegion.startIndex + pairedOffset]
      columns.append(rolledColumn(from: source, to: target))
    }
    for index in (new.count - suffix)..<new.count {
      columns.append(TextRollColumn(character: new[index], opacity: 1))
    }
    return columns
  }

  private func rolledColumn(from source: Character, to target: Character) -> TextRollColumn {
    guard source != target else {
      return TextRollColumn(character: target, opacity: 1)
    }
    if let from = Self.asciiDigit(source), let to = Self.asciiDigit(target) {
      let steps = countsDown ? (from - to + 10) % 10 : (to - from + 10) % 10
      let taken = Int((phase * Double(steps)).rounded())
      let digit = countsDown ? (from - taken + 20) % 10 : (from + taken) % 10
      let character = Character(UnicodeScalar(UInt8(ascii: "0") + UInt8(digit)))
      return TextRollColumn(character: character, opacity: Self.dip(at: phase))
    }
    if Self.isSingleCellASCII(source), Self.isSingleCellASCII(target) {
      // Same-width glyphs cross-fade: the old one dims out to the midpoint,
      // the new one dims in from it.
      if phase < 0.5 {
        return TextRollColumn(character: source, opacity: 1 - 2 * phase)
      }
      return TextRollColumn(character: target, opacity: 2 * phase - 1)
    }
    // The old glyph may not share the new glyph's cell width; keep the new
    // string's layout and fade the new glyph in.
    return TextRollColumn(character: target, opacity: phase)
  }

  /// The dim that marks a stepping digit column: full at both ends of the
  /// roll, half at its midpoint, so the motion reads as a roll rather than a
  /// flicker.
  private static func dip(at phase: Double) -> Double {
    1 - 0.5 * (1 - abs(2 * phase - 1))
  }

  private static func asciiDigit(_ character: Character) -> Int? {
    guard let ascii = character.asciiValue,
      ascii >= UInt8(ascii: "0"), ascii <= UInt8(ascii: "9")
    else {
      return nil
    }
    return Int(ascii - UInt8(ascii: "0"))
  }

  private static func isSingleCellASCII(_ character: Character) -> Bool {
    guard let ascii = character.asciiValue else { return false }
    return ascii >= 0x20 && ascii < 0x7F
  }
}

extension TextRollValue: Equatable {
  package static func == (lhs: TextRollValue, rhs: TextRollValue) -> Bool {
    lhs.previous == rhs.previous && lhs.text == rhs.text && lhs.phase == rhs.phase
  }
}
