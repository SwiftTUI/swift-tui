import Observation
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AdversarialSetAFrameBoundaryTests {
  @Test func setA551DuplicateDeadlineRearmCannotMoveItBehindTheDrainCut() throws {
    // Hypothesis: rearming an already pending instant replaces its arm ordinal,
    // postponing work that belonged to the current finite drain pass.
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    let due = MonotonicInstant(offset: .seconds(100))
    scheduler.requestDeadline(due)
    let cut = scheduler.deadlineArmCut
    scheduler.requestDeadline(due)
    let frame = try #require(scheduler.consumeReadyFrame(at: due, armedBefore: cut))
    #expect(frame.triggeredDeadline == due)
    #expect(frame.causes == [.deadline])
    #expect(scheduler.consumeReadyFrame(at: due) == nil)
  }

  @Test func setA552EarlierPostCutDeadlineCannotHideAnAdmittedLaterInstant() throws {
    // Hypothesis: a newly inserted earlier deadline makes the scheduler stop
    // at the first withheld entry and strand an older, admitted due deadline.
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    let early = MonotonicInstant(offset: .seconds(100))
    let late = early.advanced(by: .seconds(1))
    scheduler.requestDeadline(late)
    let cut = scheduler.deadlineArmCut
    scheduler.requestDeadline(early)
    let first = try #require(scheduler.consumeReadyFrame(at: late, armedBefore: cut))
    #expect(first.triggeredDeadline == late && first.nextDeadline == early)
    let second = try #require(scheduler.consumeReadyFrame(at: late))
    #expect(second.triggeredDeadline == early)
    #expect(scheduler.nextWakeInstant(after: late) == nil)
  }

  @Test func setA553EarlyInputConsumptionKeepsItsStillFutureDeadline() throws {
    // Hypothesis: consuming a non-deadline wake clears a separately armed
    // future deadline along with the coalesced intent counters.
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    let now = MonotonicInstant(offset: .seconds(100))
    let due = now.advanced(by: .seconds(5))
    scheduler.requestDeadline(due)
    scheduler.requestInput()
    let input = try #require(scheduler.consumeReadyFrame(at: now))
    #expect(input.causes == [.input] && input.triggeredDeadline == nil)
    #expect(input.nextDeadline == due)
    #expect(!scheduler.hasPendingFrame(at: now))
    #expect(scheduler.nextWakeInstant(after: now) == due)
    #expect(scheduler.consumeReadyFrame(at: due)?.triggeredDeadline == due)
  }

  @Test func setA554CancelledRenderReplayDoesNotReplayInputOrSignalEffects() throws {
    // Hypothesis: replaying an abandoned frame restores its already-dispatched
    // input/signal causes instead of only the unresolved invalidation intent.
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    let owner = testIdentity("SetA554", "owner")
    scheduler.requestInvalidation(of: [owner])
    scheduler.requestInput()
    scheduler.requestSignal(named: "old-signal")
    let abandoned = try #require(scheduler.consumeReadyFrame())
    scheduler.requestSignal(named: "new-signal")
    scheduler.replayCancelledFrameIntent(abandoned)
    let replay = try #require(scheduler.consumeReadyFrame())
    #expect(replay.causes == [.invalidation, .signal])
    #expect(replay.invalidatedIdentities == [owner])
    #expect(replay.signalNames == ["new-signal"])
    #expect(scheduler.consumeReadyFrame() == nil)
  }

  @Test func setA555WakeCallbacksCanConsumeAndRequestWithoutLosingReentrantWork() {
    // Hypothesis: wake delivery runs under the scheduler lock or clears new
    // work after a reentrant callback has already scheduled a second frame.
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    let frames = Mutex<[ScheduledFrame]>([])
    let first = testIdentity("SetA555", "first")
    let second = testIdentity("SetA555", "second")
    scheduler.setWakeHandler {
      guard let frame = scheduler.consumeReadyFrame() else { return }
      frames.withLock { $0.append(frame) }
      if frame.invalidatedIdentities == [first] {
        scheduler.requestInvalidation(of: [second])
      }
    }
    defer { scheduler.setWakeHandler(nil) }
    scheduler.requestInvalidation(of: [first])
    #expect(frames.withLock { $0.map(\.invalidatedIdentities) } == [[first], [second]])
    #expect(scheduler.consumeReadyFrame() == nil)
  }

  @Test func setA556ReleasingAWaiterDoesNotConsumeOrInventAFrame() async throws {
    // Hypothesis: the queue-exit release signal is implemented as a synthetic
    // scheduler request, or consumes the genuine future deadline while waking.
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    let now = MonotonicInstant.now()
    let due = now.advanced(by: .seconds(3600))
    scheduler.requestDeadline(due)
    let release = FrameBoundaryWaitRelease()
    let finished = AsyncEvent()
    let waiter = Task {
      await scheduler.waitForPendingFrame(at: now, releasedBy: release)
      finished.fire()
    }
    do {
      await release.registered.wait()
      try Task.checkCancellation()
      let released = release.token.markStarted()
      #expect(released)
      await finished.wait()
      try Task.checkCancellation()
      await waiter.value
    } catch {
      waiter.cancel()
      _ = release.token.markStarted()
      await waiter.value
      throw error
    }
    #expect(!scheduler.hasPendingFrame(at: now))
    #expect(scheduler.consumeReadyFrame(at: now) == nil)
    #expect(scheduler.nextWakeInstant(after: now) == due)
    #expect(scheduler.consumeReadyFrame(at: due)?.triggeredDeadline == due)
  }

  @Test func setA557ConcurrentMixedRequestsRetainEveryIdentityAndCause() async throws {
    // Hypothesis: independently locked wake channels overwrite one another's
    // coalesced payloads when signals, external wakes, and invalidations race.
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<40 {
        group.addTask { scheduler.requestInvalidation(of: [testIdentity("SetA557", "\(index)")]) }
        group.addTask { scheduler.requestSignal(named: "signal-\(index % 3)") }
        group.addTask { scheduler.requestExternalWake(reason: "external-\(index % 2)") }
      }
      await group.waitForAll()
    }
    let frame = try #require(scheduler.consumeReadyFrame())
    #expect(frame.causes == [.invalidation, .signal, .external])
    #expect(frame.invalidatedIdentities.count == 40)
    #expect(frame.signalNames == ["signal-0", "signal-1", "signal-2"])
    #expect(frame.externalReasons == ["external-0", "external-1"])
    #expect(frame.intentRequestCount == 120)
    #expect(scheduler.consumeReadyFrame() == nil)
  }

  @Test func setA558AbortedTaskRegistrationCannotStartBeforeARealCommit() async throws {
    // Hypothesis: preparing an abortable head publishes a newly authored task
    // descriptor to the live lifecycle owner before its frame commits.
    let probe = FrameBoundaryProbe()
    let h = try FrameBoundaryHarness(558) { phase in
      FrameBoundaryConditionalTask(visible: phase == 1, probe: probe)
    }
    defer {
      probe.release.fire()
      h.shutdown()
    }
    let draft = h.prepare(phase: 1)
    h.runLoop.renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    #expect(h.runLoop.lifecycleCoordinator.activeTaskCount == 0)
    #expect(probe.events.isEmpty)
    h.setState(1)
    try h.render()
    try #require(h.text.contains("Task owner"))
    await probe.started.wait()
    try Task.checkCancellation()
    #expect(probe.events == ["task-start"])
    #expect(h.runLoop.lifecycleCoordinator.activeTaskCount == 1)
  }

  @Test func setA559AbortedModalOpeningCannotCaptureCommittedBackgroundActions() throws {
    // Hypothesis: a draft-only modal portal changes the live action scope or
    // dismissal stack even though its presentation transaction is discarded.
    let probe = FrameBoundaryProbe()
    let h = try FrameBoundaryHarness(559) { phase in
      Button("Background") { probe.events.append("background") }
        .sheet(isPresented: .constant(phase == 1)) {
          Button("Draft modal") { probe.events.append("modal") }
        }.sheetStyle(.dropdown)
    }
    defer { h.shutdown() }
    let initialActions = h.runLoop.localActionRegistry.snapshot().count
    let draft = h.prepare(phase: 1)
    h.runLoop.renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    #expect(h.runLoop.localActionRegistry.snapshot().count == initialActions)
    #expect(h.runLoop.handleKeyPress(.init(.return)) == nil)
    try h.render()
    #expect(probe.events == ["background"])
    #expect(!h.text.contains("Draft modal"))
  }

  @Test func setA560AbortedEnvironmentCaptureCannotContaminateARetainedReader() throws {
    // Hypothesis: restoring a draft keeps its evaluator's temporary environment
    // input box, so a later local-state invalidation reads the abandoned value.
    let probe = FrameBoundaryProbe()
    let h = try FrameBoundaryHarness(560) { phase in
      FrameBoundaryEnvironmentCounter(probe: probe)
        .environment(\.frameBoundaryTag, phase == 1 ? "draft" : "live")
    }
    defer { h.shutdown() }
    try #require(h.text.contains("live:0"))
    let committedAction = try #require(probe.action)
    let draft = h.prepare(phase: 1)
    h.runLoop.renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    committedAction()
    try h.render()
    #expect(h.text.contains("live:1"))
    #expect(!h.text.contains("draft"))
  }

  @Test func setA561StaleHeadDiscardPreservesTheSiblingCommitsNewActionOwner() throws {
    // Hypothesis: discarding a head prepared before a sibling commit restores
    // its old whole-registry snapshot and erases a newly mounted action.
    let probe = FrameBoundaryProbe()
    let h = try FrameBoundaryHarness(561) { phase in
      if phase == 0 {
        Text("No action")
      } else {
        Button("New action") { probe.events.append("new") }
      }
    }
    defer { h.shutdown() }
    let stale = h.prepare()
    h.setState(1)
    try h.render()
    try #require(h.runLoop.localActionRegistry.snapshot().count > 0)
    h.runLoop.renderer.abortPreparedFrameHeadForCancellationTesting(stale)
    #expect(h.runLoop.handleKeyPress(.init(.return)) == nil)
    try h.render()
    #expect(probe.events == ["new"])
    #expect(h.text.contains("New action"))
  }

  @Test func setA562DiscardedObservationDraftKeepsTheCommittedModelsSubscription() throws {
    // Hypothesis: a prepared frame's replacement model observation disarms the
    // committed model even when the observation draft is later discarded.
    let live = FrameBoundaryObservable(value: 1)
    let abandoned = FrameBoundaryObservable(value: 90)
    let h = try FrameBoundaryHarness(562) { phase in
      FrameBoundaryModelReader(model: phase == 1 ? abandoned : live)
    }
    defer { h.shutdown() }
    let draft = h.prepare(phase: 1)
    h.runLoop.renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    live.value = 2
    try h.render()
    #expect(h.text.contains("model=2"))
    live.value = 3
    try h.render()
    #expect(h.text.contains("model=3"))
    #expect(!h.text.contains("90"))
  }

  @Test func setA563DiscardedCustomLayoutTailCannotPopulateTheCommittedCacheStore() async throws {
    // Hypothesis: worker placement writes persistent author caches immediately,
    // making a never-committed layout container survive a discarded candidate.
    let h = try FrameBoundaryHarness(563) { phase in
      if phase == 0 { Text("baseline") } else { FrameBoundaryLayout { Text("custom") } }
    }
    defer { h.shutdown() }
    let store = try #require(h.runLoop.renderer.customLayoutCacheStore)
    try #require(store.isEmpty)
    let draft = h.prepare(phase: 1)
    await h.runLoop.renderer.renderPreparedFrameTailForCancellationTesting(draft)
    #expect(store.isEmpty)
    h.runLoop.renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    #expect(store.isEmpty)
    h.setState(1)
    try h.render()
    #expect(h.text.contains("custom"))
    #expect(!store.isEmpty)
  }

  @Test func setA564DamageUsesTheLastPresentedSurfaceAcrossAWithheldRendererCommit() async throws {
    // Hypothesis: a committed but unpresented acquisition becomes the host's
    // damage baseline, omitting changes the host never received.
    let h = try FrameBoundaryHarness(564) { phase in
      VStack(alignment: .leading, spacing: 0) {
        Text(phase == 0 ? "A0" : "A1")
        Text(phase == 2 ? "B2" : "B0")
      }
    }
    defer { h.shutdown() }
    try #require(h.text.contains("A0") && h.text.contains("B0"))
    let count = h.host.frames.count
    h.setState(1)
    let draft = h.prepare()
    let committed = await h.runLoop.renderer.commitCompletedFrameCandidateForTesting(draft)
    let withheldText = committed.committedArtifacts.rasterSurface.lines.joined()
    try #require(withheldText.contains("A1") && withheldText.contains("B0"))
    #expect(h.host.frames.count == count)
    #expect(h.text.contains("A0") && h.text.contains("B0"))
    h.setState(2)
    try h.render()
    let frame = try #require(h.host.frames.last)
    #expect(h.host.frames.count > count)
    if let damage = frame.rasterDamage, !damage.requiresFullTextRepaint {
      for row in 0..<2 {
        #expect(
          damage.textRows.contains {
            $0.row == row
              && ($0.columnRanges.isEmpty || $0.columnRanges.contains { $0.contains(1) })
          })
      }
    }
    #expect(h.text.contains("A1") && h.text.contains("B2"))
  }

  @Test func setA565StateWrittenInsidePresentationSurvivesTheCompletingFrame() throws {
    // Hypothesis: commit bookkeeping clears a state invalidation requested
    // synchronously by the host's on-frame callback before the next drain.
    let h = try FrameBoundaryHarness(565) { phase in Text("phase=\(phase)") }
    defer {
      h.host.onPresent = nil
      h.shutdown()
    }
    h.host.onPresent = { _ in
      if h.runLoop.stateContainer.state == 1 { h.setState(2) }
    }
    h.setState(1)
    try h.render()
    #expect(h.runLoop.stateContainer.state == 2)
    #expect(h.text.contains("phase=2"))
    #expect(h.host.frames.contains { $0.raster.lines.joined().contains("phase=1") })
  }

  @Test func setA566SemanticOnlyChangesStillPublishFreshHostFrames() throws {
    // Hypothesis: unchanged raster cells suppress host delivery even when an
    // accessibility label changed and the host needs a new semantic snapshot.
    let h = try FrameBoundaryHarness(566) { phase in
      Text("Same pixels").accessibilityLabel("semantic-\(phase)")
    }
    defer { h.shutdown() }
    let before = try #require(h.host.frames.last)
    try #require(before.semantics.accessibilityNodes.contains { $0.label == "semantic-0" })
    h.setState(1)
    try h.render()
    let after = try #require(h.host.frames.last)
    #expect(after.sequence > before.sequence)
    #expect(after.raster == before.raster)
    #expect(after.semantics.accessibilityNodes.contains { $0.label == "semantic-1" })
  }

  @Test func setA567SameSizedHostAppearanceReplacementReachesRetainedReaders() throws {
    // Hypothesis: unchanged host geometry lets retained environment readers
    // keep the old terminal appearance after an external host refresh.
    let h = try FrameBoundaryHarness(567) { _ in FrameBoundaryAppearanceReader() }
    defer { h.shutdown() }
    h.host.appearance.foregroundColor = Color(hexRGB: 0xFF0000)
    h.runLoop.scheduler.requestExternalWake(reason: "appearance")
    try h.render()
    #expect(h.text.contains("foreground=255,0"))
    h.host.appearance.foregroundColor = Color(hexRGB: 0x00FF00)
    h.runLoop.scheduler.requestExternalWake(reason: "appearance-again")
    try h.render()
    #expect(h.text.contains("foreground=0,255"))
  }

  @Test func setA568WithdrawingReportedCellMetricsRestoresEstimatedMetrics() throws {
    // Hypothesis: the host-to-environment bridge only overwrites non-nil cell
    // metrics, retaining stale reported dimensions when the host withdraws them.
    let h = try FrameBoundaryHarness(568) { _ in FrameBoundaryMetricsReader() }
    defer { h.shutdown() }
    h.host.graphicsCapabilities.cellPixelSize = .init(width: 11, height: 23)
    h.runLoop.scheduler.requestExternalWake(reason: "reported-metrics")
    try h.render()
    try #require(h.text.contains("metrics=11x23:reported"))
    h.host.graphicsCapabilities.cellPixelSize = nil
    h.runLoop.scheduler.requestExternalWake(reason: "withdraw-metrics")
    try h.render()
    #expect(h.text.contains("metrics=8x16:estimated"))
  }

  @Test func setA569HostedFrameCallbacksMayReenterSurfaceUpdates() async throws {
    // Hypothesis: onFrame runs while the surface's frame-history mutex is
    // locked, deadlocking a host that immediately updates its geometry.
    let holder = FrameBoundarySurfaceHolder()
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 12, height: 3), appearance: .fallback,
      frameDelivery: .assumedMainActor,
      onFrame: { frame in
        holder.sequences.append(frame.sequence)
        holder.surface?.updateSurfaceSize(.init(width: 19, height: 4))
      })
    holder.surface = surface
    let raster = RasterSurface(size: .init(width: 12, height: 3), lines: ["callback"])
    _ = try surface.present(raster)
    #expect(surface.surfaceSize == .init(width: 19, height: 4))
    #expect(holder.sequences.count == 1)
    let retained = await surface.waitForFrame { $0.raster.lines.contains("callback") }
    #expect(retained.sequence == holder.sequences.first)
    #expect(retained.raster.size == raster.size)
    holder.surface = nil
  }

  @Test func setA570DisappearStateWritesReachTheSurvivingViewInAFollowUp() throws {
    // Hypothesis: pruning a departing subtree also drops state invalidations
    // its onDisappear callback emits for a surviving ancestor.
    let probe = FrameBoundaryProbe()
    let h = try FrameBoundaryHarness(570) { _ in FrameBoundaryDisappearWriter(probe: probe) }
    defer { h.shutdown() }
    try #require(h.text.contains("departures=0"))
    probe.action?()
    try h.render()
    #expect(h.text.contains("departures=1"))
    #expect(probe.events == ["departed"])
    h.invalidate()
    try h.render()
    #expect(probe.events == ["departed"])
  }

  @Test func setA571CancellationBeforeTheFirstTaskTurnPreventsUserCodeEntry() async throws {
    // Hypothesis: a cancelled queued lifecycle task still enters its authored
    // operation before checking cancellation and accesses a retired owner.
    let runner = TaskRunner()
    let probe = FrameBoundaryProbe()
    let node = ViewNodeID(rawValue: 571)
    let registration = TaskRegistration(
      descriptor: .init(id: "queued", priority: .medium),
      operation: { probe.events.append("entered") })
    let task = try #require(
      runner.start(
        viewNodeID: node, identity: testIdentity("SetA571"), registration: registration))
    runner.cancel(viewNodeID: node)
    await task.value
    #expect(probe.events.isEmpty)
    #expect(runner.activeTaskCount == 0)
  }

  @Test func setA572LateOldTaskCompletionCannotRetireItsReplacement() async throws {
    // Hypothesis: a retired task's completion cleans up its reused owner and
    // descriptor slot without checking the replacement's newer generation.
    let runner = TaskRunner()
    let node = ViewNodeID(rawValue: 572)
    let identity = testIdentity("SetA572")
    let descriptor = TaskDescriptor(id: "shared-slot", priority: .medium)
    let oldStarted = AsyncEvent()
    let oldRelease = FrameBoundaryUncancelledGate()
    let newStarted = AsyncEvent()
    let newRelease = AsyncEvent()
    defer {
      oldRelease.open()
      newRelease.fire()
      runner.cancelAll()
    }
    let oldTask = try #require(
      runner.start(
        viewNodeID: node, identity: identity,
        registration: TaskRegistration(descriptor: descriptor) {
          oldStarted.fire()
          await oldRelease.wait()
        }))
    var replacement: Task<Void, Never>?
    do {
      await oldStarted.wait()
      try Task.checkCancellation()
      let newTask = try #require(
        runner.start(
          viewNodeID: node, identity: identity,
          registration: TaskRegistration(descriptor: descriptor) {
            newStarted.fire()
            await newRelease.wait()
          }))
      replacement = newTask
      await newStarted.wait()
      try Task.checkCancellation()
      try #require(oldTask.isCancelled)
      oldRelease.open()
      await oldTask.value
      #expect(runner.activeTaskCount == 1)
      #expect(!newTask.isCancelled)
      runner.cancel(viewNodeID: node)
      await newTask.value
      #expect(newTask.isCancelled)
      #expect(runner.activeTaskCount == 0)
    } catch {
      oldRelease.open()
      newRelease.fire()
      runner.cancelAll()
      await oldTask.value
      await replacement?.value
      throw error
    }

  }

  @Test func setA573CooperativeExitPresentsNewContentWithoutStartingItsTask() throws {
    // Hypothesis: the required final presentation mounts a new task after
    // shutdown has already cancelled the session's prior task generation.
    let probe = FrameBoundaryProbe()
    let input = InjectedTerminalInputReader()
    let host = FrameBoundaryHost()
    let root = testIdentity("SetA573")
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    let state = StateContainer(initialState: 0, invalidationIdentities: [root])
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host, terminalInputReader: input,
      scheduler: scheduler, stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, state in
        if key == KeyPress(.return) {
          state.mutate { $0 = 1 }
          return .handled
        }
        return key == KeyPress(.escape) ? .exit(.programmatic) : .ignored
      },
      runtimeConfiguration: .init(motion: .reduced), exitKeyBindings: .none,
      viewBuilder: .init { input in
        FrameBoundaryConditionalTask(visible: input.state == 1, probe: probe)
      })
    state.invalidator = scheduler
    loop.installFocusTrackerInvalidator()
    loop.isSessionActive = true
    defer {
      loop.isSessionActive = false
      loop.lifecycleCoordinator.shutdown()
    }
    var rendered = 0
    scheduler.requestInvalidation(of: [root])
    try loop.renderPendingFrames(renderedFrames: &rendered)
    try #require(host.frames.last?.raster.lines.joined().contains("No task") == true)
    let before = host.frames.count
    let buffer = EventPumpBuffer()
    _ = buffer.enqueue(.input(.key(.init(.return))))
    _ = buffer.enqueue(.input(.key(.init(.escape))))
    let exit = try loop.processPendingEventsSynchronously(
      from: .init(
        stream: AsyncStream { $0.finish() }, drainEvents: { buffer.drain() },
        hasPendingEvents: { buffer.hasPendingEvents() }, cancel: {},
        scheduleDeadlineWake: { _ in }),
      renderedFrames: &rendered)
    #expect(exit == .programmatic && state.state == 1)
    #expect(host.frames.count > before)
    #expect(host.frames.last?.raster.lines.joined().contains("Task owner") == true)
    #expect(probe.events.isEmpty)
    #expect(loop.lifecycleCoordinator.activeTaskCount == 0)
    #expect(loop.lifecycleCoordinator.refusedStartsAfterShutdownCount > 0)
  }

  @Test func setA574ConditionalObservationSwitchesAndRearmsItsLiveDependency() throws {
    // Hypothesis: a conditional property read retains its old dependency or
    // fails to reinstall the newly selected property's one-shot observation.
    let model = FrameBoundaryObservable(value: 1)
    let h = try FrameBoundaryHarness(574) { _ in FrameBoundaryConditionalReader(model: model) }
    defer { h.shutdown() }
    model.readsFirst = false
    try h.render()
    try #require(h.text.contains("selected=10"))
    let before = h.host.frames.count
    model.value = 2
    try h.render()
    #expect(h.host.frames.count == before)
    model.second = 11
    try h.render()
    #expect(h.text.contains("selected=11"))
    model.second = 12
    try h.render()
    #expect(h.text.contains("selected=12"))
  }

  @Test func setA575OffMainObservationWakesAndRearmsADormantRunLoop() async throws {
    // Hypothesis: the Observation bridge assumes a main-actor writer, so an
    // off-main mutation cannot wake a sleeping input-free session or rearm it.
    let model = FrameBoundaryThreadModel()
    let input = InjectedTerminalInputReader()
    let received = [AsyncEvent(), AsyncEvent(), AsyncEvent()]
    let frames = FrameBoundaryObservedFrames()
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 30, height: 4), appearance: .fallback,
      frameDelivery: .assumedMainActor,
      onFrame: { frame in
        for value in 0..<3 where frame.raster.lines.joined().contains("thread=\(value)") {
          frames.byValue[value] = frame
          received[value].fire()
        }
      })
    let root = testIdentity("SetA575")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: surface, terminalInputReader: input,
      scheduler: FrameScheduler(mergePressurePacingEnabled: false),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      runtimeConfiguration: .init(motion: .reduced),
      viewBuilder: .init { _ in FrameBoundaryThreadReader(model: model) })
    let exited = AsyncEvent()
    let running = Task {
      defer { exited.fire() }
      return try await loop.run()
    }
    do {
      await received[0].wait()
      try Task.checkCancellation()
      await Task.detached { model.value = 1 }.value
      await received[1].wait()
      try Task.checkCancellation()
      let first = try #require(frames.byValue[1])
      await Task.detached { model.value = 2 }.value
      await received[2].wait()
      try Task.checkCancellation()
      let second = try #require(frames.byValue[2])
      #expect(second.sequence > first.sequence)
      input.finish()
      await exited.wait()
      try Task.checkCancellation()
      let result = try await running.value
      #expect(result.exitReason == .inputEnded)
    } catch {
      input.finish()
      running.cancel()
      _ = await running.result
      throw error
    }

  }
}

@MainActor
private final class FrameBoundaryHarness<Content: View> {
  let root: Identity
  let host = FrameBoundaryHost()
  let runLoop: RunLoop<Int, Content>
  private var rendered = 0

  init(_ number: Int, @ViewBuilder content: @escaping (Int) -> Content) throws {
    root = testIdentity("SetAFrameBoundary", "\(number)")
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    let focus = FocusTracker(invalidationIdentities: [root])
    runLoop = RunLoop(
      rootIdentity: root, renderer: DefaultRenderer(), presentationSurface: host,
      terminalInputReader: InjectedTerminalInputReader(), scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus, runtimeConfiguration: .init(motion: .reduced),
      viewBuilder: .init { input in content(input.state) })
    runLoop.stateContainer.invalidator = scheduler
    focus.invalidator = scheduler
    invalidate()
    try render()
    runLoop.renderer.enableSelectiveEvaluation()
  }

  var text: String { host.frames.last?.raster.lines.joined(separator: "\n") ?? "" }
  func setState(_ value: Int) { runLoop.stateContainer.mutate { $0 = value } }
  func invalidate() { runLoop.scheduler.requestInvalidation(of: [root]) }
  func render() throws { try runLoop.renderPendingFrames(renderedFrames: &rendered) }
  func shutdown() { runLoop.lifecycleCoordinator.shutdown() }

  func prepare(phase: Int? = nil) -> FrameHeadDraft {
    runLoop.renderer.prepareFrameHeadForCancellationTesting(
      runLoop.viewBuilder(
        (
          state: phase ?? runLoop.stateContainer.state,
          focusedIdentity: runLoop.focusTracker.currentFocusIdentity
        )),
      context: runLoop.resolveContext(
        for: .init(
          causes: [.invalidation], invalidatedIdentities: [root], signalNames: [],
          externalReasons: [],
          triggeredDeadline: nil, nextDeadline: nil)),
      proposal: runLoop.proposal())
  }
}

private final class FrameBoundaryWaitRelease: PendingFrameWaitReleasing {
  let token = FrameTailJobCancellationToken()
  let registered = AsyncEvent()
  var isReleased: Bool { token.isReleased }
  func onRelease(_ waker: @escaping @Sendable () -> Void) {
    token.onRelease(waker)
    registered.fire()
  }
}

private final class FrameBoundaryHost: PresentationSurface, SemanticHostFramePresentationSurface {
  var surfaceSize = CellSize(width: 48, height: 8)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  var appearance = TerminalAppearance.fallback
  var graphicsCapabilities = TerminalGraphicsCapabilities.none
  var frames: [SemanticHostFrame] = []
  var onPresent: ((SemanticHostFrame) -> Void)?
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    try present(
      .init(
        sequence: UInt64(frames.count), raster: surface, semantics: .init(), focusedIdentity: nil))
  }
  func present(_ frame: SemanticHostFrame) throws -> TerminalPresentationMetrics {
    frames.append(frame)
    onPresent?(frame)
    return .init(
      bytesWritten: 0, linesTouched: frame.raster.size.height,
      cellsChanged: frame.raster.size.width * frame.raster.size.height, strategy: .fullRepaint)
  }
}

@MainActor
private final class FrameBoundaryProbe {
  var events: [String] = []
  var action: (() -> Void)?
  let started = AsyncEvent()
  let release = AsyncEvent()
}

private struct FrameBoundaryConditionalTask: View {
  let visible: Bool
  let probe: FrameBoundaryProbe
  var body: some View {
    if visible {
      Text("Task owner").task {
        probe.events.append("task-start")
        probe.started.fire()
        await probe.release.wait()
      }
    } else {
      Text("No task")
    }
  }
}

private enum FrameBoundaryTagKey: EnvironmentKey { static let defaultValue = "default" }
extension EnvironmentValues {
  fileprivate var frameBoundaryTag: String {
    get { self[FrameBoundaryTagKey.self] }
    set { self[FrameBoundaryTagKey.self] = newValue }
  }
}

private struct FrameBoundaryEnvironmentCounter: View {
  let probe: FrameBoundaryProbe
  @Environment(\.frameBoundaryTag) private var tag
  @State private var count = 0
  var body: some View {
    let _ = probe.action = { count += 1 }
    Text("\(tag):\(count)")
  }
}

@MainActor @Observable
private final class FrameBoundaryObservable {
  var value: Int
  var second = 10
  var readsFirst = true
  init(value: Int) { self.value = value }
}

private struct FrameBoundaryModelReader: View {
  let model: FrameBoundaryObservable
  var body: some View { Text("model=\(model.value)") }
}

private struct FrameBoundaryConditionalReader: View {
  let model: FrameBoundaryObservable
  var body: some View { Text("selected=\(model.readsFirst ? model.value : model.second)") }
}

private struct FrameBoundaryLayout: Layout {
  struct Cache: Sendable { var size = CellSize.zero }
  func makeCache(subviews _: LayoutSubviews) -> Cache { .init() }
  func updateCache(_: inout Cache, subviews _: LayoutSubviews) {}
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Cache)
    -> LayoutSize
  {
    cache.size = subviews.first?.sizeThatFits(proposal) ?? .zero
    return cache.size
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews,
    cache _: inout Cache
  ) {
    subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
  }
}

private struct FrameBoundaryAppearanceReader: View {
  @Environment(\.terminalAppearance) private var appearance
  var body: some View {
    Text(
      "foreground=\(Int(appearance.foregroundColor.red * 255)),\(Int(appearance.foregroundColor.green * 255))"
    )
  }
}

private struct FrameBoundaryMetricsReader: View {
  @Environment(\.cellPixelMetrics) private var metrics
  var body: some View {
    Text(
      "metrics=\(metrics.width)x\(metrics.height):\(metrics.source == .reported ? "reported" : "estimated")"
    )
  }
}

@MainActor
private final class FrameBoundarySurfaceHolder {
  var surface: HostedRasterSurface?
  var sequences: [UInt64] = []
}

private struct FrameBoundaryDisappearWriter: View {
  let probe: FrameBoundaryProbe
  @State private var visible = true
  @State private var departures = 0
  var body: some View {
    let _ = probe.action = { visible = false }
    VStack(alignment: .leading) {
      if visible {
        Text("Departing").onDisappear {
          departures += 1
          probe.events.append("departed")
        }
      }
      Text("departures=\(departures)")
    }
  }
}

@MainActor
private final class FrameBoundaryUncancelledGate {
  private var opened = false
  private var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    if opened { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func open() {
    opened = true
    continuation?.resume()
    continuation = nil
  }
}

// Explicit Observation authoring keeps the model genuinely thread safe;
// mutation notifications cross executors while storage remains synchronized.
private final class FrameBoundaryThreadModel: Observable, Sendable {
  private let registrar = ObservationRegistrar()
  private let storage = Mutex(0)
  var value: Int {
    get {
      registrar.access(self, keyPath: \.value)
      return storage.withLock { $0 }
    }
    set {
      registrar.withMutation(of: self, keyPath: \.value) {
        storage.withLock { $0 = newValue }
      }
    }
  }
}

@MainActor
private final class FrameBoundaryObservedFrames {
  var byValue: [Int: SemanticHostFrame] = [:]
}

private struct FrameBoundaryThreadReader: View {
  let model: FrameBoundaryThreadModel
  var body: some View { Text("thread=\(model.value)") }
}
