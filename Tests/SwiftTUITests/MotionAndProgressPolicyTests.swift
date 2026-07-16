import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
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

    #expect(context.environmentValues.accessibilityReduceMotion)
    #expect(context.environmentValues.suppressesProgress)
    #expect(context.transaction.animationRequest == .disabled)
    #expect(context.transaction.animationBatchID == nil)
  }

  @Test("reduced motion renders indeterminate progress as static status text")
  func reducedMotionRendersIndeterminateProgressAsStaticStatus() {
    let surface = renderedSurface(
      ProgressView("Loading", barWidth: 8),
      environmentValues: policyEnvironment(accessibilityReduceMotion: true),
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
      environmentValues: policyEnvironment(accessibilityReduceMotion: true),
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
        environmentValues: policyEnvironment(accessibilityReduceMotion: true)
      )
    )
    _ = reducedRenderer.render(
      animatedText(shifted: true, animation: animation),
      context: ResolveContext(
        identity: testIdentity("ReducedRepeatedAnimation"),
        environmentValues: policyEnvironment(accessibilityReduceMotion: true)
      )
    )

    #expect(normalRenderer.internalAnimationController.activeAnimationCount > 0)
    #expect(reducedRenderer.internalAnimationController.activeAnimationCount == 0)
    #expect(!reducedRenderer.internalAnimationController.lastTickResult.hasPendingWork)
  }

  @Test("reduced motion suppresses PhaseAnimator task ticks")
  func reducedMotionSuppressesPhaseAnimatorTaskTicks() {
    let normalRegistry = LocalTaskRegistry()
    _ = renderArtifacts(
      phaseAnimatorProbe(),
      taskRegistry: normalRegistry,
      identity: testIdentity("NormalPhaseAnimator")
    )

    let reducedRegistry = LocalTaskRegistry()
    let reducedSurface = renderedSurface(
      phaseAnimatorProbe(),
      environmentValues: policyEnvironment(accessibilityReduceMotion: true),
      taskRegistry: reducedRegistry,
      identity: testIdentity("ReducedPhaseAnimator")
    )

    #expect(normalRegistry.snapshot().count == 1)
    #expect(reducedRegistry.snapshot().isEmpty)
    #expect(reducedSurface.contains("rest"))
  }

  @Test("reduced motion suppresses transition intermediates")
  func reducedMotionSuppressesTransitionIntermediates() async {
    let normalCount = await transitionAnimationCount(reducedMotion: false)
    let reducedCount = await transitionAnimationCount(reducedMotion: true)

    #expect(normalCount > 0)
    #expect(reducedCount == 0)
  }

  @Test("reduced motion suppresses matched geometry translation")
  func reducedMotionSuppressesMatchedGeometryTranslation() {
    let normalCount = matchedGeometryAnimationCount(reducedMotion: false)
    let reducedCount = matchedGeometryAnimationCount(reducedMotion: true)

    #expect(normalCount > 0)
    #expect(reducedCount == 0)
  }

  @Test("static controls render unchanged under motion and progress policy")
  func staticControlsRenderUnchangedUnderPolicy() {
    let surface = renderedSurface(
      Text("Ready"),
      environmentValues: policyEnvironment(
        accessibilityReduceMotion: true,
        suppressesProgress: true
      ),
      identity: testIdentity("StaticPolicyText")
    )

    #expect(surface.contains("Ready"))
  }
}

@MainActor
private func phaseAnimatorProbe() -> some View {
  PhaseAnimator(["rest", "pulse"]) { phase in
    Text(phase)
  } animation: { _ in
    .linear(duration: .milliseconds(500))
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
private func transitionAnimationCount(reducedMotion: Bool) async -> Int {
  let renderer = DefaultRenderer()
  let controller = renderer.internalAnimationController
  let animation = Animation.linear(duration: .milliseconds(500))
  controller.register(animation)
  let rootIdentity = testIdentity(reducedMotion ? "ReducedTransition" : "NormalTransition")
  let environmentValues = policyEnvironment(accessibilityReduceMotion: reducedMotion)

  return await TransitionRegistrationStorage.withSink(controller) {
    _ = renderer.render(
      transitionProbe(show: false),
      context: ResolveContext(
        identity: rootIdentity,
        environmentValues: environmentValues
      )
    )

    var transaction = TransactionSnapshot()
    transaction.animationRequest =
      reducedMotion ? .disabled : .animate(animation.animationBox)
    _ = renderer.render(
      transitionProbe(show: true),
      context: ResolveContext(
        identity: rootIdentity,
        environmentValues: environmentValues,
        transaction: transaction
      )
    )

    return controller.activeAnimationCount
  }
}

@MainActor
private func transitionProbe(show: Bool) -> some View {
  VStack {
    if show {
      Text("Panel")
        .id(testIdentity("Panel"))
        .transition(.opacity)
    }
  }
}

@MainActor
private func matchedGeometryAnimationCount(reducedMotion: Bool) -> Int {
  let renderer = DefaultRenderer()
  let controller = renderer.internalAnimationController
  let animation = Animation.linear(duration: .milliseconds(500))
  controller.register(animation)
  let rootIdentity = testIdentity(reducedMotion ? "ReducedMatched" : "NormalMatched")
  let environmentValues = policyEnvironment(accessibilityReduceMotion: reducedMotion)

  _ = renderer.render(
    matchedGeometryProbe(swapped: false),
    context: ResolveContext(
      identity: rootIdentity,
      environmentValues: environmentValues
    ),
    proposal: ProposedSize(width: .finite(40), height: .finite(3))
  )

  var transaction = TransactionSnapshot()
  transaction.animationRequest =
    reducedMotion ? .disabled : .animate(animation.animationBox)
  _ = renderer.render(
    matchedGeometryProbe(swapped: true),
    context: ResolveContext(
      identity: rootIdentity,
      environmentValues: environmentValues,
      transaction: transaction
    ),
    proposal: ProposedSize(width: .finite(40), height: .finite(3))
  )

  return controller.activeMatchedGeometryCount
}

@MainActor
private func matchedGeometryProbe(swapped: Bool) -> some View {
  HStack(spacing: 1) {
    if swapped {
      Text("other")
      Text("hero").matchedGeometryEffect(id: "hero")
    } else {
      Text("hero").matchedGeometryEffect(id: "hero")
      Text("other")
    }
  }
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
) -> RenderSnapshot {
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
  accessibilityReduceMotion: Bool = false,
  suppressesProgress: Bool = false
) -> EnvironmentValues {
  var values = EnvironmentValues()
  values.accessibilityReduceMotion = accessibilityReduceMotion
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

/// F134: reduced motion must keep SwiftUI's completion contract — the state
/// change applies instantly AND the `withAnimation(_:completion:)` closure
/// still fires. The resolve-context construction nils the batch ID under
/// `motion == .reduced`, so no animation ever retains the batch; before the
/// fix the registered completion was orphaned (a live awaiter hung forever)
/// and the non-empty completion ledger raised the `.animationCompletion`
/// frame-drop blocker for the whole session.
@MainActor
@Suite
struct ReducedMotionCompletionDeliveryTests {
  @MainActor
  private final class CompletionCounter {
    private(set) var count = 0
    func increment() { count += 1 }
  }

  @Test("reduced motion still delivers withAnimation completions and clears the drop blocker")
  func reducedMotionDeliversWithAnimationCompletions() throws {
    let rootIdentity = testIdentity("ReducedMotionCompletionRoot")
    let scheduler = FrameScheduler()
    let animation = Animation.linear(duration: .milliseconds(400))
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: MotionPolicyTestSurface(),
      terminalInputReader: MotionPolicyInputReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      runtimeConfiguration: RuntimeConfiguration(motion: .reduced),
      viewBuilder: ScopedMapper { _ in
        Text("Ready")
      }
    )
    let controller = runLoop.renderer.internalAnimationController
    controller.register(animation)
    let batchID = AnimationBatchID(13_401)
    let counter = CompletionCounter()
    controller.registerCompletion(batchID: batchID) {
      MainActor.assumeIsolated {
        counter.increment()
      }
    }

    scheduler.requestInvalidation(
      of: [rootIdentity],
      animation: .animate(animation.animationBox),
      batchID: batchID
    )
    let frame = try #require(scheduler.consumeReadyFrame())
    _ = runLoop.resolveContext(for: frame)

    // The reduced-motion transaction nils the batch, so no animation will
    // ever retain it. The completion must be parked (the superseded-batch
    // machinery: immediate deadline) and fire on the next controller tick.
    var leaf = ResolvedNode(
      identity: testIdentity("ReducedMotionCompletionLeaf"),
      kind: .view("Leaf")
    )
    _ = controller.applyInterpolations(
      to: &leaf,
      at: .now().advanced(by: .milliseconds(1))
    )

    #expect(
      counter.count == 1,
      "the withAnimation completion never fired under reduced motion"
    )

    // The fired completion deliberately holds the `.animationCompletion`
    // blocker for ONE frame (its state writes still need presenting). The
    // next frame head resets that hold; after it, no ledger may keep the
    // blocker raised for the session.
    controller.processResolvedTree(
      leaf,
      transaction: .init(),
      timestamp: .now().advanced(by: .milliseconds(2))
    )
    #expect(
      !controller.frameDropEligibilityBlockers.contains(.animationCompletion),
      "the orphaned completion ledger blocked frame drops for the session"
    )
  }

  @Test("reduced motion parks every disjoint same-frame animation batch")
  func reducedMotionParksEverySegmentBatch() throws {
    let rootIdentity = testIdentity("ReducedMotionSegmentRoot")
    let firstIdentity = testIdentity("ReducedMotionSegmentRoot", "First")
    let secondIdentity = testIdentity("ReducedMotionSegmentRoot", "Second")
    let scheduler = FrameScheduler()
    let firstAnimation = Animation.linear(duration: .milliseconds(100))
    let secondAnimation = Animation.linear(duration: .milliseconds(250))
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: MotionPolicyTestSurface(),
      terminalInputReader: MotionPolicyInputReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      runtimeConfiguration: RuntimeConfiguration(motion: .reduced),
      viewBuilder: ScopedMapper { _ in
        Text("Ready")
      }
    )
    let controller = runLoop.renderer.internalAnimationController
    let firstBatchID = AnimationBatchID(13_402)
    let secondBatchID = AnimationBatchID(13_403)
    let counter = CompletionCounter()
    controller.registerCompletion(batchID: firstBatchID) {
      MainActor.assumeIsolated { counter.increment() }
    }
    controller.registerCompletion(batchID: secondBatchID) {
      MainActor.assumeIsolated { counter.increment() }
    }

    scheduler.requestInvalidation(
      of: [firstIdentity],
      animation: .animate(firstAnimation.animationBox),
      batchID: firstBatchID
    )
    scheduler.requestInvalidation(
      of: [secondIdentity],
      animation: .animate(secondAnimation.animationBox),
      batchID: secondBatchID
    )
    let frame = try #require(scheduler.consumeReadyFrame())
    #expect(frame.liveAnimationBatchIDs == [firstBatchID, secondBatchID])

    let context = runLoop.resolveContext(for: frame)
    #expect(context.transaction.animationRequest == .disabled)
    #expect(context.animationSegments.isEmpty)

    var leaf = ResolvedNode(
      identity: testIdentity("ReducedMotionSegmentLeaf"),
      kind: .view("Leaf")
    )
    _ = controller.applyInterpolations(
      to: &leaf,
      at: .now().advanced(by: .milliseconds(1))
    )
    #expect(counter.count == 2)
  }
}
