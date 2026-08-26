import Testing

@_spi(Testing) @testable import SwiftTUICore

/// Unit pins for the per-column roll algorithm behind `ContentTransition`
/// (plan 2026-08-25-004 §3): what each column shows at a phase, how a
/// retarget hands over, and how draw extraction groups the columns.
@Suite("Text roll columns")
struct TextRollValueTests {
  private static let numeric = TextContentTransition(kind: .numericText)
  private static let numericDown = TextContentTransition(kind: .numericText, countsDown: true)
  private static let opacity = TextContentTransition(kind: .opacity)

  private static func roll(
    _ from: String, _ to: String,
    _ transition: TextContentTransition = numeric,
    phase: Double
  ) -> TextRollValue {
    TextRollValue(text: from, transition: transition)
      .rolling(to: TextRollValue(text: to, transition: transition), progress: phase)
  }

  @Test("at rest every column is the string, undimmed")
  func restIsThePlainString() {
    let value = TextRollValue(text: "41", transition: Self.numeric)
    #expect(!value.isRolling)
    #expect(value.renderedColumns() == [.init(character: "4", opacity: 1), .init(character: "1", opacity: 1)])
  }

  @Test("a one-step digit swaps at the midpoint and dips there")
  func oneStepDigitSwapsAtTheMidpoint() {
    #expect(Self.roll("41", "42", phase: 0).renderedColumns().map(\.character) == ["4", "1"])
    let quarter = Self.roll("41", "42", phase: 0.25).renderedColumns()
    #expect(quarter.map(\.character) == ["4", "1"])
    #expect(quarter.map(\.opacity) == [1, 0.75])
    let half = Self.roll("41", "42", phase: 0.5).renderedColumns()
    #expect(half.map(\.character) == ["4", "2"])
    #expect(half.map(\.opacity) == [1, 0.5])
    let done = Self.roll("41", "42", phase: 1)
    #expect(!done.isRolling)
    #expect(done.renderedColumns().map(\.character) == ["4", "2"])
  }

  @Test("digits count through the intermediates upward, and downward with countsDown")
  func digitsStepThroughTheIntermediates() {
    let up = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0].map {
      Self.roll("7", "0", phase: $0).renderedText
    }
    #expect(up == ["7", "8", "8", "9", "9", "0"])
    let down = [0.0, 0.25, 0.5, 0.75, 1.0].map {
      Self.roll("7", "0", Self.numericDown, phase: $0).renderedText
    }
    #expect(down == ["7", "5", "3", "2", "0"])
  }

  @Test("a length change pairs the region right-aligned and fades the added column in")
  func lengthChangeFadesTheAddedColumnIn() {
    let half = Self.roll("99", "100", phase: 0.5).renderedColumns()
    #expect(half.map(\.character) == ["1", "0", "0"])
    #expect(half.map(\.opacity) == [0.5, 0.5, 0.5])
    let early = Self.roll("99", "100", phase: 0.1).renderedColumns()
    #expect(early.map(\.character) == ["1", "9", "9"])
    #expect(early[0].opacity == 0.1)
    // Dropping a column: the vanished leading digit is simply not drawn.
    let shrink = Self.roll("10", "9", Self.numericDown, phase: 0.75).renderedColumns()
    #expect(shrink.map(\.character) == ["9"])
  }

  @Test("common prefix and suffix are untouched; a same-width non-digit cross-fades")
  func nonDigitColumnsCrossFade() {
    let quarter = Self.roll("Score: 1,5 pts", "Score: 2.5 pts", phase: 0.25).renderedColumns()
    #expect(String(quarter.map(\.character)) == "Score: 1,5 pts")
    #expect(quarter.prefix(7).allSatisfy { $0.opacity == 1 })
    #expect(quarter[7].opacity == 0.75)
    #expect(quarter[8].opacity == 0.5)
    #expect(quarter.suffix(5).allSatisfy { $0.opacity == 1 })
    let late = Self.roll("Score: 1,5 pts", "Score: 2.5 pts", phase: 0.75).renderedColumns()
    #expect(String(late.map(\.character)) == "Score: 2.5 pts")
    #expect(late[8].opacity == 0.5)
  }

  @Test("a glyph whose width may differ keeps the new string's layout and fades in")
  func widthUnsafeGlyphFadesTheNewGlyphIn() {
    let early = Self.roll("é1", "e2", phase: 0.2).renderedColumns()
    #expect(early.map(\.character) == ["e", "1"])
    #expect(early[0].opacity == 0.2)
  }

  @Test("opacity dims the whole old string out, then the whole new string in")
  func opacityCrossFadesTheWholeString() {
    let early = Self.roll("41", "420", Self.opacity, phase: 0.25).renderedColumns()
    #expect(early.map(\.character) == ["4", "1"])
    #expect(early.map(\.opacity) == [0.5, 0.5])
    let late = Self.roll("41", "420", Self.opacity, phase: 0.75).renderedColumns()
    #expect(late.map(\.character) == ["4", "2", "0"])
    #expect(late.map(\.opacity) == [0.5, 0.5, 0.5])
  }

  @Test("a retarget rolls on from the digit on screen")
  func retargetContinuesFromTheDisplayedDigit() {
    let midFlight = Self.roll("7", "0", phase: 0.4)  // showing "8"
    #expect(midFlight.renderedText == "8")
    let retargeted = midFlight.rolling(to: TextRollValue(text: "5", transition: Self.numeric), progress: 0)
    #expect(retargeted.previous == "8")
    #expect(retargeted.text == "5")
    #expect(retargeted.renderedText == "8")
    #expect(retargeted.rolling(to: retargeted, progress: 0).previous == "8")
  }

  @Test("numericText(value:) takes its direction from the change in value")
  func valueFormPicksTheDirection() {
    let from = TextRollValue(text: "7", transition: .init(kind: .numericText, value: 7))
    let down = from.rolling(to: .init(text: "0", transition: .init(kind: .numericText, value: 0)), progress: 0.5)
    #expect(down.countsDown)
    #expect(down.renderedText == "3")
    let up = from.rolling(to: .init(text: "0", transition: .init(kind: .numericText, value: 10)), progress: 0.5)
    #expect(!up.countsDown)
    #expect(up.renderedText == "9")
  }

  @Test("equality ignores the transition's value and direction")
  func equalityIsOnTheStringsAndPhase() {
    let a = TextRollValue(text: "7", transition: .init(kind: .numericText, value: 7))
    let b = TextRollValue(text: "7", transition: .init(kind: .numericText, value: 8))
    let c = TextRollValue(text: "7", transition: Self.numericDown)
    #expect(a == b)
    #expect(a == c)
    #expect(a != TextRollValue(text: "8", transition: Self.numeric))
  }

  @Test("progress outside the unit interval clamps")
  func progressClamps() {
    #expect(Self.roll("41", "42", phase: 1.3).phase == 1)
    #expect(Self.roll("41", "42", phase: -0.2).phase == 0)
    #expect(Self.roll("41", "42", phase: .nan).phase == 1)
  }

  @Test("draw extraction groups columns by opacity and multiplies the run style")
  func renderingGroupsColumnsByOpacity() {
    let roll = Self.roll("Score: 99", "Score: 100", phase: 0.5)
    let payload = TextRollRendering.payload(
      for: roll,
      style: TextStyle(emphasis: .bold, opacity: 0.8)
    )
    #expect(payload.runs.map(\.text) == ["Score: ", "100"])
    #expect(payload.runs.map(\.style.opacity) == [0.8, 0.4])
    #expect(payload.runs.allSatisfy { $0.style.emphasis == .bold })
    #expect(payload.visibleText == "Score: 100")
  }
}
