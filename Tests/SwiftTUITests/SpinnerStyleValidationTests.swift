import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// An invalid spinner presentation is reported once per spinner node and
/// issue text, not once per animated frame: the automatic fallback keeps
/// ticking, and every tick re-validates the same invalid style.
@MainActor
@Suite(.serialized)
struct SpinnerStyleValidationTests {
  private func render(
    _ renderer: DefaultRenderer,
    style: some SpinnerStyle,
    identity: Identity,
    invalidated: Bool
  ) -> RenderSnapshot {
    renderer.render(
      Spinner().spinnerStyle(style),
      context: ResolveContext(
        identity: identity,
        invalidatedIdentities: invalidated ? [identity] : [],
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 12, height: 3)
    )
  }

  private func invalidPresentationIssues(
    in artifacts: RenderSnapshot,
    label: String
  ) -> [RuntimeIssue] {
    artifacts.diagnostics.runtime.issues.filter {
      $0.code == "style.invalidPresentation" && $0.message.contains(label)
    }
  }

  @Test("an invalid style reports once across presented frames until the style changes")
  func reportsOncePerInvalidStyle() {
    let renderer = DefaultRenderer()
    let identity = testIdentity("SpinnerRepeatedInvalid")
    let emptyLabel = "SpinnerValidation.emptyFrames"
    let mixedLabel = "SpinnerValidation.mixedWidths"
    let emptyFrames = GlyphSpinnerStyle(activeFrames: [], snapshotLabel: emptyLabel)

    // Three presented frames: the first mounts, the next two model the tick
    // invalidations that re-run the spinner body under the fallback cadence.
    var reports = 0
    for frame in 0..<3 {
      let artifacts = render(
        renderer, style: emptyFrames, identity: identity, invalidated: frame > 0)
      #expect(artifacts.rasterSurface.lines.joined().contains("⠋"))
      reports += invalidPresentationIssues(in: artifacts, label: emptyLabel).count
    }
    #expect(reports == 1)

    // A different invalid style is a new report; holding it is not.
    let mixedWidths = GlyphSpinnerStyle(activeFrames: ["|", "🌕"], snapshotLabel: mixedLabel)
    let replaced = render(renderer, style: mixedWidths, identity: identity, invalidated: true)
    #expect(invalidPresentationIssues(in: replaced, label: mixedLabel).count == 1)
    #expect(invalidPresentationIssues(in: replaced, label: emptyLabel).isEmpty)
    let held = render(renderer, style: mixedWidths, identity: identity, invalidated: true)
    #expect(invalidPresentationIssues(in: held, label: mixedLabel).isEmpty)

    // Recovering to a valid style and regressing to the same invalid one is
    // a style change on both edges, so the regression reports again.
    let valid = render(
      renderer, style: GlyphSpinnerStyle(activeFrames: ["▚", "▞"]), identity: identity,
      invalidated: true)
    #expect(invalidPresentationIssues(in: valid, label: mixedLabel).isEmpty)
    let regressed = render(renderer, style: mixedWidths, identity: identity, invalidated: true)
    #expect(invalidPresentationIssues(in: regressed, label: mixedLabel).count == 1)
  }
}
