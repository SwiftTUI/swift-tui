import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The A2 spinner-style runtime battery (control-style plan 2026-08-12-002):
/// invalid presentations fall back to automatic through the shared misuse
/// channel, and the animation task's identity is scoped to the resolved
/// frames, cadence, and stage — never to paint or to the style value that
/// produced them.
@MainActor
@Suite(.serialized)
struct SpinnerStyleRuntimeTests {
  private func render(
    _ renderer: DefaultRenderer = DefaultRenderer(),
    style: some SpinnerStyle,
    stage: Spinner.Stage = .active,
    taskRegistry: LocalTaskRegistry? = nil,
    identity: Identity,
    invalidated: Bool = false
  ) -> RenderSnapshot {
    renderer.render(
      Spinner(stage: stage).spinnerStyle(style),
      context: ResolveContext(
        identity: identity,
        invalidatedIdentities: invalidated ? [identity] : [],
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 12, height: 3)
    )
  }

  private func styleIssues(in artifacts: RenderSnapshot) -> [RuntimeIssue] {
    artifacts.diagnostics.runtime.issues.filter { $0.code == "style.invalidPresentation" }
  }

  private func surface(of artifacts: RenderSnapshot) -> String {
    artifacts.rasterSurface.lines.joined(separator: "\n")
  }

  /// Registers the style's spinner task on a shared renderer and returns the
  /// sole registered descriptor. Cross-render comparison is only meaningful
  /// on one renderer: the value-to-label mapping that distinguishes task ids
  /// lives on the graph.
  private func soleTaskDescriptor(
    _ renderer: DefaultRenderer,
    style: some SpinnerStyle,
    registry: LocalTaskRegistry,
    identity: Identity,
    invalidated: Bool
  ) throws -> TaskDescriptor {
    _ = render(
      renderer,
      style: style,
      taskRegistry: registry,
      identity: identity,
      invalidated: invalidated
    )
    let registrations = registry.snapshot().values.flatMap { $0 }
    #expect(registrations.count == 1)
    return try #require(registrations.first?.descriptor)
  }

  @Test("an empty-frames presentation falls back to automatic and reports one issue")
  func emptyFramesFallBackAndReport() throws {
    let artifacts = render(
      style: GlyphSpinnerStyle(activeFrames: []),
      identity: testIdentity("SpinnerEmptyFrames")
    )
    #expect(surface(of: artifacts).contains("⠋"))
    let issues = styleIssues(in: artifacts)
    let issue = try #require(issues.first)
    #expect(issues.count == 1)
    #expect(issue.message.contains("active frames are empty"))
    #expect(issue.message.contains("SpinnerStyle"))
  }

  @Test("a non-positive cadence falls back to automatic and reports one issue")
  func nonPositiveCadenceFallsBackAndReports() throws {
    let artifacts = render(
      style: GlyphSpinnerStyle(activeFrames: ["|", "/"], interval: .zero),
      identity: testIdentity("SpinnerZeroInterval")
    )
    #expect(surface(of: artifacts).contains("⠋"))
    let issue = try #require(styleIssues(in: artifacts).first)
    #expect(issue.message.contains("interval is not positive"))
  }

  @Test("mixed-width active frames fall back to automatic and report one issue")
  func mixedWidthFramesFallBackAndReport() throws {
    let artifacts = render(
      style: GlyphSpinnerStyle(activeFrames: ["|", "🌕"]),
      identity: testIdentity("SpinnerMixedWidths")
    )
    #expect(surface(of: artifacts).contains("⠋"))
    let issue = try #require(styleIssues(in: artifacts).first)
    #expect(issue.message.contains("mix terminal-cell widths"))
  }

  @Test("a valid custom presentation reports no issue and renders its frame")
  func validPresentationReportsNoIssue() {
    let artifacts = render(
      style: GlyphSpinnerStyle(activeFrames: ["▚", "▞"]),
      identity: testIdentity("SpinnerValid")
    )
    #expect(styleIssues(in: artifacts).isEmpty)
    #expect(surface(of: artifacts).contains("▚"))
  }

  @Test("a paint-only style difference keeps the task descriptor")
  func paintOnlyDifferenceKeepsTaskDescriptor() throws {
    let renderer = DefaultRenderer()
    let registry = LocalTaskRegistry()
    let identity = testIdentity("SpinnerPaint")
    let a = try soleTaskDescriptor(
      renderer,
      style: GlyphSpinnerStyle(
        activeFrames: ["|", "/", "-"],
        foregroundStyle: AnyShapeStyle(Color.red)
      ),
      registry: registry,
      identity: identity,
      invalidated: false
    )
    let b = try soleTaskDescriptor(
      renderer,
      style: GlyphSpinnerStyle(
        activeFrames: ["|", "/", "-"],
        foregroundStyle: AnyShapeStyle(Color.blue)
      ),
      registry: registry,
      identity: identity,
      invalidated: true
    )
    #expect(a == b)
  }

  @Test("distinct styles resolving the same frames and cadence share the task descriptor")
  func equalResolvingStylesShareTaskDescriptor() throws {
    // `.automatic` and `.brailleLoop` are distinct built-ins (distinct
    // labels) that resolve identical frames and cadence; swapping between
    // them must not restart the loop.
    let renderer = DefaultRenderer()
    let registry = LocalTaskRegistry()
    let identity = testIdentity("SpinnerEqualResolve")
    let a = try soleTaskDescriptor(
      renderer,
      style: GlyphSpinnerStyle.automatic,
      registry: registry,
      identity: identity,
      invalidated: false
    )
    let b = try soleTaskDescriptor(
      renderer,
      style: GlyphSpinnerStyle.brailleLoop,
      registry: registry,
      identity: identity,
      invalidated: true
    )
    #expect(a == b)
  }

  @Test("a cadence change changes the task descriptor")
  func cadenceChangeChangesTaskDescriptor() throws {
    let renderer = DefaultRenderer()
    let registry = LocalTaskRegistry()
    let identity = testIdentity("SpinnerCadence")
    let a = try soleTaskDescriptor(
      renderer,
      style: GlyphSpinnerStyle(activeFrames: ["|", "/"], interval: .milliseconds(200)),
      registry: registry,
      identity: identity,
      invalidated: false
    )
    let b = try soleTaskDescriptor(
      renderer,
      style: GlyphSpinnerStyle(activeFrames: ["|", "/"], interval: .milliseconds(50)),
      registry: registry,
      identity: identity,
      invalidated: true
    )
    #expect(a != b)
  }

  @Test("a frame-sequence change changes the task descriptor")
  func frameChangeChangesTaskDescriptor() throws {
    let renderer = DefaultRenderer()
    let registry = LocalTaskRegistry()
    let identity = testIdentity("SpinnerFrames")
    let a = try soleTaskDescriptor(
      renderer,
      style: GlyphSpinnerStyle(activeFrames: ["|", "/"]),
      registry: registry,
      identity: identity,
      invalidated: false
    )
    let b = try soleTaskDescriptor(
      renderer,
      style: GlyphSpinnerStyle(activeFrames: ["-", "\\"]),
      registry: registry,
      identity: identity,
      invalidated: true
    )
    #expect(a != b)
  }

  @Test("inactive and finished stages render their static frames")
  func inertStagesRenderStaticFrames() {
    for stage in [Spinner.Stage.inactive, .finished] {
      let artifacts = render(
        style: GlyphSpinnerStyle(
          activeFrames: ["|"], inactiveFrame: "i", finishedFrame: "f"),
        stage: stage,
        identity: testIdentity("SpinnerInert-\(stage)")
      )
      #expect(surface(of: artifacts).contains(stage == .inactive ? "i" : "f"))
    }
  }
}
