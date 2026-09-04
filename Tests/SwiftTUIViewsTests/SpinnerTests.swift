import Testing

@_spi(StyleFixtures) @testable import SwiftTUIViews

@MainActor
@Suite("Spinner styles")
struct SpinnerTests {
  private func presentation(
    of style: AnySpinnerStyle,
    stage: Spinner.Stage = .active
  ) -> SpinnerStylePresentation {
    style.presentation(
      for: SpinnerStyleConfiguration(
        stage: stage,
        accessibilityReduceMotion: false,
        styleEnvironment: StyleEnvironmentSnapshot()
      )
    )
  }

  @Test("the automatic style preserves the braille loop at 64 ms")
  func automaticPreservesBrailleLoopCadence() {
    let resolved = presentation(of: .automatic)
    #expect(resolved.activeFrames == ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
    #expect(resolved.interval == .milliseconds(64))
    #expect(resolved.foregroundStyle == nil)
  }

  @Test("the asterisk cycle keeps its glyphs and the gallery's 240 ms cadence")
  func asteriskCycleGlyphsAndCadence() {
    let resolved = presentation(of: .asteriskCycle)
    #expect(resolved.activeFrames == ["*", "·", "+", "÷"])
    #expect(resolved.interval == .milliseconds(240))
  }

  @Test("a custom glyph style resolves its own frames and cadence")
  func customGlyphStyleResolves() {
    let custom = GlyphSpinnerStyle(
      activeFrames: ["◡", "◟", "◜", "◠"],
      inactiveFrame: "○",
      finishedFrame: "●",
      interval: .milliseconds(120)
    )
    let resolved = presentation(of: AnySpinnerStyle(custom))
    #expect(resolved.activeFrames == ["◡", "◟", "◜", "◠"])
    #expect(resolved.inactiveFrame == "○")
    #expect(resolved.finishedFrame == "●")
    #expect(resolved.interval == .milliseconds(120))
  }

  @Test("equal-valued glyph styles compare equal for reuse; distinct values do not")
  func glyphStyleReuseEquality() {
    let a = AnySpinnerStyle(.moonPhase)
    let b = AnySpinnerStyle(.moonPhase)
    let c = AnySpinnerStyle(.globe)
    #expect(a.isEqualForReuse(to: b))
    #expect(!a.isEqualForReuse(to: c))
  }

  @Test("every built-in exposes a distinct snapshot label")
  func builtinSnapshotLabelsAreDistinct() {
    let builtins: [AnySpinnerStyle] = [
      .automatic, .circleOrbit, .brailleRingFilled, .brailleBlockFill, .barRise,
      .circleFill, .brailleSweep, .diamondPulse, .brailleDotOrbit,
      .brailleLoopFilled, .quadrantOrbit, .clockFace, .halfCircle,
      .triangleCompass, .brailleRamp, .brailleLinePulse, .diceRoll,
      .boxCornerOrbit, .brailleDotFade, .brailleLineSweep, .brailleRing,
      .arcOrbit, .brailleLoop, .shadeFade, .dotChase, .globe, .moonPhase,
      .segmentedBar, .arrowCompass, .glyphPulse, .blockCorners,
      .horizontalBarFill, .quadrantCorners, .verticalBarFill,
      .heavyArrowCompass, .lineCompass, .asteriskCycle, .oghamPulse,
    ]
    let labels = builtins.map(\.description)
    #expect(labels.count == 38)
    #expect(Set(labels).count == labels.count)
    #expect(labels.allSatisfy { $0.hasPrefix("SpinnerStyle.") })
  }

  @Test("every built-in's active frames share one terminal-cell width")
  func builtinActiveFramesShareOneWidth() {
    let builtins: [AnySpinnerStyle] = [
      .automatic, .circleOrbit, .brailleRingFilled, .brailleBlockFill, .barRise,
      .circleFill, .brailleSweep, .diamondPulse, .brailleDotOrbit,
      .brailleLoopFilled, .quadrantOrbit, .clockFace, .halfCircle,
      .triangleCompass, .brailleRamp, .brailleLinePulse, .diceRoll,
      .boxCornerOrbit, .brailleDotFade, .brailleLineSweep, .brailleRing,
      .arcOrbit, .brailleLoop, .shadeFade, .dotChase, .globe, .moonPhase,
      .segmentedBar, .arrowCompass, .glyphPulse, .blockCorners,
      .horizontalBarFill, .quadrantCorners, .verticalBarFill,
      .heavyArrowCompass, .lineCompass, .asteriskCycle, .oghamPulse,
    ]
    for builtin in builtins {
      let frames = presentation(of: builtin).activeFrames
      let widths = Set(
        frames.map { frame in
          frame.reduce(0) { $0 + cellWidth(of: $1) }
        }
      )
      #expect(
        widths.count == 1,
        "\(builtin.description) mixes frame widths \(widths.sorted())"
      )
      #expect(!frames.isEmpty)
    }
  }
}
