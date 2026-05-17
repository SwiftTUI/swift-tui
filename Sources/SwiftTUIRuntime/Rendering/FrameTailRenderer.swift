import SwiftTUICore
import SwiftTUIViews
import Synchronization

#if canImport(Darwin)
  import Darwin
#endif

#if canImport(Dispatch)
  @unsafe @preconcurrency import Dispatch
#endif

private final class FrameTailRetainedState: Sendable {
  private struct State: Sendable {
    var previousFrameIndex: RetainedFrameIndex?
    var previousRasterSurface: RasterSurface?
  }

  private let state = Mutex(State())

  func input(
    invalidatedIdentities: Set<Identity>
  ) -> FrameTailRetainedInput {
    state.withLock { state in
      .init(
        retainedLayout: RetainedLayoutSession(
          previousFrameIndex: state.previousFrameIndex,
          invalidatedIdentities: invalidatedIdentities
        ),
        previousRasterSurface: state.previousRasterSurface
      )
    }
  }

  /// Stores the frame's artifacts so the next frame's pipeline can
  /// reuse cached layout.
  ///
  /// `baselinePlacedTree` is the **pre-overlay** placed tree — the
  /// canonical layout result from `LayoutEngine.place`, before the
  /// animation controller injected any transient removal overlays.
  /// The retained-layout cache indexes this baseline so future tick
  /// frames reuse stable bounds/identities rather than the
  /// animation-decorated tree; overlays are re-injected from the
  /// controller's own removal-entry state on each tick.
  ///
  /// When no overlays were injected this frame, pass the same
  /// `placedTree` as baseline — the two are identical.
  func storeCommittedFrame(
    _ artifacts: FrameArtifacts,
    baselinePlacedTree: PlacedNode
  ) {
    var indexable = artifacts
    indexable.placedTree = baselinePlacedTree
    state.withLock { state in
      state.previousFrameIndex = .init(frame: indexable)
      state.previousRasterSurface = artifacts.rasterSurface
    }
  }
}

struct FrameTailRetainedInput {
  var retainedLayout: RetainedLayoutSession
  var previousRasterSurface: RasterSurface?
}

struct FrameTailInput {
  var generation: RenderGeneration
  var resolved: ResolvedNode
  var proposal: ProposedSize
  var rootIdentity: Identity
  var retained: FrameTailRetainedInput
  var layoutPassContext: LayoutPassContext
}

struct FrameTailDiagnostics {
  var measureDuration: Duration
  var placeDuration: Duration
  var semanticsDuration: Duration
  var drawDuration: Duration
  var rasterDuration: Duration
  var layoutWork: LayoutWorkMetrics
  var workerTimings: FrameWorkerTimings?
  var measurementCache: MeasurementCacheMetrics?
}

struct FrameTailLayoutOutput {
  var generation: RenderGeneration
  var measured: MeasuredNode
  var baselinePlaced: PlacedNode
  var measureDuration: Duration
  var placeDuration: Duration
  var layoutWork: LayoutWorkMetrics
  var workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate]
  var workerEnqueueToStart: Duration
  var workerCompute: Duration
  var ranOffMain: Bool
}

struct ReconciledFrameTailLayout {
  var input: FrameTailInput
  var layout: FrameTailLayoutOutput
  var resolved: ResolvedNode
  var runtimeIssues: [RuntimeIssue]
}

private struct FrameTailSemanticsOutput {
  var semantics: SemanticSnapshot
  var duration: Duration
}

private struct FrameTailDrawOutput {
  var draw: DrawNode
  var duration: Duration
}

private struct FrameTailRasterOutput {
  var surface: RasterSurface
  var drawnIdentities: Set<Identity>
  var presentationDamage: PresentationDamage?
  var duration: Duration
}

struct FrameTailOutput {
  var generation: RenderGeneration
  var measured: MeasuredNode
  var placed: PlacedNode
  var baselinePlaced: PlacedNode
  var semantics: SemanticSnapshot
  var draw: DrawNode
  var raster: RasterSurface
  var drawnIdentities: Set<Identity>
  var presentationDamage: PresentationDamage?
  var diagnostics: FrameTailDiagnostics
  var workerCompletedAt: ContinuousClock.Instant?
}

package enum FrameTailJobState: String, Sendable {
  case queued
  case started
  case completed
  case cancelledBeforeStart = "cancelled_before_start"
  case droppedCompleted = "dropped_completed"
}

package struct CancellableRenderOutcome {
  package var artifacts: FrameArtifacts?
  package var runtimeIssues: [RuntimeIssue]
  package var renderGeneration: RenderGeneration
  package var newestDesiredGeneration: RenderGeneration?
  package var tailJobState: FrameTailJobState
  package var tailCancelReason: String?
  package var completedFrameDropDecision: CompletedFrameDropDecision?
}

final class FrameTailJobCancellationToken: Sendable {
  private let state = Mutex<FrameTailJobState>(.queued)

  var currentState: FrameTailJobState {
    state.withLock { $0 }
  }

  func cancelBeforeStart() -> Bool {
    state.withLock { state in
      guard state == .queued else {
        return false
      }
      state = .cancelledBeforeStart
      return true
    }
  }

  func markStarted() -> Bool {
    state.withLock { state in
      switch state {
      case .queued:
        state = .started
        return true
      case .cancelledBeforeStart:
        return false
      case .started, .completed, .droppedCompleted:
        return true
      }
    }
  }

  func markCompleted() {
    state.withLock { state in
      if state == .started {
        state = .completed
      }
    }
  }
}

package struct FrameHeadDraft {
  var clock: ContinuousClock?
  var renderGeneration: RenderGeneration
  var registrationDraft: FrameHeadRegistrationDraft
  var viewGraphCheckpoint: ViewGraph.Checkpoint
  var frameStateCheckpoint: FrameResolveState.Checkpoint
  var presentationPortalCheckpoint: PresentationPortalState.Checkpoint
  var observationBridge: ObservationBridge?
  var observationBridgeCheckpoint: ObservationBridge.Checkpoint?
  var resolveContext: ResolveContext
  var graphRootIdentity: Identity
  var frameContext: FrameContext
  var resolved: ResolvedNode
  var frameTailInput: FrameTailInput
  var runtimeIssues: [RuntimeIssue]
  var animationTimestamp: MonotonicInstant
  var resolveDuration: Duration
  var animationCheckpoint: AnimationController.Checkpoint
}

struct AsyncFrameTailDraftOutput {
  var frameTailInput: FrameTailInput
  var layout: FrameTailLayoutOutput
  var tail: FrameTailOutput
  var resolved: ResolvedNode
  var runtimeIssues: [RuntimeIssue]
  var renderSuspensionDuration: Duration
}

struct CompletedFrameCandidate {
  var draft: FrameHeadDraft
  var tailOutput: AsyncFrameTailDraftOutput
  var resolved: ResolvedNode
  var workerTimings: FrameWorkerTimings?
  var collectsDiagnostics: Bool
  var previewArtifacts: FrameArtifacts
  var eligibility: FrameDropEligibility
  var newestDesiredGeneration: RenderGeneration
  var dropDecision: CompletedFrameDropDecision
}

enum CancellableFrameTailResult {
  case output(AsyncFrameTailDraftOutput)
  case cancelledBeforeStart
}

private struct FrameTailWorkerResult<Value> {
  var value: Value
  var enqueueToStart: Duration
  var compute: Duration
  var completedAt: ContinuousClock.Instant?
}

final class RenderGenerationSequencer: Sendable {
  private let nextRawValue = Mutex<UInt64>(1)

  func next() -> RenderGeneration {
    nextRawValue.withLock { value in
      let generation = RenderGeneration(value)
      value &+= 1
      return generation
    }
  }
}

private final class FrameTailLayoutWorkerBox: Sendable {
  private let storage = Mutex<FrameTailLayoutWorker?>(nil)

  func async<Value>(
    _ operation: @escaping @Sendable () -> Value
  ) async -> Value {
    let worker = storage.withLock { storage in
      if let storage {
        return storage
      }
      let worker = FrameTailLayoutWorker()
      storage = worker
      return worker
    }
    return await worker.async(operation)
  }
}

#if canImport(Darwin) && canImport(Dispatch)
  @safe private final class FrameTailLayoutWorkerState: Sendable {
    struct Job: Sendable {
      var operation: @Sendable () -> Void
    }

    private enum NextJob {
      case job(Job)
      case idle
      case stop
    }

    private struct State: Sendable {
      var jobs: [Job] = []
      var isStopping = false
    }

    private let state = Mutex(State())
    private let semaphore = DispatchSemaphore(value: 0)

    func enqueue(_ job: Job) {
      state.withLock { state in
        state.jobs.append(job)
      }
      semaphore.signal()
    }

    func stop() {
      state.withLock { state in
        state.isStopping = true
      }
      semaphore.signal()
    }

    func runLoop() {
      unsafe pthread_setname_np("swift-tui.frame-tail-layout")

      while true {
        semaphore.wait()

        drainJobs: while true {
          switch nextJob() {
          case .job(let job):
            job.operation()
          case .idle:
            break drainJobs
          case .stop:
            return
          }
        }
      }
    }

    private func nextJob() -> NextJob {
      state.withLock { state in
        if !state.jobs.isEmpty {
          return .job(state.jobs.removeFirst())
        }
        if state.isStopping {
          return .stop
        }
        return .idle
      }
    }
  }

  @safe private final class FrameTailLayoutWorker: Sendable {
    private static let stackSize = 8 * 1024 * 1024

    private let state: FrameTailLayoutWorkerState
    private let thread: UInt?
    private let fallbackQueue = DispatchQueue(label: "swift-tui.frame-tail-layout-fallback")

    init() {
      let state = FrameTailLayoutWorkerState()
      self.state = state
      thread = Self.startThread(state: state)
    }

    deinit {
      stopThread()
    }

    func async<Value>(
      _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
      await withCheckedContinuation { continuation in
        enqueue(
          FrameTailLayoutWorkerState.Job {
            continuation.resume(returning: operation())
          }
        )
      }
    }

    private static func startThread(
      state: FrameTailLayoutWorkerState
    ) -> UInt? {
      var attributes = pthread_attr_t()
      guard unsafe pthread_attr_init(&attributes) == 0 else {
        return nil
      }
      defer {
        unsafe pthread_attr_destroy(&attributes)
      }

      _ = unsafe pthread_attr_setstacksize(&attributes, Self.stackSize)

      var createdThread: pthread_t?
      let retainedState = unsafe Unmanaged.passRetained(state)
      let result = unsafe pthread_create(
        &createdThread,
        &attributes,
        { pointer in
          let state = unsafe Unmanaged<FrameTailLayoutWorkerState>
            .fromOpaque(pointer)
            .takeRetainedValue()
          state.runLoop()
          return nil
        },
        unsafe retainedState.toOpaque()
      )

      guard result == 0 else {
        unsafe retainedState.release()
        return nil
      }
      guard unsafe createdThread != nil else {
        unsafe retainedState.release()
        return nil
      }
      return UInt(bitPattern: unsafe createdThread!)
    }

    private func stopThread() {
      guard
        let thread,
        let currentThread = unsafe pthread_t(bitPattern: thread)
      else {
        return
      }
      guard unsafe pthread_equal(pthread_self(), currentThread) == 0 else {
        return
      }

      state.stop()
      unsafe pthread_join(currentThread, nil)
    }

    private func enqueue(_ job: FrameTailLayoutWorkerState.Job) {
      guard thread != nil else {
        fallbackQueue.async {
          job.operation()
        }
        return
      }

      state.enqueue(job)
    }
  }
#elseif canImport(Dispatch)
  private final class FrameTailLayoutWorker: Sendable {
    private let queue = DispatchQueue(label: "swift-tui.frame-tail-layout")

    func async<Value>(
      _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
      await withCheckedContinuation { continuation in
        queue.async {
          continuation.resume(returning: operation())
        }
      }
    }
  }
#else
  private final class FrameTailLayoutWorker: Sendable {
    func async<Value>(
      _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
      operation()
    }
  }
#endif

package struct FrameTailRenderHooks: Sendable {
  package var beforeLayout: (@Sendable () -> Void)?
  package var beforeRaster: (@Sendable () -> Void)?

  package init(
    beforeLayout: (@Sendable () -> Void)? = nil,
    beforeRaster: (@Sendable () -> Void)? = nil
  ) {
    self.beforeLayout = beforeLayout
    self.beforeRaster = beforeRaster
  }
}

package struct FrameRenderSuspensionHooks: Sendable {
  package var onBegin: (@Sendable () -> Void)?
  package var onEnd: (@Sendable () -> Void)?

  package init(
    onBegin: (@Sendable () -> Void)? = nil,
    onEnd: (@Sendable () -> Void)? = nil
  ) {
    self.onBegin = onBegin
    self.onEnd = onEnd
  }
}

final class FrameTailRenderer: Sendable {
  private let layoutEngine: LayoutEngine
  private let semanticExtractor: SemanticExtractor
  private let drawExtractor: DrawExtractor
  private let rasterizer: Rasterizer
  private let retainedState = FrameTailRetainedState()
  private let renderHooks = Mutex<FrameTailRenderHooks?>(nil)
  private let suspensionHooks = Mutex<FrameRenderSuspensionHooks?>(nil)
  private let layoutWorker = FrameTailLayoutWorkerBox()

  #if canImport(Dispatch)
    private let queue = DispatchQueue(label: "swift-tui.frame-tail-renderer")
  #endif

  init(
    layoutEngine: LayoutEngine,
    semanticExtractor: SemanticExtractor,
    drawExtractor: DrawExtractor,
    rasterizer: Rasterizer
  ) {
    self.layoutEngine = layoutEngine
    self.semanticExtractor = semanticExtractor
    self.drawExtractor = drawExtractor
    self.rasterizer = rasterizer
  }

  func retainedInput(
    invalidatedIdentities: Set<Identity>
  ) -> FrameTailRetainedInput {
    sync {
      retainedState.input(
        invalidatedIdentities: invalidatedIdentities
      )
    }
  }

  func renderLayout(
    _ input: FrameTailInput,
    clock: ContinuousClock?
  ) -> FrameTailLayoutOutput {
    renderLayoutInline(
      input,
      clock: clock
    )
  }

  func renderLayoutAsync(
    _ input: FrameTailInput,
    clock: ContinuousClock?,
    cancellationToken: FrameTailJobCancellationToken? = nil
  ) async -> FrameTailLayoutOutput? {
    if containsLayoutDependentContent(input.resolved) {
      input.layoutPassContext.updateWorkMetrics {
        $0.layoutDependentMainActorFallbacks += 1
      }
    }
    guard canOffloadLayout(input) else {
      guard cancellationToken?.markStarted() ?? true else {
        return nil
      }
      return renderLayoutInline(
        input,
        clock: clock
      )
    }

    let result = await timedLayoutAsync(
      clock: clock,
      cancellationToken: cancellationToken
    ) {
      self.renderLayoutInline(
        input,
        clock: clock
      )
    }
    guard var output = result.value else {
      return nil
    }
    output.workerEnqueueToStart = result.enqueueToStart
    output.workerCompute = result.compute
    output.ranOffMain = true
    return output
  }

  func canOffloadLayout(
    _ input: FrameTailInput
  ) -> Bool {
    !containsMainActorOnlyCustomLayout(input.resolved)
      && !containsMainActorOnlyIndexedChildSource(input.resolved)
      && !containsLayoutDependentContent(input.resolved)
  }

  func needsIndexedChildSourceWorkerSnapshot(
    _ input: FrameTailInput
  ) -> Bool {
    !containsMainActorOnlyCustomLayout(input.resolved)
      && containsMainActorOnlyIndexedChildSource(input.resolved)
      && !containsLayoutDependentContent(input.resolved)
  }

  func renderRaster(
    _ input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot,
    clock: ContinuousClock?
  ) -> FrameTailOutput {
    let result = timedSync(clock: clock) {
      renderRasterInline(
        input,
        layout: layout,
        placed: placed,
        animationOverlaySnapshot: animationOverlaySnapshot,
        clock: clock
      )
    }
    var output = result.value
    output.diagnostics.workerTimings = .init(
      layoutEnqueueToStart: layout.workerEnqueueToStart,
      layoutCompute: layout.workerCompute,
      rasterEnqueueToStart: result.enqueueToStart,
      rasterCompute: result.compute
    )
    output.workerCompletedAt = result.completedAt
    return output
  }

  func renderRasterAsync(
    _ input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot,
    clock: ContinuousClock?
  ) async -> FrameTailOutput {
    let result = await timedAsync(clock: clock) {
      self.renderRasterInline(
        input,
        layout: layout,
        placed: placed,
        animationOverlaySnapshot: animationOverlaySnapshot,
        clock: clock
      )
    }
    var output = result.value
    output.diagnostics.workerTimings = .init(
      layoutEnqueueToStart: layout.workerEnqueueToStart,
      layoutCompute: layout.workerCompute,
      rasterEnqueueToStart: result.enqueueToStart,
      rasterCompute: result.compute
    )
    output.workerCompletedAt = result.completedAt
    return output
  }

  func pruneMeasurementCache(
    keeping identities: Set<Identity>
  ) {
    sync {
      layoutEngine.cache?.prune(keeping: identities)
    }
  }

  func storeCommittedFrame(
    _ artifacts: FrameArtifacts,
    baselinePlacedTree: PlacedNode
  ) {
    sync {
      retainedState.storeCommittedFrame(
        artifacts,
        baselinePlacedTree: baselinePlacedTree
      )
    }
  }

  func setRenderHooks(
    _ hooks: FrameTailRenderHooks?
  ) {
    renderHooks.withLock { currentHooks in
      currentHooks = hooks
    }
  }

  func setRenderSuspensionHooks(
    _ hooks: FrameRenderSuspensionHooks?
  ) {
    suspensionHooks.withLock { currentHooks in
      currentHooks = hooks
    }
  }

  func renderSuspensionHooksSnapshot() -> FrameRenderSuspensionHooks? {
    suspensionHooks.withLock { $0 }
  }

  func runLayoutWorkerJobForCancellationTesting(
    _ operation: @escaping @Sendable () -> Void
  ) async {
    _ = await layoutWorker.async(operation)
  }

  private func sync<Value>(
    _ operation: () -> Value
  ) -> Value {
    #if canImport(Dispatch)
      queue.sync {
        operation()
      }
    #else
      operation()
    #endif
  }

  private func timedSync<Value>(
    clock: ContinuousClock?,
    _ operation: () -> Value
  ) -> FrameTailWorkerResult<Value> {
    guard let clock else {
      return .init(
        value: sync(operation),
        enqueueToStart: .zero,
        compute: .zero,
        completedAt: nil
      )
    }

    let enqueuedAt = clock.now
    return sync {
      let startedAt = clock.now
      let value = operation()
      let completedAt = clock.now
      return .init(
        value: value,
        enqueueToStart: enqueuedAt.duration(to: startedAt),
        compute: startedAt.duration(to: completedAt),
        completedAt: completedAt
      )
    }
  }

  private func async<Value>(
    _ operation: @escaping @Sendable () -> Value
  ) async -> Value {
    #if canImport(Dispatch)
      await withCheckedContinuation { continuation in
        queue.async {
          continuation.resume(returning: operation())
        }
      }
    #else
      operation()
    #endif
  }

  private func timedAsync<Value>(
    clock: ContinuousClock?,
    _ operation: @escaping @Sendable () -> Value
  ) async -> FrameTailWorkerResult<Value> {
    guard let clock else {
      return .init(
        value: await async(operation),
        enqueueToStart: .zero,
        compute: .zero,
        completedAt: nil
      )
    }

    let enqueuedAt = clock.now
    return await async {
      let startedAt = clock.now
      let value = operation()
      let completedAt = clock.now
      return .init(
        value: value,
        enqueueToStart: enqueuedAt.duration(to: startedAt),
        compute: startedAt.duration(to: completedAt),
        completedAt: completedAt
      )
    }
  }

  private func timedLayoutAsync<Value>(
    clock: ContinuousClock?,
    cancellationToken: FrameTailJobCancellationToken?,
    _ operation: @escaping @Sendable () -> Value
  ) async -> FrameTailWorkerResult<Value?> {
    guard let clock else {
      return .init(
        value: await layoutWorker.async {
          guard cancellationToken?.markStarted() ?? true else {
            return nil
          }
          return operation()
        },
        enqueueToStart: .zero,
        compute: .zero,
        completedAt: nil
      )
    }

    let enqueuedAt = clock.now
    return await layoutWorker.async {
      let startedAt = clock.now
      guard cancellationToken?.markStarted() ?? true else {
        return .init(
          value: nil,
          enqueueToStart: enqueuedAt.duration(to: startedAt),
          compute: .zero,
          completedAt: startedAt
        )
      }
      let value = operation()
      let completedAt = clock.now
      return .init(
        value: Optional(value),
        enqueueToStart: enqueuedAt.duration(to: startedAt),
        compute: startedAt.duration(to: completedAt),
        completedAt: completedAt
      )
    }
  }

  private func renderLayoutInline(
    _ input: FrameTailInput,
    clock: ContinuousClock?
  ) -> FrameTailLayoutOutput {
    let beforeLayout = renderHooks.withLock { hooks in
      hooks?.beforeLayout
    }
    beforeLayout?()
    let (measured, measureDuration) = measurePhase(clock: clock) {
      layoutEngine.measure(
        input.resolved,
        proposal: input.proposal,
        passContext: input.layoutPassContext
      )
    }
    let (placed, placeDuration) = measurePhase(clock: clock) {
      layoutEngine.place(
        input.resolved,
        measured: measured,
        passContext: input.layoutPassContext
      )
    }
    return FrameTailLayoutOutput(
      generation: input.generation,
      measured: measured,
      baselinePlaced: placed,
      measureDuration: measureDuration,
      placeDuration: placeDuration,
      layoutWork: input.layoutPassContext.workMetrics,
      workerCustomLayoutCacheUpdates: input.layoutPassContext.workerCustomLayoutCacheUpdates,
      workerEnqueueToStart: .zero,
      workerCompute: .zero,
      ranOffMain: false
    )
  }

  private func containsMainActorOnlyCustomLayout(
    _ node: ResolvedNode
  ) -> Bool {
    if case .custom(let handle) = node.layoutBehavior,
      !handle.canRunOnWorker
    {
      return true
    }
    if let workerChildren = node.indexedChildSource?.workerResolvedChildren,
      workerChildren.contains(where: containsMainActorOnlyCustomLayout)
    {
      return true
    }
    return node.children.contains { containsMainActorOnlyCustomLayout($0) }
  }

  private func containsMainActorOnlyIndexedChildSource(
    _ node: ResolvedNode
  ) -> Bool {
    if let source = node.indexedChildSource {
      if !source.canRunOnWorker {
        return true
      }
      if let workerChildren = source.workerResolvedChildren,
        workerChildren.contains(where: containsMainActorOnlyIndexedChildSource)
      {
        return true
      }
    }
    return node.children.contains { containsMainActorOnlyIndexedChildSource($0) }
  }

  private func containsLayoutDependentContent(
    _ node: ResolvedNode
  ) -> Bool {
    if node.layoutDependentContent != nil {
      return true
    }
    if let workerChildren = node.indexedChildSource?.workerResolvedChildren,
      workerChildren.contains(where: containsLayoutDependentContent)
    {
      return true
    }
    return node.children.contains { containsLayoutDependentContent($0) }
  }

  private func renderRasterInline(
    _ input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot,
    clock: ContinuousClock?
  ) -> FrameTailOutput {
    var placed = placed
    applyPlacedAnimationOverlaySnapshot(
      animationOverlaySnapshot,
      to: &placed
    )
    let presentationDamage = presentationDamage(
      rootIdentity: input.rootIdentity,
      placed: placed,
      retainedLayout: input.retained.retainedLayout
    )
    let semantics = renderSemantics(
      placed: placed,
      clock: clock
    )
    let draw = renderDraw(
      placed: placed,
      clock: clock
    )
    let raster = renderRasterSurface(
      input,
      draw: draw.draw,
      presentationDamage: presentationDamage,
      clock: clock
    )
    let diagnostics = FrameTailDiagnostics(
      measureDuration: layout.measureDuration,
      placeDuration: layout.placeDuration,
      semanticsDuration: semantics.duration,
      drawDuration: draw.duration,
      rasterDuration: raster.duration,
      layoutWork: layout.layoutWork,
      workerTimings: nil,
      measurementCache: layoutEngine.cache?.metrics
    )
    return FrameTailOutput(
      generation: input.generation,
      measured: layout.measured,
      placed: placed,
      baselinePlaced: layout.baselinePlaced,
      semantics: semantics.semantics,
      draw: draw.draw,
      raster: raster.surface,
      drawnIdentities: raster.drawnIdentities,
      presentationDamage: raster.presentationDamage,
      diagnostics: diagnostics,
      workerCompletedAt: nil
    )
  }

  private func renderSemantics(
    placed: PlacedNode,
    clock: ContinuousClock?
  ) -> FrameTailSemanticsOutput {
    let (semantics, duration) = measurePhase(clock: clock) {
      semanticExtractor.extract(from: placed)
    }
    return .init(
      semantics: semantics,
      duration: duration
    )
  }

  private func renderDraw(
    placed: PlacedNode,
    clock: ContinuousClock?
  ) -> FrameTailDrawOutput {
    let (draw, duration) = measurePhase(clock: clock) {
      drawExtractor.extract(from: placed)
    }
    return .init(
      draw: draw,
      duration: duration
    )
  }

  private func renderRasterSurface(
    _ input: FrameTailInput,
    draw: DrawNode,
    presentationDamage: PresentationDamage?,
    clock: ContinuousClock?
  ) -> FrameTailRasterOutput {
    let beforeRaster = renderHooks.withLock { hooks in
      hooks?.beforeRaster
    }
    beforeRaster?()
    let (rasterized, duration) = measurePhase(clock: clock) {
      rasterizer.rasterizeCollectingVisibleIdentities(
        draw,
        minimumSize: minimumRasterSurfaceSize(for: input.proposal),
        previousSurface: input.retained.previousRasterSurface,
        damage: presentationDamage
      )
    }
    return .init(
      surface: rasterized.surface,
      drawnIdentities: rasterized.visibleIdentities,
      presentationDamage: rasterized.presentationDamage,
      duration: duration
    )
  }

  private func measurePhase<Value>(
    clock: ContinuousClock?,
    _ operation: () -> Value
  ) -> (Value, Duration) {
    guard let clock else {
      return (operation(), .zero)
    }
    let start = clock.now
    let value = operation()
    return (value, start.duration(to: clock.now))
  }

  private func minimumRasterSurfaceSize(
    for proposal: ProposedSize
  ) -> CellSize {
    guard
      case .finite(let width) = proposal.width,
      case .finite(let height) = proposal.height
    else {
      return .zero
    }

    return .init(
      width: max(0, width),
      height: max(0, height)
    )
  }

  private func presentationDamage(
    rootIdentity: Identity,
    placed: PlacedNode,
    retainedLayout: RetainedLayoutSession?
  ) -> PresentationDamage? {
    guard let retainedLayout,
      let previousFrameIndex = retainedLayout.previousFrameIndex
    else {
      return nil
    }

    let directlyInvalidated = retainedLayout.invalidationSummary.directlyInvalidated
    guard !directlyInvalidated.isEmpty, !directlyInvalidated.contains(rootIdentity) else {
      return nil
    }

    var currentPlacedByIdentity: [Identity: PlacedNode] = [:]
    indexPlacedNodes(placed, into: &currentPlacedByIdentity)

    var textRowRanges: [Int: [Range<Int>]] = [:]
    for identity in directlyInvalidated {
      guard previousFrameIndex.resolvedNode(for: identity) != nil else {
        return nil
      }
      guard
        let previousPath = placedPath(
          to: identity,
          in: previousFrameIndex.placedByIdentity
        ),
        let currentPath = placedPath(
          to: identity,
          in: currentPlacedByIdentity
        ),
        cleanSiblingBoundsAreStable(
          previousPath: previousPath,
          currentPath: currentPath
        )
      else {
        return nil
      }
      let previousPlaced = previousPath.last
      let currentPlaced = currentPath.last

      if let previousBounds = previousPlaced?.bounds {
        textRows(for: previousBounds, into: &textRowRanges)
      }
      if let currentBounds = currentPlaced?.bounds {
        textRows(for: currentBounds, into: &textRowRanges)
      }
    }

    return .init(
      textRows: textRowRanges.keys.sorted().map { row in
        .init(
          row: row,
          columnRanges: textRowRanges[row] ?? []
        )
      }
    )
  }

  private func placedPath(
    to identity: Identity,
    in index: [Identity: PlacedNode]
  ) -> [PlacedNode]? {
    var identities: [Identity] = []
    var currentIdentity: Identity? = identity

    while let current = currentIdentity {
      guard index[current] != nil else {
        return nil
      }
      identities.append(current)
      currentIdentity = current.parent
    }

    return identities.reversed().compactMap { index[$0] }
  }

  private func cleanSiblingBoundsAreStable(
    previousPath: [PlacedNode],
    currentPath: [PlacedNode]
  ) -> Bool {
    guard previousPath.count == currentPath.count, previousPath.count > 1 else {
      return previousPath.count == currentPath.count
    }

    for index in previousPath.indices.dropLast() {
      let previousAncestor = previousPath[index]
      let currentAncestor = currentPath[index]
      let dirtyChildIdentity = previousPath[index + 1].identity
      let previousChildren = previousAncestor.children
      let currentChildren = currentAncestor.children

      guard
        previousChildren.map(\.identity) == currentChildren.map(\.identity)
      else {
        return false
      }

      for (previousChild, currentChild) in zip(previousChildren, currentChildren)
      where previousChild.identity != dirtyChildIdentity {
        guard previousChild.bounds == currentChild.bounds else {
          return false
        }
      }
    }

    return true
  }

  private func indexPlacedNodes(
    _ node: PlacedNode,
    into storage: inout [Identity: PlacedNode]
  ) {
    storage[node.identity] = node
    for child in node.children {
      indexPlacedNodes(child, into: &storage)
    }
  }

  private func textRows(
    for bounds: CellRect,
    into textRowRanges: inout [Int: [Range<Int>]]
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let lowerBound = max(0, bounds.origin.y)
    let upperBound = max(lowerBound, bounds.origin.y + bounds.size.height)
    let leadingColumn = max(0, bounds.origin.x)
    let trailingColumn = max(leadingColumn, bounds.origin.x + bounds.size.width)
    guard leadingColumn < trailingColumn else {
      return
    }

    for row in lowerBound..<upperBound {
      textRowRanges[row, default: []].append(leadingColumn..<trailingColumn)
    }
  }
}
