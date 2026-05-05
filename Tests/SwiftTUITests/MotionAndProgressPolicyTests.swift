import Testing

@testable import SwiftTUI
@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct MotionAndProgressPolicyTests {
  @Test("runtime configuration maps reduced motion and no-progress into resolve context")
  func runtimeConfigurationMapsPolicyIntoResolveContext() throws {
    let rootIdentity = testIdentity("RuntimeMotionPolicyRoot")
    let scheduler = FrameScheduler()
    let animation = Animation.linear(duration: .milliseconds(1_000))
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: MotionPolicyTestSurface(),
      terminalInputReader: MotionPolicyInputReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      runtimeConfiguration: RuntimeConfiguration(motion: .reduced, noProgress: true),
      viewBuilder: ScopedMapper { _ in
        Text("Ready")
      }
    )

    scheduler.requestInvalidation(
      of: [rootIdentity],
      animation: .animate(animation.animationBox),
      batchID: nil
    )
    let frame = try #require(scheduler.consumeReadyFrame())
    let context = runLoop.resolveContext(for: frame)

    #expect(context.environmentValues.reducesMotion)
    #expect(context.environmentValues.suppressesProgress)
    #expect(context.transaction.animationRequest == .disabled)
    #expect(context.transaction.animationBatchID == nil)
  }

  @Test("reduced motion renders indeterminate progress as static status text")
  func reducedMotionRendersIndeterminateProgressAsStaticStatus() {
    let surface = renderedSurface(
      ProgressView("Loading", barWidth: 8),
      environmentValues: policyEnvironment(reducesMotion: true),
      identity: testIdentity("ReducedMotionProgress")
    )

    #expect(surface.contains("Loading"))
    #expect(!surface.contains("█"))
    #expect(!surface.contains("─"))
  }

  @Test("no-progress removes progress ornament and keeps determinate status text")
  func noProgressKeepsDeterminateStatusText() {
    let surface = renderedSurface(
      ProgressView("Sync", value: 3, total: 4, barWidth: 8),
      environmentValues: policyEnvironment(suppressesProgress: true),
      identity: testIdentity("NoProgressDeterminate")
    )

    #expect(surface.contains("Sync"))
    #expect(surface.contains("3/4"))
    #expect(!surface.contains("█"))
    #expect(!surface.contains("─"))
  }

  @Test("reduced motion suppresses spinner task ticks")
  func reducedMotionSuppressesSpinnerTaskTicks() {
    let normalRegistry = LocalTaskRegistry()
    _ = renderArtifacts(
      Spinner(.asciiLineCompass),
      taskRegistry: normalRegistry,
      identity: testIdentity("NormalSpinner")
    )

    let reducedRegistry = LocalTaskRegistry()
    let reducedSurface = renderedSurface(
      Spinner(.asciiLineCompass),
      environmentValues: policyEnvironment(reducesMotion: true),
      taskRegistry: reducedRegistry,
      identity: testIdentity("ReducedSpinner")
    )

    #expect(normalRegistry.snapshot().count == 1)
    #expect(reducedRegistry.snapshot().isEmpty)
    #expect(reducedSurface.contains("|"))
  }

  @Test("reduced motion suppresses repeated value animations")
  func reducedMotionSuppressesRepeatedValueAnimations() {
    let animation = Animation.linear(duration: .milliseconds(1_000))
      .repeatForever(autoreverses: false)

    let normalRenderer = DefaultRenderer()
    normalRenderer.internalAnimationController.register(animation)
    _ = normalRenderer.render(
      animatedText(shifted: false, animation: animation),
      context: ResolveContext(identity: testIdentity("NormalRepeatedAnimation"))
    )
    _ = normalRenderer.render(
      animatedText(shifted: true, animation: animation),
      context: ResolveContext(identity: testIdentity("NormalRepeatedAnimation"))
    )

    let reducedRenderer = DefaultRenderer()
    reducedRenderer.internalAnimationController.register(animation)
    _ = reducedRenderer.render(
      animatedText(shifted: false, animation: animation),
      context: ResolveContext(
        identity: testIdentity("ReducedRepeatedAnimation"),
        environmentValues: policyEnvironment(reducesMotion: true)
      )
    )
    _ = reducedRenderer.render(
      animatedText(shifted: true, animation: animation),
      context: ResolveContext(
        identity: testIdentity("ReducedRepeatedAnimation"),
        environmentValues: policyEnvironment(reducesMotion: true)
      )
    )

    #expect(normalRenderer.internalAnimationController.activeAnimationCount > 0)
    #expect(reducedRenderer.internalAnimationController.activeAnimationCount == 0)
    #expect(!reducedRenderer.internalAnimationController.lastTickResult.hasPendingWork)
  }

  @Test("static controls render unchanged under motion and progress policy")
  func staticControlsRenderUnchangedUnderPolicy() {
    let surface = renderedSurface(
      Text("Ready"),
      environmentValues: policyEnvironment(reducesMotion: true, suppressesProgress: true),
      identity: testIdentity("StaticPolicyText")
    )

    #expect(surface.contains("Ready"))
  }
}

@MainActor
private func animatedText(
  shifted: Bool,
  animation: Animation
) -> some View {
  Text("Move")
    .offset(x: shifted ? 4 : 0, y: 0)
    .animation(animation, value: shifted)
}

@MainActor
private func renderedSurface<V: View>(
  _ view: V,
  environmentValues: EnvironmentValues = .init(),
  taskRegistry: LocalTaskRegistry? = nil,
  identity: Identity
) -> String {
  renderArtifacts(
    view,
    environmentValues: environmentValues,
    taskRegistry: taskRegistry,
    identity: identity
  ).rasterSurface.lines.joined(separator: "\n")
}

@MainActor
private func renderArtifacts<V: View>(
  _ view: V,
  environmentValues: EnvironmentValues = .init(),
  taskRegistry: LocalTaskRegistry? = nil,
  identity: Identity
) -> FrameArtifacts {
  DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: identity,
      environmentValues: environmentValues,
      localTaskRegistry: taskRegistry,
      applyEnvironmentValues: true
    ),
    proposal: .init(width: 40, height: 8)
  )
}

private func policyEnvironment(
  reducesMotion: Bool = false,
  suppressesProgress: Bool = false
) -> EnvironmentValues {
  var values = EnvironmentValues()
  values.reducesMotion = reducesMotion
  values.suppressesProgress = suppressesProgress
  return values
}

private final class MotionPolicyTestSurface: PresentationSurface {
  let surfaceSize = CellSize(width: 40, height: 8)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics {
    TerminalPresentationMetrics()
  }
}

private final class MotionPolicyInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
