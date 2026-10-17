import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIPrimitives
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetAColorPaintBoundaryTests {
  @Test func setA676ShortHexFormattingHonorsExplicitUppercase() throws {
    // Hypothesis: the nibble formatter bypasses the letter-case conversion used by byte formats.
    let color = try Color(hex: "#ABCDEF88")
    #expect(color.hexString(format: .rrggbbaa) == "#ABCDEF88")
    #expect(color.hexString(format: .rgba, letterCase: .lowercase) == "#ace8")
    do {
      #expect(color.hexString(format: .rgba, letterCase: .uppercase) == "#ACE8")
    }
  }

  @Test func setA677CustomProfileWithABuiltinNameSurvivesColorCoding() throws {
    // Hypothesis: serialization recognizes a profile by name alone and silently replaces its transfer curve.
    let custom = RGBColorProfile(
      name: "sRGB", primaries: RGBColorProfile.sRGB.primaries,
      whitePoint: .d65, transferFunction: .gamma(1.7))
    let source = Color(red: 0.2, green: 0.6, blue: 0.8, alpha: 0.4, profile: custom)
    let decoded = try JSONDecoder().decode(Color.self, from: JSONEncoder().encode(source))
    #expect(decoded == source)
    #expect(decoded.profile != .sRGB)
    #expect(abs(decoded.xyz().y - source.xyz().y) < 1e-12)
  }

  @Test func setA678UnknownColorSchemaIsRejectedBeforeReadingItsPayload() {
    // Hypothesis: unknown versions fall through into today's payload interpretation or get silently accepted.
    let data = Data(
      #"{"schemaVersion":2,"profile":"sRGB","red":0,"green":0,"blue":0,"alpha":1}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Color.self, from: data) }
  }

  @Test func setA679InvalidDecodedWhitePointThrowsInsteadOfTerminatingTheProcess() async {
    // Hypothesis: a throwing Codable initializer sends malformed external values into a trapping value initializer.
    do {
      await #expect(processExitsWith: .success) {
        let data = Data(#"{"name":"external","x":0,"y":0.3}"#.utf8)
        do {
          _ = try JSONDecoder().decode(ReferenceWhite.self, from: data)
          Issue.record("Invalid chromaticity was accepted")
        } catch is DecodingError {
        } catch {
          Issue.record("Expected a decoding error, got \(error)")
        }
      }
    }
  }

  @Test func setA680TransferFunctionsPreserveNegativeExtendedChannelsAtTheirToes() {
    // Hypothesis: an unsigned nonlinear branch turns negative extended-gamut components into NaN or positive channels.
    for curve in [TransferFunction.sRGB, .rec2020, .proPhotoRGB, .gamma(2.2)] {
      for value in [-0.00001, -0.018, -0.4, -1.2] {
        let encoded = curve.encode(value)
        #expect(encoded < 0 && encoded.isFinite)
        #expect(abs(curve.decode(encoded) - value) < 1e-8)
        #expect(abs(encoded + curve.encode(-value)) < 1e-12)
      }
    }
  }

  @Test func setA681IntegerPowerAcceptsTheNegativeRepresentableOverflowBoundary() {
    // Hypothesis: overflow checks reject Int.min because its positive magnitude is not representable.
    #expect(SwiftTUIPrimitives.pow(-2, Int.bitWidth - 1) == Int.min)
    #expect(SwiftTUIPrimitives.pow(2, Int.bitWidth - 1) == nil)
    #expect(SwiftTUIPrimitives.pow(Int.min, 1) == Int.min)
  }

  @Test func setA682MissingHueBorrowsItsChromaticPeerAcrossWrappedAngles() {
    // Hypothesis: an achromatic endpoint invents hue zero or retains unnormalized degrees in polar interpolation.
    #expect(interpolateHue(from: nil, to: -725, t: 0.25, path: .longest) == 355)
    #expect(interpolateHue(from: 1085, to: nil, t: 0.75, path: .decreasing) == 5)
    #expect(interpolateHue(from: nil, to: nil, t: 0.5, path: .shortest) == nil)
    #expect(interpolateHue(from: 350, to: 10, t: 0.5, path: .shortest) == 0)
  }

  @Test func setA683CIEDE2000DistanceIsSymmetricAcrossTheHueDiscontinuity() {
    // Hypothesis: hue-average branch selection makes reversing the compared colors change the distance.
    let a = LabColor(l: 49, a: -0.001, b: 2.49, whitePoint: .d50)
    let b = LabColor(l: 53, a: 0.0009, b: -2.49, whitePoint: .d50)
    let forward = _deltaE2000(a, b)
    #expect(forward > 0)
    #expect(abs(forward - _deltaE2000(b, a)) < 1e-12)
    #expect(_deltaE2000(a, a) == 0)
  }

  @Test func setA684BlendModesCannotColorizeAFullyTransparentBackdrop() {
    // Hypothesis: nonlinear blend terms retain the invisible backdrop's RGB even when its alpha is zero.
    let foreground = Color(red: 0.2, green: 0.6, blue: 0.3, alpha: 0.4)
    let transparent = Color(red: 0.9, green: 0.1, blue: 0.8, alpha: 0)
    for mode in [BlendMode.multiply, .screen, .overlay, .darken, .lighten] {
      let result = foreground.composited(over: transparent, mode: mode)
      #expect(result.deltaE(to: foreground) < 1e-8)
      #expect(result.alpha == foreground.alpha)
    }
  }

  @Test func setA685FiniteSemanticOpacityCompositionDoesNotExhaustAliasRecursion() throws {
    // Hypothesis: the semantic-alias recursion guard counts ordinary opacity wrappers and erases a valid finite paint.
    var environment = StyleEnvironmentSnapshot()
    environment.tintStyle = .color(.red)
    let shallow = sample(.semantic(.tint).opacity(0.5), environment: environment)
    #expect(try #require(shallow).alpha == 0.5)
    var style = AnyShapeStyle.semantic(.tint)
    for _ in 0..<10 { style = style.opacity(0.5) }
    let result = sample(style, environment: environment)
    do {
      #expect(result != nil)
    }
    if let result { #expect(abs(result.alpha - 1.0 / 1024) < 1e-12) }
  }

  @Test func setA686ReversingLinearGradientGeometryMirrorsEveryCellCenter() throws {
    // Hypothesis: direction reversal samples edges rather than cell centers and shifts the mirrored gradient by one cell.
    let forward = LinearGradient(
      colors: [.red, .green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    let reverse = LinearGradient(
      colors: [.red, .green, .blue], startPoint: .bottomTrailing, endPoint: .topLeading)
    let bounds = rect(x: 7, y: 3, width: 9, height: 5)
    for y in 0..<5 {
      for x in 0..<9 {
        let a = try #require(Rasterizer().sample(forward, in: bounds, x: 7 + x, y: 3 + y))
        let b = try #require(Rasterizer().sample(reverse, in: bounds, x: 15 - x, y: 7 - y))
        #expect(a.deltaE(to: b) < 1e-7)
      }
    }
  }

  @Test func setA687CoincidentGradientStopsKeepAHardTransitionWithoutNaN() throws {
    // Hypothesis: zero-length adjacent stop intervals smear or poison the two sides of an authored hard edge.
    let gradient = LinearGradient(
      gradient: .init(stops: [
        .init(color: .red, location: 0), .init(color: .red, location: 0.5),
        .init(color: .blue, location: 0.5), .init(color: .blue, location: 1),
      ]), startPoint: .leading, endPoint: .trailing)
    let bounds = rect(width: 10, height: 1)
    let left = try #require(Rasterizer().sample(gradient, in: bounds, x: 4, y: 0))
    let right = try #require(Rasterizer().sample(gradient, in: bounds, x: 5, y: 0))
    #expect(left.deltaE(to: .red) < 1e-7)
    #expect(right.deltaE(to: .blue) < 1e-7)
  }

  @Test func setA688RadialSegmentHintsRecoverAfterNonmonotoneSampleOrder() {
    // Hypothesis: a mutable segment cursor assumes raster-monotone distance and serves an old interval after moving inward.
    let gradient = RadialGradient(
      gradient: .init(stops: [
        .init(color: .clear, location: 0), .init(color: .red, location: 0.2),
        .init(color: .green, location: 0.6), .init(color: .clear, location: 1),
      ]), center: .center, startRadius: 0, endRadius: 10)
    let bounds = rect(width: 21, height: 11)
    let prepared = PreparedRadialGradient(gradient, aspectRatio: 2, bounds: bounds)
    var hint = 0
    for x in [20, 10, 16, 11, 0, 14, 9] {
      let result = prepared.color(atCellX: x, y: 5, segmentHint: &hint)
      #expect(result == Rasterizer().sample(gradient, in: bounds, aspectRatio: 2, x: x, y: 5))
    }
  }

  @Test func setA689NegativeMultiTurnAngularSweepKeepsItsWholeSpanLocation() {
    // Hypothesis: selecting the last clockwise/counter-clockwise turn loses the preceding full-turn fraction.
    let gradient = AngularGradient(
      colors: [.red, .blue], startAngle: .zero, endAngle: .degrees(-720))
    #expect(abs(gradient.location(atAngle: -.pi / 2) - 0.625) < 1e-12)
    #expect(abs(gradient.location(atAngle: .pi / 2) - 0.875) < 1e-12)
    #expect(abs(gradient.location(atAngle: 3 * .pi / 2) - 0.625) < 1e-12)
  }

  @Test func setA690TransposingAMeshPreservesItsCorrespondingSampleColors() {
    // Hypothesis: patch row/column indexing or derivative directions are not transposed with rectangular surface geometry.
    let colors: [Color] = [.red, .green, .blue, .white]
    let a = PreparedMeshGradient(input: meshInput(colors), bounds: rect(width: 7, height: 3))
    let b = PreparedMeshGradient(
      input: meshInput([colors[0], colors[2], colors[1], colors[3]]),
      bounds: rect(width: 3, height: 7))
    for y in 0..<3 {
      for x in 0..<7 {
        #expect(a.color(atCellX: x, y: y).deltaE(to: b.color(atCellX: y, y: x)) < 1e-6)
      }
    }
  }

  @Test func setA691MeshOpacityFadesItsUncoveredBackgroundAsWellAsControls() throws {
    // Hypothesis: fading a mesh forgets the fallback paint outside its deformed control surface.
    let mesh = MeshGradient(
      width: 2, height: 2,
      points: [.init(0.4, 0.4), .init(0.6, 0.4), .init(0.4, 0.6), .init(0.6, 0.6)],
      colors: Array(repeating: .red, count: 4), background: .blue.opacity(0.8), smoothsColors: false
    )
    let result = try #require(sample(AnyShapeStyle(mesh).opacity(0.25)))
    #expect(abs(result.alpha - 0.2) < 1e-12)
    #expect(result.blue > result.red)
    #expect(mesh.background.alpha == 0.8)
  }

  @Test func setA692MeshCacheSeparatesSameNamedColorProfilesWithDifferentCurves() {
    // Hypothesis: cache keys use the Identifiable profile name and alias different color transfer functions.
    let base = RGBColorProfile.sRGB
    let alternate = RGBColorProfile(
      name: base.name, primaries: base.primaries,
      whitePoint: base.whitePoint, transferFunction: .linear)
    let cache = PreparedMeshGradientCache()
    let bounds = rect(width: 3, height: 3)
    let a = meshInput(Array(repeating: Color(white: 0.5, profile: base), count: 4))
    let b = meshInput(Array(repeating: Color(white: 0.5, profile: alternate), count: 4))
    let first = cache.prepared(for: a, bounds: bounds).color(atCellX: 1, y: 1)
    let second = cache.prepared(for: b, bounds: bounds).color(atCellX: 1, y: 1)
    #expect(first.profile == base && second.profile == alternate)
    #expect(first.deltaE(to: second) > 0.1)
    #expect(cache.metrics.entries == 2)
  }

  @Test func setA693TileWrappingAcceptsTheMostNegativeIntegerCoordinate() {
    // Hypothesis: wrapping negates a negative coordinate and overflows on Int.min before choosing a tile cell.
    let pattern = TileStyle.Pattern(rows: ["abc", "def"])
    #expect(pattern.character(atX: Int.min, y: Int.min) == "b")
    #expect(pattern.character(atX: -1, y: -1) == "f")
    #expect(pattern.character(atX: 3, y: 2) == "a")
  }

  @Test func setA694TileCoordinatesRestartAtTheTranslatedShapeOrigin() {
    // Hypothesis: global surface coordinates phase-shift a tile when the filled shape moves by a non-periodic offset.
    let tile = TileStyle(.init(rows: ["abc", "def"]), foreground: Color.white)
    let local = render(Rectangle().fill(tile).frame(width: 6, height: 2), width: 6, height: 2)
    let shifted = render(
      HStack(spacing: 2) {
        Text("XX").frame(width: 2, height: 2)
        Rectangle().fill(tile).frame(width: 6, height: 2)
      }, width: 10, height: 2)
    #expect(
      shifted.cells.map { Array($0.dropFirst(4)).map(\.character) }
        == local.cells.map { $0.map(\.character) })
    #expect(local.lines == ["abcabc", "defdef"])
  }

  @Test func setA695FullyTransparentTileCannotReplaceUnderlyingTextGlyphs() {
    // Hypothesis: tile painting skips alpha compositing and overwrites glyphs even when both paints are invisible.
    let surface = render(
      ZStack {
        Text("underlay")
        Rectangle().fill(
          TileStyle(.dots, foreground: Color.red.opacity(0), background: Color.blue.opacity(0)))
      }, width: 8, height: 1)
    let zeroOpacity = render(
      ZStack {
        Text("underlay")
        Rectangle().fill(TileStyle(.dots, foreground: Color.red, background: Color.blue)).opacity(0)
      }, width: 8, height: 1)
    #expect(zeroOpacity.lines == ["underlay"])
    do {
      #expect(surface.lines == ["underlay"])
    }
  }

  @Test func setA696TileForegroundAndBackgroundKeepIndependentGradientAxes() throws {
    // Hypothesis: resolving both tile paints reuses one gradient's geometry or sampling direction for the other.
    let foreground = LinearGradient(
      colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    let background = LinearGradient(colors: [.black, .white], startPoint: .top, endPoint: .bottom)
    let surface = render(
      Rectangle().fill(TileStyle(.dots, foreground: foreground, background: background)), width: 6,
      height: 4)
    let tl = try #require(surface.cells[0][0].style)
    let tr = try #require(surface.cells[0][5].style)
    let bl = try #require(surface.cells[3][0].style)
    #expect(tl.foregroundColor != tr.foregroundColor)
    #expect(tl.foregroundColor == bl.foregroundColor)
    #expect(tl.backgroundColor == tr.backgroundColor)
    #expect(tl.backgroundColor != bl.backgroundColor)
  }

  @Test func setA697ReducedTransparencyPreservesAnExactlyClearGradientEndpoint() throws {
    // Hypothesis: an opaque accessibility wrapper turns the gradient's intentionally empty support into visible paint.
    var environment = StyleEnvironmentSnapshot()
    environment.accessibilityPreferences.reduceTransparency = true
    let gradient = LinearGradient(
      gradient: .init(stops: [
        .init(color: .clear, location: 0.25), .init(color: .red.opacity(0.2), location: 0.75),
      ]), startPoint: .leading, endPoint: .trailing)
    let mode = Rasterizer().resolvedColorMode(
      from: .linearGradient(gradient), environment: environment, bounds: rect(width: 4, height: 1))
    let clear = try #require(
      Rasterizer().resolveColor(
        from: mode, bounds: rect(width: 4, height: 1), sampleX: 0, sampleY: 0))
    let visible = try #require(
      Rasterizer().resolveColor(
        from: mode, bounds: rect(width: 4, height: 1), sampleX: 3, sampleY: 0))
    #expect(clear.alpha == 0)
    #expect(visible.alpha == 1)
  }

  @Test func setA698SemanticForegroundRedirectsThroughTheCurrentTintOverride() throws {
    // Hypothesis: a semantic-to-semantic alias falls back to the theme without consulting the destination role's override.
    var environment = StyleEnvironmentSnapshot()
    environment.foregroundStyle = .semantic(.tint)
    environment.tintStyle = .color(.green)
    #expect(try #require(sample(.semantic(.foreground), environment: environment)) == .green)
    environment.tintStyle = .color(.blue)
    #expect(try #require(sample(.semantic(.foreground), environment: environment)) == .blue)
  }

  @Test func setA699CompositingGroupRestoresTheFollowingSiblingsBlendContext() throws {
    // Hypothesis: exiting a compositing group leaks its outer blend mode into a following sibling.
    let red = Color(red: 1, green: 0, blue: 0)
    let yellow = Color(red: 1, green: 1, blue: 0)
    let blue = Color(red: 0, green: 0, blue: 1)
    let surface = render(
      ZStack(alignment: .topLeading) {
        Rectangle().fill(yellow)
        HStack(spacing: 0) {
          Rectangle().fill(red).compositingGroup().blendMode(.multiply).frame(
            width: 3, height: 2)
          Rectangle().fill(blue).frame(width: 3, height: 2)
        }
      }, width: 6, height: 2)
    let grouped = try #require(surface.cells[0][0].style?.backgroundColor)
    let sibling = try #require(surface.cells[0][4].style?.backgroundColor)
    #expect(grouped.deltaE(to: red) < 1e-7)
    #expect(sibling.deltaE(to: blue) < 1e-7)
  }

  @Test func setA700LiveGradientMutationInvalidatesItsRetainedPaintWithoutGeometryChange() throws {
    // Hypothesis: changing a gradient endpoint at fixed bounds is ignored by retained draw/raster reuse.
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetA700"), size: .init(width: 20, height: 4)
    ) {
      SetAColorGradientRoot()
    }
    defer { h.shutdown() }
    let before = try gradientColors(h)
    try h.clickText("Reverse paint")
    let after = try gradientColors(h)
    #expect(before != after)
    try h.clickText("Reverse paint")
    #expect(try gradientColors(h) == before)
  }

  private func gradientColors(_ h: StressRuntimeHarness<SetAColorGradientRoot>) throws -> [Color] {
    let surface = try #require(h.runLoop.previousPresentedRasterSurface)
    let point = try #require(h.point(forText: "Gradient"))
    let start = Int(point.x) - "Gradient".count / 2
    let colors = surface.cells[Int(point.y)][start..<(start + "Gradient".count)]
      .compactMap { $0.style?.foregroundColor }
    #expect(colors.count == "Gradient".count)
    return colors
  }

  private func rect(x: Int = 0, y: Int = 0, width: Int = 8, height: Int = 4) -> CellRect {
    .init(origin: .init(x: x, y: y), size: .init(width: width, height: height))
  }
  private func sample(_ style: AnyShapeStyle, environment: StyleEnvironmentSnapshot = .init())
    -> Color?
  {
    Rasterizer().resolveColor(
      from: style, environment: environment, bounds: rect(), sampleX: 0, sampleY: 0)
  }
  private func meshInput(_ colors: [Color]) -> MeshGradientRasterInput {
    .init(
      width: 2, height: 2, points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
      colors: colors, background: .clear, smoothsColors: false, colorSpace: .device)
  }
  private func render<V: View>(_ view: V, width: Int, height: Int) -> RasterSurface {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetAColorPaint")),
      proposal: .init(width: width, height: height)
    ).rasterSurface
  }
}

private struct SetAColorGradientRoot: View {
  @State var reversed = false
  var body: some View {
    VStack {
      Button("Reverse paint") { reversed.toggle() }
      Text("Gradient").foregroundStyle(
        LinearGradient(
          colors: [.red, .blue],
          startPoint: reversed ? .trailing : .leading, endPoint: reversed ? .leading : .trailing)
      )
      .frame(width: 12, height: 2)
    }
  }
}
