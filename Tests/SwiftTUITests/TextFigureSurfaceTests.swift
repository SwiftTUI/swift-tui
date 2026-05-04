import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite
struct TextFigureSurfaceTests {
  @Test("TextFigure renders the embedded standard font at its ideal width")
  func textFigureRendersStandardFontAtIdealWidth() {
    let artifacts = render(TextFigure("Hi"))
    let standardFont = embeddedFont(named: "standard")
    let metrics = TextFigureSupport.layoutMetrics(
      for: .init(content: "Hi", font: standardFont)
    )

    #expect(metrics.idealSize == .init(width: 9, height: 6))
    #expect(artifacts.measuredTree.measuredSize == .init(width: 9, height: 6))
    #expect(artifacts.placedTree.bounds.size == .init(width: 9, height: 6))

    #expect(
      artifacts.rasterSurface.lines == [
        " _   _ _",
        "| | | (_)",
        "| |_| | |",
        "|  _  | |",
        "|_| |_|_|",
        "",
      ])
  }

  @Test("TextFigure renders alternate embedded fonts")
  func textFigureRendersAlternateEmbeddedFonts() {
    let artifacts = render(TextFigure("Hi", font: embeddedFont(named: "slant")))

    #expect(
      artifacts.rasterSurface.lines == [
        "    __  ___",
        "   / / / (_)",
        "  / /_/ / /",
        " / __  / /",
        "/_/ /_/_/",
        "",
      ])
  }

  @Test("finite width proposals reflow TextFigure output")
  func finiteWidthProposalsReflowTextFigureOutput() {
    let artifacts = render(
      TextFigure("Hi"),
      proposal: .init(width: 8, height: .unspecified)
    )

    #expect(
      artifacts.rasterSurface.lines == [
        " _   _",
        "| | | |",
        "| |_| |",
        "|  _  |",
        "|_| |_|",
        "",
        " _",
        "(_)",
        "| |",
        "| |",
        "|_|",
        "",
      ])
  }

  @Test("widths below the figure minimum clip without rewrapping again")
  func widthsBelowMinimumClipWithoutDoubleWrapping() {
    let artifacts = render(
      TextFigure("Hi"),
      proposal: .init(width: 4, height: .unspecified)
    )

    #expect(
      artifacts.rasterSurface.lines == [
        " _  ",
        "| | ",
        "| |_",
        "|  _",
        "|_| ",
        "",
        " _",
        "(_)",
        "| |",
        "| |",
        "|_|",
        "",
      ])
  }

  @Test("generic view styling propagates to TextFigure output")
  func genericViewStylingPropagatesToTextFigureOutput() {
    let artifacts = render(
      TextFigure("Hi")
        .foregroundStyle(Color.red)
        .opacity(0.4)
        .underline()
        .strikethrough()
    )

    let styleRuns = artifacts.rasterSurface.styleRuns
    #expect(!styleRuns.isEmpty)
    // Opacity is baked into the foreground color at rasterize time so
    // the presentation layer emits a smoothly interpolated RGB instead
    // of the binary SGR "faint" attribute.  The foreground color is
    // therefore no longer pure red and the style's opacity is normalized
    // to 1.0 after baking.
    #expect(
      styleRuns.contains { run in
        guard let fg = run.style.foregroundColor else { return false }
        // The baked color sits strictly between red and the theme
        // background — it should not be the untouched red sentinel.
        return fg != Color.red && run.style.opacity == 1.0
      }
    )
    #expect(styleRuns.contains { $0.style.underlineStyle != nil })
    #expect(styleRuns.contains { $0.style.strikethroughStyle != nil })
  }

  @Test("TextFigure preserves authored TDF colors by default")
  func textFigurePreservesAuthoredTDFColorsByDefault() {
    let artifacts = render(TextFigure("x", font: embeddedFont(named: "208")))
    let palette = TerminalAppearance.fallback.palette
    let foregrounds = foregroundColors(in: artifacts)

    #expect(!foregrounds.isEmpty)
    #expect(
      foregrounds.contains { color in
        color == palette.red || color == palette.brightRed
      })
  }

  @Test("TextFigure monochrome color mode strips authored colors")
  func textFigureMonochromeColorModeStripsAuthoredColors() {
    let artifacts = render(
      TextFigure("x", font: embeddedFont(named: "208"))
        .textFigureColorMode(.monochrome)
        .foregroundStyle(Color.green)
    )
    let foregrounds = foregroundColors(in: artifacts)

    #expect(!foregrounds.isEmpty)
    #expect(foregrounds.allSatisfy { $0 == Color.green })
  }

  @Test("TextFigure override color mode replaces authored colors")
  func textFigureOverrideColorModeReplacesAuthoredColors() {
    let artifacts = render(
      TextFigure("x", font: embeddedFont(named: "208"))
        .textFigureColorMode(.override(Color.cyan))
        .foregroundStyle(Color.red)
    )
    let foregrounds = foregroundColors(in: artifacts)

    #expect(!foregrounds.isEmpty)
    #expect(foregrounds.allSatisfy { $0 == Color.cyan })
  }

  @Test("fractional opacity produces distinct blended foreground colors")
  func fractionalOpacityProducesDistinctForegroundColors() {
    // Guards against a regression to binary "faint" opacity rendering:
    // two different opacity values on the same color must produce two
    // visibly different foreground colors in the raster so animated
    // fades look smooth.
    let dim = render(
      Text("Hi").foregroundStyle(Color.red).opacity(0.3)
    )
    let bright = render(
      Text("Hi").foregroundStyle(Color.red).opacity(0.9)
    )

    let dimFg = dim.rasterSurface.styleRuns.first?.style.foregroundColor
    let brightFg = bright.rasterSurface.styleRuns.first?.style.foregroundColor
    #expect(dimFg != nil)
    #expect(brightFg != nil)
    #expect(
      dimFg != brightFg,
      "distinct opacity values must produce distinct blended foreground colors"
    )
    // Both style runs should carry opacity == 1.0 after baking.
    #expect(dim.rasterSurface.styleRuns.first?.style.opacity == 1.0)
    #expect(bright.rasterSurface.styleRuns.first?.style.opacity == 1.0)
  }

  private func render<V: View>(
    _ view: V,
    proposal: ProposedSize = .unspecified
  ) -> FrameArtifacts {
    DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root")),
      proposal: proposal
    )
  }

  private func embeddedFont(named name: String) -> TextFigure.Font {
    guard let font = TextFigure.availableFonts.first(where: { $0.rawValue == name }) else {
      fatalError("Missing embedded TextFigure font \(name)")
    }
    return font
  }

  private func foregroundColors(
    in artifacts: FrameArtifacts
  ) -> [Color] {
    artifacts.rasterSurface.styleRuns.compactMap(\.style.foregroundColor)
  }
}
