import Testing

@testable import SwiftTUICore

@Test("TileStyle stores pattern, foreground, and optional background")
func tileStyleStoresFields() {
  let style = TileStyle(.lightShade, foreground: .red, background: .black)
  #expect(style.pattern == .lightShade)
  #expect(style.foreground.style == .color(.red))
  #expect(style.background?.style == .color(.black))
}

@Test("TileStyle default pattern is checker shade and background is nil")
func tileStyleDefaultPattern() {
  let style = TileStyle(foreground: .white)
  #expect(style.pattern == .checkerShade)
  #expect(style.background == nil)
}

@Test("TileStyle accepts terminal chrome foreground styles")
func tileStyleAcceptsTerminalChromeForeground() {
  let style = TileStyle(foreground: .terminalTile(.info))
  #expect(style.pattern == .checkerShade)
  #expect(style.foreground.style == .terminalChrome(.init(.tile(tone: .info))))
}

@Test("TileStyle erases to .tileStyle AnyShapeStyle")
func tileStyleErases() {
  let style = TileStyle(.mediumShade, foreground: .blue)
  let any = AnyShapeStyle(style)
  if case .tileStyle(let inner) = any {
    #expect(inner.pattern == .mediumShade)
  } else {
    Issue.record("expected .tileStyle case")
  }
}

@Test("TileStyle.Pattern.checkerShade uses the canonical default tile pattern")
func tileStyleCheckerShade() {
  #expect(TileStyle.Pattern.checkerShade.character(atX: 0, y: 0) == "░")
  #expect(TileStyle.Pattern.checkerShade.character(atX: 1, y: 0) == "▒")
  #expect(TileStyle.Pattern.checkerShade.character(atX: 0, y: 1) == "▒")
  #expect(TileStyle.Pattern.checkerShade.character(atX: 1, y: 1) == "░")
}

@Test("TileStyle.Pattern shade and dot presets use expected glyphs")
func tileStylePatternPresets() {
  #expect(TileStyle.Pattern.lightShade.character(atX: 0, y: 0) == "░")
  #expect(TileStyle.Pattern.mediumShade.character(atX: 0, y: 0) == "▒")
  #expect(TileStyle.Pattern.heavyShade.character(atX: 0, y: 0) == "▓")
  #expect(TileStyle.Pattern.dots.character(atX: 0, y: 0) == "·")
}

@Test("TileStyle is Equatable")
func tileStyleEquatable() {
  let a = TileStyle(.lightShade, foreground: .red)
  let b = TileStyle(.lightShade, foreground: .red)
  let c = TileStyle(.mediumShade, foreground: .red)
  let d = TileStyle(.lightShade, foreground: .blue)
  #expect(a == b)
  #expect(a != c)
  #expect(a != d)
}

@Test("TileStyle opacity fades foreground and background")
func tileStyleOpacity() {
  let style = TileStyle(.lightShade, foreground: .red, background: .black)
  let faded = style.opacity(0.5)
  if case .tileStyle(let inner) = faded {
    if case .color(let foreground) = inner.foreground.style {
      #expect(foreground.alpha < 1)
    } else {
      Issue.record("expected faded foreground to remain a color")
    }

    if case .color(let background) = inner.background?.style {
      #expect(background.alpha < 1)
    } else {
      Issue.record("expected faded background to remain a color")
    }

    #expect(inner.pattern == .lightShade)
  } else {
    Issue.record("expected .tileStyle case")
  }
}

@Test("TileStyle accepts a linear gradient as its foreground paint")
func tileStyleLinearGradientForeground() {
  let gradient = LinearGradient(
    colors: [.red, .blue],
    startPoint: .leading,
    endPoint: .trailing
  )
  let style = TileStyle(.lightShade, foreground: gradient)
  #expect(style.foreground.style == .linearGradient(gradient))
  #expect(style.background == nil)
  #expect(style.foreground.representativeColor == .red)
}

@Test("TileStyle accepts a radial gradient as its background paint")
func tileStyleRadialGradientBackground() {
  let background = RadialGradient(
    colors: [.black, .white],
    center: .center,
    startRadius: 0,
    endRadius: 10
  )
  let style = TileStyle(
    .mediumShade,
    foreground: .red,
    background: background
  )
  #expect(style.foreground.style == .color(.red))
  #expect(style.background?.style == .radialGradient(background))
  #expect(style.background?.representativeColor == .black)
}

@Test("TileStyle.Paint opacity fades gradient stops uniformly")
func tileStylePaintOpacityFadesGradient() {
  let gradient = LinearGradient(
    colors: [.red, .blue],
    startPoint: .leading,
    endPoint: .trailing
  )
  let faded = TileStyle.Paint(gradient).opacity(0.5)
  if case .linearGradient(let out) = faded.style {
    #expect(out.gradient.stops.count == 2)
    for stop in out.gradient.stops {
      #expect(stop.color.alpha < 1)
    }
  } else {
    Issue.record("expected faded paint to remain a linear gradient")
  }
}
