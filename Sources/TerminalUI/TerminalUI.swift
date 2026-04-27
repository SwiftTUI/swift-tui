@_exported import Core
@_exported import EmbeddedFonts
import Synchronization
@_exported import View

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

private struct FrameTailRetainedInput {
  var retainedLayout: RetainedLayoutSession
  var previousRasterSurface: RasterSurface?
}

private struct FrameTailInput {
  var generation: RenderGeneration
  var resolved: ResolvedNode
  var proposal: ProposedSize
  var rootIdentity: Identity
  var retained: FrameTailRetainedInput
  var layoutPassContext: LayoutPassContext
}

private struct FrameTailDiagnostics {
  var measureDuration: Duration
  var placeDuration: Duration
  var semanticsDuration: Duration
  var drawDuration: Duration
  var rasterDuration: Duration
  var layoutWork: LayoutWorkMetrics
  var workerTimings: FrameWorkerTimings?
  var measurementCache: MeasurementCacheMetrics?
}

private struct FrameTailLayoutOutput {
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

private struct FrameTailOutput {
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

private struct FrameHeadDraft {
  var clock: ContinuousClock?
  var renderGeneration: RenderGeneration
  var resolveContext: ResolveContext
  var frameContext: FrameContext
  var resolved: ResolvedNode
  var frameTailInput: FrameTailInput
  var animationTimestamp: MonotonicInstant
  var resolveDuration: Duration
  var animationCheckpoint: AnimationController.Checkpoint
}

private struct AsyncFrameTailDraftOutput {
  var layout: FrameTailLayoutOutput
  var tail: FrameTailOutput
  var renderSuspensionDuration: Duration
}

private struct FrameTailWorkerResult<Value> {
  var value: Value
  var enqueueToStart: Duration
  var compute: Duration
  var completedAt: ContinuousClock.Instant?
}

private final class RenderGenerationSequencer: Sendable {
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
      unsafe pthread_setname_np("swift-terminal-ui.frame-tail-layout")

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
    private let fallbackQueue = DispatchQueue(label: "swift-terminal-ui.frame-tail-layout-fallback")

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
    private let queue = DispatchQueue(label: "swift-terminal-ui.frame-tail-layout")

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

private final class FrameTailRenderer: Sendable {
  private let layoutEngine: LayoutEngine
  private let semanticExtractor: SemanticExtractor
  private let drawExtractor: DrawExtractor
  private let rasterizer: Rasterizer
  private let retainedState = FrameTailRetainedState()
  private let renderHooks = Mutex<FrameTailRenderHooks?>(nil)
  private let suspensionHooks = Mutex<FrameRenderSuspensionHooks?>(nil)
  private let layoutWorker = FrameTailLayoutWorkerBox()

  #if canImport(Dispatch)
    private let queue = DispatchQueue(label: "swift-terminal-ui.frame-tail-renderer")
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
    clock: ContinuousClock?
  ) async -> FrameTailLayoutOutput {
    guard canOffloadLayout(input) else {
      return renderLayoutInline(
        input,
        clock: clock
      )
    }

    let result = await timedLayoutAsync(clock: clock) {
      self.renderLayoutInline(
        input,
        clock: clock
      )
    }
    var output = result.value
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
  }

  func needsIndexedChildSourceWorkerSnapshot(
    _ input: FrameTailInput
  ) -> Bool {
    !containsMainActorOnlyCustomLayout(input.resolved)
      && containsMainActorOnlyIndexedChildSource(input.resolved)
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
    _ operation: @escaping @Sendable () -> Value
  ) async -> FrameTailWorkerResult<Value> {
    guard let clock else {
      return .init(
        value: await layoutWorker.async(operation),
        enqueueToStart: .zero,
        compute: .zero,
        completedAt: nil
      )
    }

    let enqueuedAt = clock.now
    return await layoutWorker.async {
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
  ) -> Size {
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
    for bounds: Rect,
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

/// Renders authored terminal views through the full frame pipeline.
///
/// `DefaultRenderer` is the public one-shot entry point for turning a `View`
/// into `FrameArtifacts` for previews, snapshot tests, diagnostics, or custom
/// presentation.
public struct DefaultRenderer {
  public let resolver: Resolver
  public let layoutEngine: LayoutEngine
  public let semanticExtractor: SemanticExtractor
  public let drawExtractor: DrawExtractor
  public let rasterizer: Rasterizer
  public let commitPlanner: CommitPlanner
  private let imageRepository: ImageAssetRepository
  private let viewGraph: ViewGraph
  private let frameState: FrameResolveState
  private let presentationHostState: PresentationHostState
  private let animationController: AnimationController
  private let renderGenerationSequencer: RenderGenerationSequencer

  private let frameTailRenderer: FrameTailRenderer

  /// Creates a renderer with the supplied pipeline components.
  @MainActor
  public init(
    resolver: Resolver = .init(),
    layoutEngine: LayoutEngine = .init(cache: MeasurementCache()),
    semanticExtractor: SemanticExtractor = .init(),
    drawExtractor: DrawExtractor = .init(),
    rasterizer: Rasterizer = .init(),
    commitPlanner: CommitPlanner = .init()
  ) {
    self.resolver = resolver
    self.layoutEngine = layoutEngine
    self.semanticExtractor = semanticExtractor
    self.drawExtractor = drawExtractor
    self.rasterizer = rasterizer
    self.commitPlanner = commitPlanner
    imageRepository = sharedImageAssetRepository
    viewGraph = .init()
    frameState = .init()
    presentationHostState = .init()
    animationController = .init()
    renderGenerationSequencer = .init()
    frameTailRenderer = .init(
      layoutEngine: layoutEngine,
      semanticExtractor: semanticExtractor,
      drawExtractor: drawExtractor,
      rasterizer: rasterizer
    )
  }

  /// Package-only accessor so the run loop can register animations
  /// against the renderer's controller before a `withAnimation` body
  /// executes.
  @MainActor
  package var internalAnimationController: AnimationController {
    animationController
  }

  /// Package-only accessor so the run loop can route framework-reserved
  /// single-key events (currently Escape) to the active presentation
  /// coordinator stack. Returns the dismiss closure of the topmost
  /// Escape-dismissible presentation, or nil when none is active.
  @MainActor
  package func topmostEscapeDismissAction() -> (@MainActor @Sendable () -> Void)? {
    presentationHostState.topmostEscapeDismissAction()
  }

  /// Package-only accessor exposing the renderer's internal
  /// `ViewGraph.registrationAliasDiagnostics`.  Added for Item 7 of
  /// `docs/proposals/ARCHITECTURE_NOTES.md` to let tests measure the alias layer's
  /// actual workload against the architecture doc's hypothesis.
  @MainActor
  package var debugRegistrationAliasDiagnostics: RegistrationAliasDiagnostics {
    viewGraph.registrationAliasDiagnostics
  }

  /// Renders `root` into complete frame artifacts.
  @MainActor
  public func render<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified,
    collectsDiagnostics: Bool = true
  ) -> FrameArtifacts {
    renderView(
      root,
      context: context,
      proposal: proposal,
      collectsDiagnostics: collectsDiagnostics
    )
  }

  /// Renders `root` into complete frame artifacts, suspending while the
  /// frame-tail worker computes the Sendable semantics, draw, and raster phases.
  @MainActor
  public func renderAsync<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified,
    collectsDiagnostics: Bool = true
  ) async -> FrameArtifacts {
    await renderViewAsync(
      root,
      context: context,
      proposal: proposal,
      collectsDiagnostics: collectsDiagnostics
    )
  }

  @MainActor
  private func renderView<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    collectsDiagnostics: Bool = true
  ) -> FrameArtifacts {
    let clock: ContinuousClock? = collectsDiagnostics ? ContinuousClock() : nil
    let renderGeneration = renderGenerationSequencer.next()

    var resolveContext = context
    let runtimeRegistrations = resolveContext.runtimeRegistrations
    resolveContext.imageAssetResolver = imageRepository.resolver()
    resolveContext.frameState = frameState
    frameState.update(from: resolveContext, proposal: proposal)
    viewGraph.beginFrame()
    let canUseSelectiveEvaluation =
      frameState.selectiveEvaluationEnabled
      && !frameState.environmentRequiresRootEvaluation
      && !context.invalidatedIdentities.contains(resolveContext.identity)
    if canUseSelectiveEvaluation {
      viewGraph.invalidateAndQueueDirty(context.invalidatedIdentities)
    } else {
      viewGraph.invalidate(context.invalidatedIdentities)
    }
    resolveContext.viewGraph = viewGraph
    resolveContext.observationBridge?.attachViewGraph(viewGraph)
    resolveContext.observationBridge?.beginTrackingPass()
    let wrappedRoot = PresentationHostingRoot(
      content: root,
      hostState: presentationHostState
    )
    viewGraph.setRootEvaluator(rootIdentity: resolveContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: resolveContext)
    }
    viewGraph.setEvaluator(for: resolveContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: resolveContext)
    }
    let (_, resolveDuration): (Void, Duration)
    animationController.beginTransitionCollection()
    if canUseSelectiveEvaluation, !viewGraph.hasDirtyWork {
      // Nothing is dirty — skip evaluation entirely and reuse the
      // existing tree snapshot.  The root evaluator and registrations
      // are untouched.
      resolveDuration = .zero
    } else {
      let dirtyEvaluationPlan = viewGraph.selectiveDirtyEvaluationPlan()
      if let dirtyEvaluationPlan {
        runtimeRegistrations.removeSubtrees(
          rootedAt: dirtyEvaluationPlan.frontierIdentities
        )
      } else {
        runtimeRegistrations.resetAll()
      }

      (_, resolveDuration) = measurePhase(clock: clock) {
        viewGraph.evaluateDirtyNodes(
          using: dirtyEvaluationPlan
        )
      }
    }
    animationController.finishTransitionCollection()
    var resolved = viewGraph.snapshot()
    resolved = composePresentationHostTree(
      baseNode: resolved,
      hostState: presentationHostState,
      in: resolveContext
    )
    resolved = wrapInContainerSafeArea(
      resolved,
      context: resolveContext
    )

    // Animation: capture from/to for changed animatable properties, then
    // apply interpolated values to the resolved tree before measure.
    // This is the only pipeline insertion for animation — the rest of
    // measure/place/draw/raster runs unchanged on the mutated tree.
    let animationTimestamp = MonotonicInstant.now()
    animationController.processResolvedTree(
      resolved,
      transaction: context.transaction,
      timestamp: animationTimestamp
    )
    _ = animationController.applyInterpolations(
      to: &resolved,
      at: animationTimestamp
    )

    let frameTailRetainedInput = frameTailRenderer.retainedInput(
      invalidatedIdentities: context.invalidatedIdentities
    )
    let layoutPassContext = LayoutPassContext(
      retainedLayout: frameTailRetainedInput.retainedLayout,
      invalidatedIdentities: context.invalidatedIdentities
    )
    let frameContext = FrameContext(
      environment: context.environment,
      transaction: context.transaction,
      invalidatedIdentities: context.invalidatedIdentities
    )
    let frameTailInput = FrameTailInput(
      generation: renderGeneration,
      resolved: resolved,
      proposal: proposal,
      rootIdentity: resolveContext.identity,
      retained: frameTailRetainedInput,
      layoutPassContext: layoutPassContext
    )
    let tailLayout = frameTailRenderer.renderLayout(
      frameTailInput,
      clock: clock
    )
    let placed = tailLayout.baselinePlaced
    // Capture the BASELINE placed tree (pre-overlay) for two things:
    // 1. The animation controller's removal-snapshot lookup on the
    //    next frame (capturePlacedTree).
    // 2. The retained-layout store below, so future tick frames
    //    reuse the canonical layout and not an animation-decorated
    //    tree.
    //
    // If we stored the post-overlay placed tree, subsequent ticks
    // would hit retainedPlacement and return the cached tree
    // including the stale transient overlay — then overlay snapshot
    // application would inject another overlay on top, growing the tree
    // each tick and leaving ghosted artefacts visible after the animation
    // completes.
    animationController.capturePlacedTree(tailLayout.baselinePlaced)
    // Snapshot any pending placed-level animation overlays. The snapshot
    // advances controller-owned animation state on the main actor, then the
    // frame-tail worker applies the value data before semantics/draw/raster.
    let animationOverlaySnapshot = animationController.placedAnimationOverlaySnapshot(
      for: placed,
      at: animationTimestamp
    )
    let tail = frameTailRenderer.renderRaster(
      frameTailInput,
      layout: tailLayout,
      placed: placed,
      animationOverlaySnapshot: animationOverlaySnapshot,
      clock: clock
    )
    var workerTimings = tail.diagnostics.workerTimings
    if var timings = workerTimings,
      let clock,
      let workerCompletedAt = tail.workerCompletedAt
    {
      timings.completionToMainCommit = workerCompletedAt.duration(to: clock.now)
      workerTimings = timings
    }
    let (commit, commitDuration) = measurePhase(clock: clock) {
      let lifecycleEvents = viewGraph.finalizeFrame(
        rootIdentity: resolveContext.identity,
        resolved: resolved,
        placed: tail.placed
      )
      return commitPlanner.plan(
        resolved: resolved,
        placed: tail.placed,
        semantics: tail.semantics,
        transaction: frameContext.transaction,
        lifecycleEvents: lifecycleEvents
      )
    }
    applyWorkerCustomLayoutCacheUpdates(tailLayout.workerCustomLayoutCacheUpdates)
    frameTailRenderer.pruneMeasurementCache(
      keeping: viewGraph.liveIdentitySnapshot()
    )
    let diagnostics: FrameDiagnostics
    if collectsDiagnostics {
      let phaseTimings = FramePhaseTimings(
        resolve: resolveDuration,
        measure: tail.diagnostics.measureDuration,
        place: tail.diagnostics.placeDuration,
        semantics: tail.diagnostics.semanticsDuration,
        draw: tail.diagnostics.drawDuration,
        raster: tail.diagnostics.rasterDuration,
        commit: commitDuration
      )
      let mainActorTimings = FrameMainActorTimings(
        blocked: phaseTimings.total,
        suspended: .zero
      )
      diagnostics = FrameDiagnostics.summarize(
        resolved: resolved,
        measured: tail.measured,
        placed: tail.placed,
        semantics: tail.semantics,
        draw: tail.draw,
        invalidatedIdentities: frameContext.invalidatedIdentities,
        resolveWork: resolveContext.resolveWorkTracker?.snapshot,
        layoutWork: tail.diagnostics.layoutWork,
        presentationDamage: tail.presentationDamage,
        presentationSurfaceWidth: tail.raster.size.width,
        phaseTimings: phaseTimings,
        renderGenerations: .init(
          render: renderGeneration,
          layoutInput: frameTailInput.generation,
          layoutOutput: tailLayout.generation,
          rasterInput: frameTailInput.generation,
          rasterOutput: tail.generation
        ),
        workerTimings: workerTimings,
        mainActorTimings: mainActorTimings,
        measurementCache: tail.diagnostics.measurementCache
      )
    } else {
      diagnostics = .init()
    }
    let artifacts = FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: tail.measured,
      placedTree: tail.placed,
      semanticSnapshot: tail.semantics,
      drawTree: tail.draw,
      rasterSurface: tail.raster,
      presentationDamage: tail.presentationDamage,
      drawnIdentities: tail.drawnIdentities,
      commitPlan: commit,
      diagnostics: diagnostics
    )

    frameTailRenderer.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: tail.baselinePlaced
    )
    return artifacts
  }

  @MainActor
  private func renderViewAsync<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    collectsDiagnostics: Bool = true
  ) async -> FrameArtifacts {
    let draft = prepareFrameHead(
      root,
      context: context,
      proposal: proposal,
      collectsDiagnostics: collectsDiagnostics
    )
    let tailOutput = await renderFrameTailAsync(draft)
    return finishFrame(
      draft: draft,
      tailOutput: tailOutput,
      collectsDiagnostics: collectsDiagnostics
    )
  }

  @MainActor
  private func prepareFrameHead<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    collectsDiagnostics: Bool
  ) -> FrameHeadDraft {
    let clock: ContinuousClock? = collectsDiagnostics ? ContinuousClock() : nil
    let renderGeneration = renderGenerationSequencer.next()

    var resolveContext = context
    let runtimeRegistrations = resolveContext.runtimeRegistrations
    resolveContext.imageAssetResolver = imageRepository.resolver()
    resolveContext.frameState = frameState
    frameState.update(from: resolveContext, proposal: proposal)
    viewGraph.beginFrame()
    let canUseSelectiveEvaluation =
      frameState.selectiveEvaluationEnabled
      && !frameState.environmentRequiresRootEvaluation
      && !context.invalidatedIdentities.contains(resolveContext.identity)
    if canUseSelectiveEvaluation {
      viewGraph.invalidateAndQueueDirty(context.invalidatedIdentities)
    } else {
      viewGraph.invalidate(context.invalidatedIdentities)
    }
    resolveContext.viewGraph = viewGraph
    resolveContext.observationBridge?.attachViewGraph(viewGraph)
    resolveContext.observationBridge?.beginTrackingPass()
    let wrappedRoot = PresentationHostingRoot(
      content: root,
      hostState: presentationHostState
    )
    viewGraph.setRootEvaluator(rootIdentity: resolveContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: resolveContext)
    }
    viewGraph.setEvaluator(for: resolveContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: resolveContext)
    }
    let (_, resolveDuration): (Void, Duration)
    let animationCheckpoint = animationController.beginFrameHeadTransaction()
    animationController.beginTransitionCollection()
    if canUseSelectiveEvaluation, !viewGraph.hasDirtyWork {
      resolveDuration = .zero
    } else {
      let dirtyEvaluationPlan = viewGraph.selectiveDirtyEvaluationPlan()
      if let dirtyEvaluationPlan {
        runtimeRegistrations.removeSubtrees(
          rootedAt: dirtyEvaluationPlan.frontierIdentities
        )
      } else {
        runtimeRegistrations.resetAll()
      }

      (_, resolveDuration) = measurePhase(clock: clock) {
        viewGraph.evaluateDirtyNodes(
          using: dirtyEvaluationPlan
        )
      }
    }
    animationController.finishTransitionCollection()
    var resolved = viewGraph.snapshot()
    resolved = composePresentationHostTree(
      baseNode: resolved,
      hostState: presentationHostState,
      in: resolveContext
    )
    resolved = wrapInContainerSafeArea(
      resolved,
      context: resolveContext
    )

    let animationTimestamp = MonotonicInstant.now()
    animationController.processResolvedTree(
      resolved,
      transaction: context.transaction,
      timestamp: animationTimestamp
    )
    _ = animationController.applyInterpolations(
      to: &resolved,
      at: animationTimestamp
    )

    let frameTailRetainedInput = frameTailRenderer.retainedInput(
      invalidatedIdentities: context.invalidatedIdentities
    )
    let layoutPassContext = LayoutPassContext(
      retainedLayout: frameTailRetainedInput.retainedLayout,
      invalidatedIdentities: context.invalidatedIdentities
    )
    let frameContext = FrameContext(
      environment: context.environment,
      transaction: context.transaction,
      invalidatedIdentities: context.invalidatedIdentities
    )
    var frameTailInput = FrameTailInput(
      generation: renderGeneration,
      resolved: resolved,
      proposal: proposal,
      rootIdentity: resolveContext.identity,
      retained: frameTailRetainedInput,
      layoutPassContext: layoutPassContext
    )
    if frameTailRenderer.needsIndexedChildSourceWorkerSnapshot(frameTailInput) {
      resolved = indexedChildSourceWorkerSnapshot(of: resolved)
      frameTailInput = FrameTailInput(
        generation: renderGeneration,
        resolved: resolved,
        proposal: proposal,
        rootIdentity: resolveContext.identity,
        retained: frameTailRetainedInput,
        layoutPassContext: layoutPassContext
      )
    }

    return FrameHeadDraft(
      clock: clock,
      renderGeneration: renderGeneration,
      resolveContext: resolveContext,
      frameContext: frameContext,
      resolved: resolved,
      frameTailInput: frameTailInput,
      animationTimestamp: animationTimestamp,
      resolveDuration: resolveDuration,
      animationCheckpoint: animationCheckpoint
    )
  }

  @MainActor
  private func renderFrameTailAsync(
    _ draft: FrameHeadDraft
  ) async -> AsyncFrameTailDraftOutput {
    let suspensionHooks = frameTailRenderer.renderSuspensionHooksSnapshot()
    let layoutSuspends = frameTailRenderer.canOffloadLayout(draft.frameTailInput)
    let layoutSuspensionStart = layoutSuspends ? draft.clock?.now : nil
    if layoutSuspends {
      suspensionHooks?.onBegin?()
    }
    let layout = await frameTailRenderer.renderLayoutAsync(
      draft.frameTailInput,
      clock: draft.clock
    )
    if layoutSuspends {
      suspensionHooks?.onEnd?()
    }
    let layoutSuspensionDuration =
      if let layoutSuspensionStart, let clock = draft.clock {
        layoutSuspensionStart.duration(to: clock.now)
      } else {
        Duration.zero
      }
    let placed = layout.baselinePlaced
    animationController.capturePlacedTree(layout.baselinePlaced)
    let animationOverlaySnapshot = animationController.placedAnimationOverlaySnapshot(
      for: placed,
      at: draft.animationTimestamp
    )
    let rasterSuspensionStart = draft.clock?.now
    suspensionHooks?.onBegin?()
    let tail = await frameTailRenderer.renderRasterAsync(
      draft.frameTailInput,
      layout: layout,
      placed: placed,
      animationOverlaySnapshot: animationOverlaySnapshot,
      clock: draft.clock
    )
    suspensionHooks?.onEnd?()
    let rasterSuspensionDuration =
      if let rasterSuspensionStart, let clock = draft.clock {
        rasterSuspensionStart.duration(to: clock.now)
      } else {
        Duration.zero
      }

    return AsyncFrameTailDraftOutput(
      layout: layout,
      tail: tail,
      renderSuspensionDuration: layoutSuspensionDuration + rasterSuspensionDuration
    )
  }

  @MainActor
  private func finishFrame(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    collectsDiagnostics: Bool
  ) -> FrameArtifacts {
    let layout = tailOutput.layout
    let tail = tailOutput.tail
    var workerTimings = tail.diagnostics.workerTimings
    if var timings = workerTimings,
      let clock = draft.clock,
      let workerCompletedAt = tail.workerCompletedAt
    {
      timings.completionToMainCommit = workerCompletedAt.duration(to: clock.now)
      workerTimings = timings
    }
    let (commit, commitDuration) = measurePhase(clock: draft.clock) {
      let lifecycleEvents = viewGraph.finalizeFrame(
        rootIdentity: draft.resolveContext.identity,
        resolved: draft.resolved,
        placed: tail.placed
      )
      return commitPlanner.plan(
        resolved: draft.resolved,
        placed: tail.placed,
        semantics: tail.semantics,
        transaction: draft.frameContext.transaction,
        lifecycleEvents: lifecycleEvents
      )
    }
    animationController.commitFrameHeadTransaction(draft.animationCheckpoint)
    applyWorkerCustomLayoutCacheUpdates(layout.workerCustomLayoutCacheUpdates)
    frameTailRenderer.pruneMeasurementCache(
      keeping: viewGraph.liveIdentitySnapshot()
    )
    let diagnostics: FrameDiagnostics
    if collectsDiagnostics {
      let phaseTimings = FramePhaseTimings(
        resolve: draft.resolveDuration,
        measure: tail.diagnostics.measureDuration,
        place: tail.diagnostics.placeDuration,
        semantics: tail.diagnostics.semanticsDuration,
        draw: tail.diagnostics.drawDuration,
        raster: tail.diagnostics.rasterDuration,
        commit: commitDuration
      )
      let mainActorTimings = FrameMainActorTimings(
        blocked: draft.resolveDuration
          + (layout.ranOffMain
            ? .zero
            : tail.diagnostics.measureDuration + tail.diagnostics.placeDuration)
          + commitDuration,
        suspended: tailOutput.renderSuspensionDuration
      )
      diagnostics = FrameDiagnostics.summarize(
        resolved: draft.resolved,
        measured: tail.measured,
        placed: tail.placed,
        semantics: tail.semantics,
        draw: tail.draw,
        invalidatedIdentities: draft.frameContext.invalidatedIdentities,
        resolveWork: draft.resolveContext.resolveWorkTracker?.snapshot,
        layoutWork: tail.diagnostics.layoutWork,
        presentationDamage: tail.presentationDamage,
        presentationSurfaceWidth: tail.raster.size.width,
        phaseTimings: phaseTimings,
        renderGenerations: .init(
          render: draft.renderGeneration,
          layoutInput: draft.frameTailInput.generation,
          layoutOutput: layout.generation,
          rasterInput: draft.frameTailInput.generation,
          rasterOutput: tail.generation
        ),
        workerTimings: workerTimings,
        mainActorTimings: mainActorTimings,
        measurementCache: tail.diagnostics.measurementCache
      )
    } else {
      diagnostics = .init()
    }
    let artifacts = FrameArtifacts(
      resolvedTree: draft.resolved,
      measuredTree: tail.measured,
      placedTree: tail.placed,
      semanticSnapshot: tail.semantics,
      drawTree: tail.draw,
      rasterSurface: tail.raster,
      presentationDamage: tail.presentationDamage,
      drawnIdentities: tail.drawnIdentities,
      commitPlan: commit,
      diagnostics: diagnostics
    )

    frameTailRenderer.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: tail.baselinePlaced
    )
    return artifacts
  }

  @MainActor
  private func applyWorkerCustomLayoutCacheUpdates(
    _ updates: [WorkerCustomLayoutCacheUpdate]
  ) {
    for update in updates {
      update.apply()
    }
  }

  @MainActor
  private func indexedChildSourceWorkerSnapshot(
    of node: ResolvedNode
  ) -> ResolvedNode {
    var node = node
    node.children = node.children.map(indexedChildSourceWorkerSnapshot(of:))

    guard let source = node.indexedChildSource,
      !source.canRunOnWorker
    else {
      return node
    }

    let children = (0..<source.count).map { index in
      indexedChildSourceWorkerSnapshot(of: source.child(at: index))
    }
    node.indexedChildSource = IndexedChildSourceSnapshot(
      identityRoot: source.identityRoot,
      measurementSignature: source.measurementSignature,
      children: children
    )
    return node
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

  private func wrapInContainerSafeArea(
    _ resolved: ResolvedNode,
    context: ResolveContext
  ) -> ResolvedNode {
    let safeAreaInsets = context.environmentValues.safeAreaInsets
    guard !safeAreaInsets.isZero else {
      return resolved
    }

    return ResolvedNode(
      identity: resolved.identity.child(.named("ContainerSafeArea")),
      kind: .view("ContainerSafeArea"),
      children: [resolved],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      layoutBehavior: .padding(safeAreaInsets)
    )
  }

  /// Enables selective dirty-frontier evaluation for subsequent frames.
  /// Call after the first full render has established the tree and
  /// evaluator closures.
  @MainActor
  package func enableSelectiveEvaluation() {
    frameState.selectiveEvaluationEnabled = true
  }

  /// Forces the next render to use root evaluation regardless of whether
  /// selective evaluation would otherwise apply.
  @MainActor
  package func forceRootEvaluation() {
    frameState.forceRootEvaluation = true
  }

  @MainActor
  package func liveIdentitySnapshot() -> Set<Identity> {
    viewGraph.liveIdentitySnapshot()
  }

  @MainActor
  package func setFrameTailRenderHooks(
    _ hooks: FrameTailRenderHooks?
  ) {
    frameTailRenderer.setRenderHooks(hooks)
  }

  @MainActor
  package func setFrameRenderSuspensionHooks(
    _ hooks: FrameRenderSuspensionHooks?
  ) {
    frameTailRenderer.setRenderSuspensionHooks(hooks)
  }
}
