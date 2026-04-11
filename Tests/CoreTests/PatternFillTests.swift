import Testing

@testable import Core

@Test("PatternFill stores glyph, foreground, and optional background")
func patternFillStoresFields() {
  let p = PatternFill(glyph: "░", foreground: .red, background: .black)
  #expect(p.glyph == "░")
  #expect(p.foreground == .red)
  #expect(p.background == .black)
}

@Test("PatternFill default background is nil")
func patternFillDefaultBackground() {
  let p = PatternFill(glyph: "·", foreground: .white)
  #expect(p.background == nil)
}

@Test("PatternFill erases to .patternFill AnyShapeStyle")
func patternFillErases() {
  let p = PatternFill(glyph: "▒", foreground: .blue)
  let any = AnyShapeStyle(p)
  if case .patternFill(let inner) = any {
    #expect(inner.glyph == "▒")
  } else {
    Issue.record("expected .patternFill case")
  }
}

@Test("PatternFill.lightShade uses U+2591")
func patternFillLightShade() {
  #expect(PatternFill.lightShade.glyph == "░")
}

@Test("PatternFill.mediumShade uses U+2592")
func patternFillMediumShade() {
  #expect(PatternFill.mediumShade.glyph == "▒")
}

@Test("PatternFill.heavyShade uses U+2593")
func patternFillHeavyShade() {
  #expect(PatternFill.heavyShade.glyph == "▓")
}

@Test("PatternFill.dots uses ·")
func patternFillDots() {
  #expect(PatternFill.dots.glyph == "·")
}

@Test("PatternFill is Equatable")
func patternFillEquatable() {
  let a = PatternFill(glyph: "░", foreground: .red)
  let b = PatternFill(glyph: "░", foreground: .red)
  let c = PatternFill(glyph: "▒", foreground: .red)
  let d = PatternFill(glyph: "░", foreground: .blue)
  #expect(a == b)
  #expect(a != c)
  #expect(a != d)
}

@Test("PatternFill opacity fades foreground and background")
func patternFillOpacity() {
  let p = PatternFill(glyph: "░", foreground: .red, background: .black)
  let faded = p.opacity(0.5)
  if case .patternFill(let inner) = faded {
    // Foreground should have alpha < 1 after fading.
    #expect(inner.foreground.alpha < 1)
    // Background was non-nil and should also be faded.
    #expect(inner.background != nil)
    #expect((inner.background?.alpha ?? 1) < 1)
    // Glyph is preserved.
    #expect(inner.glyph == "░")
  } else {
    Issue.record("expected .patternFill case")
  }
}
