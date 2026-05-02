import Foundation
import Testing

@_spi(Testing) @testable import Core
@testable import SwiftTUI
@testable import View

/// Regression pins for the "gallery freezes on the chasing-light panel"
/// bug.
///
/// The user's repro: navigate to the Borders & Shapes tab, which mounts
/// a `BorderBlend` chasing-light animation under
/// `withAnimation(.linear(duration: .milliseconds(3000)).repeatForever)`
/// alongside a `Canvas` sparkline further down the same `ScrollView`
/// content.  Once the animation is in flight every 33 ms tick frame
/// pegs the run loop at ~30 ms / frame.  Removing `.onAppear` (so the
/// animation never starts) makes the freeze go away; switching to a
/// short, non-repeating animation makes it less noticeable.
///
/// Diagnosis (see commit message): two distinct measurement-cache
/// equivalence bugs were both kicking in.
///
///   1. ``LayoutBehavior.border``'s `==` includes the cosmetic
///      `blendPhase` field, so two borders that differ only in their
///      animated phase reported "not equivalent" and forced the layout
///      cache to re-measure them on every tick.
///   2. ``DrawPayload.isEquivalentForMeasurement`` had no `.canvas`
///      case at all and fell through to `default: return false`, so a
///      `Canvas` leaf reported "not equivalent" against itself even
///      when its drawing was byte-for-byte identical.
///
/// Both bugs cascade up the ancestor spine via the recursive
/// `ResolvedNode.isEquivalentForMeasurement` walk: a single leaf that
/// fails the equivalence check invalidates every ancestor's cached
/// measurement.  In the gallery, the canvas at the bottom of the
/// borders tab caused the entire tab's ancestor spine to re-measure
/// on every chasing-light tick.
///
/// These tests pin both fixes:
///
///   * `borderBlendPhase` mutations alone do not invalidate the
///     measurement cache.
///   * Identical `Canvas` payloads are measurement-equivalent.
///   * A view that pairs an animated border with a `Canvas` further
///     down the tree drives ZERO `measuredNodesComputed` per tick
///     across many frames.
@MainActor
@Suite("Animation chasing-light tick frames must not invalidate the measure cache", .serialized)
struct AnimationRepeatForeverGrowthTests {
  // MARK: - Equivalence-predicate unit pins

  @Test("LayoutBehavior.border equivalence ignores blendPhase")
  func borderLayoutBehaviorEquivalenceIgnoresPhase() {
    let phaseA = LayoutBehavior.border(
      .rounded,
      placement: .outset,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue, .red]),
      blendPhase: 0.31,
      sides: .all
    )
    let phaseB = LayoutBehavior.border(
      .rounded,
      placement: .outset,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue, .red]),
      blendPhase: 0.42,
      sides: .all
    )
    #expect(
      phaseA != phaseB,
      "two borders with distinct blendPhase values must differ under ==, or there is no animation phase to interpolate at all"
    )
    #expect(
      phaseA.isEquivalentForMeasurement(to: phaseB),
      "blendPhase is a draw-time-only field, so layout-measurement equivalence must ignore it"
    )

    // Sanity check: the carve-out must NOT swallow border changes that
    // actually do affect layout (set or sides).
    let differentSet = LayoutBehavior.border(
      .double,
      placement: .outset,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue, .red]),
      blendPhase: 0.31,
      sides: .all
    )
    #expect(
      !phaseA.isEquivalentForMeasurement(to: differentSet),
      "different BorderSet values change borderLayoutInsets and must invalidate the cache"
    )
    let differentSides = LayoutBehavior.border(
      .rounded,
      placement: .outset,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue, .red]),
      blendPhase: 0.31,
      sides: .top
    )
    #expect(
      !phaseA.isEquivalentForMeasurement(to: differentSides),
      "different sides masks change borderLayoutInsets and must invalidate the cache"
    )
  }

  @Test("DrawPayload.canvas equivalence treats canvases as measurement-equivalent")
  func canvasDrawPayloadIsMeasurementEquivalent() {
    let lhs = DrawPayload.canvas(CanvasPayload(drawing: ProbeCanvasDrawing(value: 1)))
    let rhs = DrawPayload.canvas(CanvasPayload(drawing: ProbeCanvasDrawing(value: 2)))
    // Two canvases must be equivalent for measurement EVEN WHEN their
    // drawings differ.  The layout engine routes `.canvas` through the
    // same path as `.shape`: the cell frame is reserved by the parent's
    // proposal and the drawing is rasterized at paint time.  Drawings
    // never contribute to size — see ``LayoutEngine.measuredCellSize``,
    // ``case .canvas``.
    #expect(lhs.isEquivalentForMeasurement(to: rhs))
  }

  // MARK: - Pipeline integration

  @Test(
    "animated border + Canvas leaf drives zero measure churn across many ticks",
    arguments: [30, 80]
  )
  func animatedBorderWithCanvasLeafDoesNotChurnMeasurement(tickCount: Int) throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    AnimationRegistrationStorage.currentSink = controller
    TransitionRegistrationStorage.currentSink = controller
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
    }

    let animation = Animation.linear(duration: .milliseconds(3000))
      .repeatForever(autoreverses: false)
    controller.register(animation)

    let blend = BorderBlend([.red, .yellow, .green, .cyan, .blue, .magenta, .red])
    let rootIdentity = Identity(components: [.named("ChasingLightCanvasRepro")])

    @MainActor
    func body(phase: Double) -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("chasing light")
          .padding(1)
          .frame(width: 30, height: 3)
          .border(
            blend: blend,
            set: .rounded,
            phase: phase
          )
        // The Canvas leaf is what surfaced bug #2 in the gallery: every
        // animation tick invalidated its measurement cache via the
        // missing `.canvas` case in DrawPayload.isEquivalentForMeasurement,
        // which cascaded up the ancestor spine.  Pin it here too so any
        // future regression in the canvas equivalence walk fires this
        // test, not just the gallery smoke test.
        Canvas(ProbeCanvasDrawing(value: 7))
          .frame(width: 30, height: 4)
      }
    }

    // Frame 1: seed render at phase 0, no animation intent.
    _ = renderer.render(
      body(phase: 0),
      context: ResolveContext(identity: rootIdentity),
      proposal: ProposedSize(width: .finite(40), height: .finite(20))
    )

    // Mirror the run loop's "after first frame" switch into selective
    // dirty evaluation, so subsequent renders take the same code paths
    // a real tick frame would take.
    renderer.enableSelectiveEvaluation()

    // Frame 2: explicit animate transaction starts the chasing-light
    // animation.  This is the equivalent of the run loop committing
    // `.onAppear { withAnimation(...) { gradientPhase = 1.0 } }`.
    var animateTransaction = TransactionSnapshot()
    animateTransaction.animationRequest = .animate(animation.animationBox)
    _ = renderer.render(
      body(phase: 1.0),
      context: ResolveContext(
        identity: rootIdentity,
        transaction: animateTransaction
      ),
      proposal: ProposedSize(width: .finite(40), height: .finite(20))
    )

    // Drive `tickCount` tick frames.  Each tick constructs the same
    // view (phase unchanged at the @State level — the animation
    // controller is what drives the per-frame interpolation) with a
    // bare `.inherit` transaction.  Phase 4 stopped injecting the
    // controller's "dominant active request" on tick frames — the
    // controller's diff path correctly leaves an in-flight animation
    // alone when the next frame's snapshot matches its target value
    // (the early `previous == current` guard in
    // `enqueueSlotChangeIfNeeded`), so tick frames don't need to
    // re-announce the animation intent.
    var measureCounts: [Int] = []
    var activeAnimationCounts: [Int] = []
    for _ in 0..<tickCount {
      var tickTransaction = TransactionSnapshot()
      tickTransaction.animationRequest = .inherit
      let artifacts = renderer.render(
        body(phase: 1.0),
        context: ResolveContext(
          identity: rootIdentity,
          transaction: tickTransaction
        ),
        proposal: ProposedSize(width: .finite(40), height: .finite(20))
      )
      measureCounts.append(artifacts.diagnostics.measuredNodesComputed)
      activeAnimationCounts.append(controller.activeAnimationCount)
    }

    let maxMeasured = measureCounts.max() ?? 0
    #expect(
      maxMeasured == 0,
      """
      tick frames must reuse 100% of the measurement cache; \
      maxMeasuredNodesComputed=\(maxMeasured) \
      counts@[0,1,9,49]=\
      [\(measureCounts.first ?? -1),\
      \(measureCounts.dropFirst().first ?? -1),\
      \(measureCounts.dropFirst(9).first ?? -1),\
      \(measureCounts.dropFirst(49).first ?? -1)]
      """
    )

    let maxActive = activeAnimationCounts.max() ?? 0
    let firstActive = activeAnimationCounts.first ?? 0
    #expect(
      maxActive <= firstActive,
      """
      activeAnimationCount must stay bounded across repeatForever ticks; \
      first=\(firstActive) max=\(maxActive)
      """
    )
  }

  @Test("onAppear-started repeatForever keeps runtime bookkeeping bounded across tick frames")
  func onAppearStartedRepeatForeverKeepsRuntimeBookkeepingBounded() throws {
    let terminalSize = CellSize(width: 40, height: 10)
    let rootIdentity = testIdentity("OnAppearRepeatForeverGrowth", "Root")
    let terminal = RepeatForeverGrowthTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      terminalInputReader: EmptyTerminalInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        OnAppearRepeatForeverProbe()
      }
    )

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    scheduler.requestInvalidation(of: [rootIdentity])

    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    if scheduler.hasPendingFrame(at: .now()) {
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    }

    let controller = runLoop.renderer.internalAnimationController
    let initialActive = controller.activeAnimationCount
    let initialLifecycleSnapshot = runLoop.localLifecycleRegistry.snapshot()
    let initialAppearHandlers = initialLifecycleSnapshot.appearHandlers.count
    let initialDisappearHandlers = initialLifecycleSnapshot.disappearHandlers.count

    #expect(
      initialActive > 0,
      "runtime startup must actually enqueue the repeatForever animation"
    )

    var activeCounts: [Int] = [initialActive]
    var appearHandlerCounts: [Int] = [initialAppearHandlers]
    var disappearHandlerCounts: [Int] = [initialDisappearHandlers]
    var resolvedNodeTotals: [Int] = []
    var placedNodeTotals: [Int] = []
    var measuredNodeCounts: [Int] = []

    for _ in 0..<80 {
      let frame = ScheduledFrame(
        causes: [.deadline],
        invalidatedIdentities: [],
        signalNames: [],
        externalReasons: [],
        triggeredDeadline: nil,
        nextDeadline: nil
      )
      let artifacts = runLoop.renderer.render(
        runLoop.viewBuilder(
          (
            state: runLoop.stateContainer.state,
            focusedIdentity: runLoop.focusTracker.currentFocusIdentity
          )),
        context: runLoop.resolveContext(for: frame),
        proposal: runLoop.proposal()
      )
      runLoop.lifecycleCoordinator.applyCommittedFrame(
        plan: artifacts.commitPlan,
        currentLifecycleRegistry: runLoop.localLifecycleRegistry,
        currentTaskRegistry: runLoop.localTaskRegistry
      )
      resolvedNodeTotals.append(artifacts.diagnostics.resolvedNodeCount)
      placedNodeTotals.append(artifacts.diagnostics.placedNodeCount)
      measuredNodeCounts.append(artifacts.diagnostics.measuredNodesComputed)
      activeCounts.append(controller.activeAnimationCount)
      let lifecycleSnapshot = runLoop.localLifecycleRegistry.snapshot()
      appearHandlerCounts.append(lifecycleSnapshot.appearHandlers.count)
      disappearHandlerCounts.append(lifecycleSnapshot.disappearHandlers.count)
    }

    #expect(
      (activeCounts.max() ?? 0) <= initialActive,
      """
      active animation bookkeeping must stay bounded once the repeatForever \
      animation is in flight; initial=\(initialActive) \
      counts@[0,1,9,39,79]=[
      \(activeCounts.first ?? -1),
      \(activeCounts.dropFirst().first ?? -1),
      \(activeCounts.dropFirst(9).first ?? -1),
      \(activeCounts.dropFirst(39).first ?? -1),
      \(activeCounts.dropFirst(79).first ?? -1)
      ]
      """
    )
    #expect(
      (appearHandlerCounts.max() ?? 0) <= initialAppearHandlers,
      """
      .onAppear registrations must not accumulate across animation ticks; \
      initial=\(initialAppearHandlers) max=\(appearHandlerCounts.max() ?? -1)
      """
    )
    #expect(
      (disappearHandlerCounts.max() ?? 0) <= initialDisappearHandlers,
      """
      .onDisappear registrations must not accumulate across animation ticks; \
      initial=\(initialDisappearHandlers) max=\(disappearHandlerCounts.max() ?? -1)
      """
    )
    #expect(
      (measuredNodeCounts.max() ?? 0) == 0,
      """
      synthetic tick frames should reuse the measurement cache completely; \
      maxMeasured=\(measuredNodeCounts.max() ?? -1)
      """
    )
    #expect(
      (resolvedNodeTotals.max() ?? 0) == (resolvedNodeTotals.min() ?? 0),
      """
      resolved tree size must stay constant across synthetic ticks; \
      min=\(resolvedNodeTotals.min() ?? -1) max=\(resolvedNodeTotals.max() ?? -1)
      """
    )
    #expect(
      (placedNodeTotals.max() ?? 0) == (placedNodeTotals.min() ?? 0),
      """
      placed tree size must stay constant across synthetic ticks; \
      min=\(placedNodeTotals.min() ?? -1) max=\(placedNodeTotals.max() ?? -1)
      """
    )
  }

  @Test("tab-hosted repeatForever keeps runtime bookkeeping bounded across tick frames")
  func tabHostedRepeatForeverKeepsRuntimeBookkeepingBounded() throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = testIdentity("TabHostedRepeatForeverGrowth", "Root")
    let terminal = RepeatForeverGrowthTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      terminalInputReader: EmptyTerminalInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        TabHostedRepeatForeverProbe()
      }
    )

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    scheduler.requestInvalidation(of: [rootIdentity])

    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    if scheduler.hasPendingFrame(at: .now()) {
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    }

    let controller = runLoop.renderer.internalAnimationController
    let initialActive = controller.activeAnimationCount
    let initialLifecycleSnapshot = runLoop.localLifecycleRegistry.snapshot()

    #expect(
      initialActive > 0,
      "tab-hosted runtime startup must actually enqueue the repeatForever animation"
    )

    var activeCounts: [Int] = [initialActive]
    var appearHandlerCounts: [Int] = [initialLifecycleSnapshot.appearHandlers.count]
    var disappearHandlerCounts: [Int] = [initialLifecycleSnapshot.disappearHandlers.count]
    var resolvedNodeTotals: [Int] = []
    var placedNodeTotals: [Int] = []
    var resolvedNodeCounts: [Int] = []
    var measuredNodeCounts: [Int] = []

    for _ in 0..<80 {
      let frame = ScheduledFrame(
        causes: [.deadline],
        invalidatedIdentities: [],
        signalNames: [],
        externalReasons: [],
        triggeredDeadline: nil,
        nextDeadline: nil
      )
      let artifacts = runLoop.renderer.render(
        runLoop.viewBuilder(
          (
            state: runLoop.stateContainer.state,
            focusedIdentity: runLoop.focusTracker.currentFocusIdentity
          )),
        context: runLoop.resolveContext(for: frame),
        proposal: runLoop.proposal()
      )
      runLoop.lifecycleCoordinator.applyCommittedFrame(
        plan: artifacts.commitPlan,
        currentLifecycleRegistry: runLoop.localLifecycleRegistry,
        currentTaskRegistry: runLoop.localTaskRegistry
      )
      resolvedNodeTotals.append(artifacts.diagnostics.resolvedNodeCount)
      placedNodeTotals.append(artifacts.diagnostics.placedNodeCount)
      resolvedNodeCounts.append(artifacts.diagnostics.resolvedNodesComputed)
      measuredNodeCounts.append(artifacts.diagnostics.measuredNodesComputed)
      activeCounts.append(controller.activeAnimationCount)
      let lifecycleSnapshot = runLoop.localLifecycleRegistry.snapshot()
      appearHandlerCounts.append(lifecycleSnapshot.appearHandlers.count)
      disappearHandlerCounts.append(lifecycleSnapshot.disappearHandlers.count)
    }

    #expect(
      (activeCounts.max() ?? 0) <= initialActive,
      """
      active animation bookkeeping must stay bounded for the tab-hosted \
      repeatForever probe; initial=\(initialActive) \
      max=\(activeCounts.max() ?? -1)
      """
    )
    #expect(
      (appearHandlerCounts.max() ?? 0) <= appearHandlerCounts[0],
      """
      tab-hosted .onAppear registrations must not accumulate across ticks; \
      initial=\(appearHandlerCounts[0]) max=\(appearHandlerCounts.max() ?? -1)
      """
    )
    #expect(
      (disappearHandlerCounts.max() ?? 0) <= disappearHandlerCounts[0],
      """
      tab-hosted .onDisappear registrations must not accumulate across ticks; \
      initial=\(disappearHandlerCounts[0]) max=\(disappearHandlerCounts.max() ?? -1)
      """
    )
    #expect(
      (resolvedNodeCounts.max() ?? 0) == 0,
      """
      synthetic tick frames should not re-resolve the tab-hosted probe; \
      maxResolved=\(resolvedNodeCounts.max() ?? -1)
      """
    )
    #expect(
      (measuredNodeCounts.max() ?? 0) == 0,
      """
      synthetic tick frames should reuse the measurement cache for the \
      tab-hosted probe; maxMeasured=\(measuredNodeCounts.max() ?? -1)
      """
    )
    #expect(
      (resolvedNodeTotals.max() ?? 0) == (resolvedNodeTotals.min() ?? 0),
      """
      tab-hosted resolved tree size must stay constant across synthetic ticks; \
      min=\(resolvedNodeTotals.min() ?? -1) max=\(resolvedNodeTotals.max() ?? -1)
      """
    )
    #expect(
      (placedNodeTotals.max() ?? 0) == (placedNodeTotals.min() ?? 0),
      """
      tab-hosted placed tree size must stay constant across synthetic ticks; \
      min=\(placedNodeTotals.min() ?? -1) max=\(placedNodeTotals.max() ?? -1)
      """
    )
  }

  @Test("nested child-owned onAppear repeatForever enqueues the initial animation")
  func nestedChildOwnedOnAppearRepeatForeverEnqueuesInitialAnimation() throws {
    let terminalSize = CellSize(width: 40, height: 10)
    let rootIdentity = testIdentity("NestedChildOwnedRepeatForever", "Root")
    let terminal = RepeatForeverGrowthTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      terminalInputReader: EmptyTerminalInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        NestedChildOwnedRepeatForeverHost()
      }
    )

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    scheduler.requestInvalidation(of: [rootIdentity])

    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(
      renderedFrames >= 2,
      "expected initial mount plus the onAppear-triggered follow-up frame"
    )
    #expect(
      runLoop.renderer.internalAnimationController.activeAnimationCount > 0,
      """
      nested child-owned repeatForever should enqueue an active animation after \
      the onAppear-triggered follow-up frame
      """
    )
  }

  @MainActor
  @Test(
    "run loop keeps ticking repeatForever animations even when the next deadline is already due")
  func runLoopContinuesOverdueRepeatForeverDeadlines() async throws {
    let terminalSize = CellSize(width: 40, height: 10)
    let rootIdentity = testIdentity("OverdueRepeatForeverDeadline", "Root")
    let terminal = SlowPresentTerminalHost(
      surfaceSize: terminalSize,
      presentDelayMicroseconds: 40_000
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      terminalInputReader: DelayedQuitTerminalInputReader(
        delayNanoseconds: 200_000_000
      ),
      signalReader: nil,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        OnAppearRepeatForeverProbe()
      }
    )

    let result = try await runLoop.run()

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(
      result.renderedFrames >= 3,
      """
      repeatForever animation should keep producing frames even when \
      presentation overruns the 33 ms frame interval; renderedFrames=\(result.renderedFrames)
      """
    )
  }
}

/// Test-only ``CanvasDrawing`` whose `==` distinguishes drawings by an
/// integer payload.  Used by the canvas-equivalence pins above.
private struct ProbeCanvasDrawing: CanvasDrawing, Equatable {
  let value: Int

  func draw(into context: inout CanvasContext) {
    // No-op: the layout cache reuse contract is independent of what
    // the drawing actually paints.
  }
}

private struct OnAppearRepeatForeverProbe: View {
  @State private var phase: Double = 0

  var body: some View {
    Text("probe")
      .padding(1)
      .frame(width: 20, height: 3)
      .border(
        blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .magenta, .red]),
        set: .rounded,
        phase: phase
      )
      .onAppear {
        withAnimation(
          .linear(duration: .milliseconds(3000))
            .repeatForever(autoreverses: false)
        ) {
          phase = 1.0
        }
      }
  }
}

private struct TabHostedRepeatForeverProbe: View {
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
      Tab("Animated", value: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 1) {
            OnAppearRepeatForeverProbe()
            Canvas(ProbeCanvasDrawing(value: 7))
              .frame(width: 30, height: 4)
          }
          .padding(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      Tab("Other", value: 1) {
        Text("Other")
      }
    }
  }
}

private struct NestedChildOwnedRepeatForeverHost: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("host")
      NestedChildOwnedRepeatForeverCard()
    }
  }
}

private struct NestedChildOwnedRepeatForeverCard: View {
  @State private var phase: Double = 0

  var body: some View {
    Text("nested probe")
      .padding(1)
      .frame(width: 20, height: 3)
      .border(
        blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .magenta, .red]),
        set: .rounded,
        phase: phase
      )
      .onAppear {
        withAnimation(
          .linear(duration: .milliseconds(3000))
            .repeatForever(autoreverses: false)
        ) {
          phase = 1.0
        }
      }
  }
}

private final class RepeatForeverGrowthTerminalHost: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_: String) throws {}
}

private final class EmptyTerminalInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class DelayedQuitTerminalInputReader: TerminalInputReading {
  let delayNanoseconds: UInt64

  init(delayNanoseconds: UInt64) {
    self.delayNanoseconds = delayNanoseconds
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let delayNanoseconds = self.delayNanoseconds
      let task = Task {
        if delayNanoseconds > 0 {
          try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        continuation.yield(.key(KeyPress(.character("c"), modifiers: .ctrl)))
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class SlowPresentTerminalHost: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let presentDelayMicroseconds: useconds_t

  init(surfaceSize: CellSize, presentDelayMicroseconds: useconds_t) {
    self.surfaceSize = surfaceSize
    self.presentDelayMicroseconds = presentDelayMicroseconds
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    if presentDelayMicroseconds > 0 {
      usleep(presentDelayMicroseconds)
    }
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_: String) throws {}
}
