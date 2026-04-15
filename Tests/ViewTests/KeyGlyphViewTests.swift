import Testing

@testable import Core
@testable import View

@Suite
struct KeyGlyphViewTests {
  @Test("unmodified character renders as lowercase in brackets")
  func unmodifiedCharacterIsLowercase() {
    #expect(keyDisplayString(for: KeyPress(.character("s"))) == "[s]")
    #expect(keyDisplayString(for: KeyPress(.character("S"))) == "[s]")
  }

  @Test("ctrl+character uppercases the character with caret prefix")
  func ctrlCharacterUsesCaretPrefix() {
    #expect(keyDisplayString(for: .ctrl("s")) == "[^S]")
    #expect(keyDisplayString(for: .ctrl("q")) == "[^Q]")
  }

  @Test("alt+character uppercases the character with option symbol prefix")
  func altCharacterUsesOptionSymbol() {
    #expect(keyDisplayString(for: .alt("x")) == "[\u{2325}X]")
  }

  @Test("shift+character uppercases with shift symbol prefix")
  func shiftCharacterUsesShiftSymbol() {
    #expect(keyDisplayString(for: .shift("a")) == "[\u{21E7}A]")
  }

  @Test("modifiers stack ctrl → alt → shift in that order")
  func modifierStackingOrder() {
    let key = KeyPress(.character("a"), modifiers: [.ctrl, .shift])
    #expect(keyDisplayString(for: key) == "[^\u{21E7}A]")

    let all = KeyPress(.character("a"), modifiers: [.ctrl, .alt, .shift])
    #expect(keyDisplayString(for: all) == "[^\u{2325}\u{21E7}A]")
  }

  @Test("escape renders as [Esc]")
  func escapeRenders() {
    #expect(keyDisplayString(for: .escape) == "[Esc]")
  }

  @Test("return renders as the enter glyph")
  func returnRenders() {
    #expect(keyDisplayString(for: .return) == "[\u{23CE}]")
  }

  @Test("space and tab use their word names")
  func spaceAndTabUseWords() {
    #expect(keyDisplayString(for: .space) == "[Space]")
    #expect(keyDisplayString(for: .tab) == "[Tab]")
  }

  @Test("arrows use the unicode arrow glyphs")
  func arrowsUseGlyphs() {
    #expect(keyDisplayString(for: KeyPress(.arrowLeft)) == "[\u{2190}]")
    #expect(keyDisplayString(for: KeyPress(.arrowRight)) == "[\u{2192}]")
    #expect(keyDisplayString(for: KeyPress(.arrowUp)) == "[\u{2191}]")
    #expect(keyDisplayString(for: KeyPress(.arrowDown)) == "[\u{2193}]")
  }

  @Test("home and end spell out their names")
  func homeAndEndSpellOut() {
    #expect(keyDisplayString(for: KeyPress(.home)) == "[Home]")
    #expect(keyDisplayString(for: KeyPress(.end)) == "[End]")
  }

  @Test("backspace uses the erase-left glyph")
  func backspaceGlyph() {
    #expect(keyDisplayString(for: KeyPress(.backspace)) == "[\u{232B}]")
  }

  @Test("modified named keys combine modifier prefix with the key label")
  func modifiedNamedKey() {
    let ctrlEscape = KeyPress(.escape, modifiers: .ctrl)
    #expect(keyDisplayString(for: ctrlEscape) == "[^Esc]")

    let shiftTab = KeyPress(.tab, modifiers: .shift)
    #expect(keyDisplayString(for: shiftTab) == "[\u{21E7}Tab]")
  }
}
