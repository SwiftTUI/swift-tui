import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct TextFigureSurfaceTests {
  @Test("TextFigure renders the embedded standard font at its ideal width")
  func textFigureRendersStandardFontAtIdealWidth() {
    let artifacts = render(TextFigure("Hi"))
    let metrics = TextFigureSupport.layoutMetrics(for: .init(content: "Hi", font: "standard"))

    #expect(metrics.idealSize == .init(width: 9, height: 6))
    #expect(artifacts.measuredTree.measuredSize == .init(width: 9, height: 6))
    #expect(artifacts.placedTree.bounds.size == .init(width: 9, height: 6))

    #expect(artifacts.rasterSurface.lines == [
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
    let artifacts = render(TextFigure("Hi", font: "slant"))

    #expect(artifacts.rasterSurface.lines == [
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

    #expect(artifacts.rasterSurface.lines == [
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

    #expect(artifacts.rasterSurface.lines == [
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
    #expect(styleRuns.contains { $0.style.foregroundColor == .red })
    #expect(styleRuns.contains { $0.style.opacity == 0.4 })
    #expect(styleRuns.contains { $0.style.underlineStyle != nil })
    #expect(styleRuns.contains { $0.style.strikethroughStyle != nil })
  }

  @Test("invalid TextFigure fonts fall back to plain text")
  func invalidTextFigureFontsFallBackToPlainText() {
    let artifacts = render(TextFigure("Hi", font: "missing-font"))

    #expect(artifacts.resolvedTree.kind == .view("TextFigure"))
    #expect(artifacts.resolvedTree.drawPayload == .text("Hi"))
    #expect(artifacts.rasterSurface.lines == ["Hi"])
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
}
