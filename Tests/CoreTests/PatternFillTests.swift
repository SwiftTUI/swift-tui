import Testing

@testable import Core

@Test("PatternFill stores glyph, foreground, and optional background")
func patternFillStoresFields() {
  let p = PatternFill(glyph: "░", foreground: .red, background: .black)
  #expect(p.glyph == "░")
  #expect(p.foreground == .color(.red))
  #expect(p.background == .color(.black))
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
    #expect((inner.foreground.representativeColor?.alpha ?? 1) < 1)
    // Background was non-nil and should also be faded.
    #expect(inner.background != nil)
    #expect((inner.background?.representativeColor?.alpha ?? 1) < 1)
    // Glyph is preserved.
    #expect(inner.glyph == "░")
  } else {
    Issue.record("expected .patternFill case")
  }
}

@Test("PatternFill accepts a linear gradient as its foreground paint")
func patternFillLinearGradientForeground() {
  let gradient = LinearGradient(
    colors: [.red, .blue],
    startPoint: .leading,
    endPoint: .trailing
  )
  let p = PatternFill(
    glyph: "░",
    foreground: .linearGradient(gradient)
  )
  #expect(p.foreground == .linearGradient(gradient))
  #expect(p.background == nil)
  // The representative color is the first stop.
  #expect(p.foreground.representativeColor == .red)
}

@Test("PatternFill accepts a radial gradient as its background paint")
func patternFillRadialGradientBackground() {
  let bg = RadialGradient(
    colors: [.black, .white],
    center: .center,
    startRadius: 0,
    endRadius: 10
  )
  let p = PatternFill(
    glyph: "▒",
    foreground: .color(.red),
    background: .radialGradient(bg)
  )
  #expect(p.foreground == .color(.red))
  #expect(p.background == .radialGradient(bg))
  #expect(p.background?.representativeColor == .black)
}

@Test("PatternFill.Paint.opacity fades gradient stops uniformly")
func patternFillPaintOpacityFadesGradient() {
  let gradient = LinearGradient(
    colors: [.red, .blue],
    startPoint: .leading,
    endPoint: .trailing
  )
  let faded = PatternFill.Paint.linearGradient(gradient).opacity(0.5)
  if case .linearGradient(let out) = faded {
    #expect(out.gradient.stops.count == 2)
    for stop in out.gradient.stops {
      #expect(stop.color.alpha < 1)
    }
  } else {
    Issue.record("expected faded paint to remain a linear gradient")
  }
}
