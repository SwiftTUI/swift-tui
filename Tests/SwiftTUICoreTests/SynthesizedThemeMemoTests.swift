import Testing

@_spi(Testing) @testable import SwiftTUICore

/// F152 — `synthesizedTheme()` is memoized on appearance value equality
/// (single slot). These tests pin the memo contract: repeated calls stay
/// stable, distinct appearances never see each other's themes (including
/// under alternation, which evicts the single slot every call), and any
/// field edit re-derives.
@Suite
struct SynthesizedThemeMemoTests {
  private static let light = TerminalAppearance(
    foregroundColor: try! Color(hex: "#20242C"),
    backgroundColor: try! Color(hex: "#F4F1EC"),
    tintColor: .blue,
    source: .activeQuery
  )

  @Test("repeated synthesis of one appearance is stable")
  func repeatedSynthesisIsStable() {
    let appearance = TerminalAppearance.fallback
    let first = appearance.synthesizedTheme()
    let second = appearance.synthesizedTheme()
    #expect(first == second)
  }

  @Test("alternating appearances each keep their own theme")
  func alternatingAppearancesKeepDistinctThemes() {
    let dark = TerminalAppearance.fallback
    let light = Self.light

    let darkFirst = dark.synthesizedTheme()
    let lightFirst = light.synthesizedTheme()
    // Alternate again: each call evicts the other's slot, so a stale hit
    // would surface here as the wrong theme.
    let darkSecond = dark.synthesizedTheme()
    let lightSecond = light.synthesizedTheme()

    #expect(darkFirst == darkSecond)
    #expect(lightFirst == lightSecond)
    #expect(darkFirst != lightFirst)
    #expect(darkFirst.background == dark.backgroundColor)
    #expect(lightFirst.background == light.backgroundColor)
  }

  @Test("editing any appearance field re-derives the theme")
  func fieldEditReDerives() {
    let base = TerminalAppearance.fallback
    let baseTheme = base.synthesizedTheme()

    var recolored = base
    recolored.backgroundColor = try! Color(hex: "#101418")
    let recoloredTheme = recolored.synthesizedTheme()

    #expect(recoloredTheme != baseTheme)
    #expect(recoloredTheme.background == recolored.backgroundColor)
    // The original appearance still resolves to its own theme after the
    // edit displaced it from the slot.
    #expect(base.synthesizedTheme() == baseTheme)
  }
}
