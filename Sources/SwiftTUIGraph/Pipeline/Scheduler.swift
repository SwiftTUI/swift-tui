/// Reasons the runtime may schedule a new frame.
public enum WakeCause: String, Hashable, Sendable {
  case input
  case invalidation
  case signal
  case external
  case deadline
}

/// A consumed frame request containing every pending wake reason.
public struct ScheduledFrame: Equatable, Sendable {
  public var causes: Set<WakeCause>
  public var invalidatedIdentities: Set<Identity>
  public var signalNames: [String]
  public var externalReasons: [String]
  public var triggeredDeadline: MonotonicInstant?
  public var nextDeadline: MonotonicInstant?
  package var forceRootEvaluation: Bool
  package var animationRequest: AnimationRequest
  package var animationBatchID: AnimationBatchID?
  /// Batch IDs the latest-wins coalescing displaced before this frame
  /// drained (F117); the runtime parks their completions so they still fire.
  package var supersededAnimationBatchIDs: [AnimationBatchID]
  /// Total number of `request*` calls (input, invalidation, signal,
  /// external, deadline) that the scheduler coalesced into this
  /// frame.  Used as a cancellation-pressure proxy for the
  /// `ASYNC_RENDER_GENERATION_SCHEDULER` Stage 3D rollout: when a
  /// frame's `intentRequestCount > 1`, multiple distinct intents
  /// merged into one render — meaning a hypothetical pre-start
  /// cancellation could have superseded an in-flight tail job here.
  public var intentRequestCount: Int

  public init(
    causes: Set<WakeCause>,
    invalidatedIdentities: Set<Identity>,
    signalNames: [String],
    externalReasons: [String],
    triggeredDeadline: MonotonicInstant?,
    nextDeadline: MonotonicInstant?
  ) {
    self.causes = causes
    self.invalidatedIdentities = invalidatedIdentities
    self.signalNames = signalNames
    self.externalReasons = externalReasons
    self.triggeredDeadline = triggeredDeadline
    self.nextDeadline = nextDeadline
    self.forceRootEvaluation = false
    self.animationRequest = .inherit
    self.animationBatchID = nil
    self.supersededAnimationBatchIDs = []
    self.intentRequestCount = 0
  }

  package init(
    causes: Set<WakeCause>,
    invalidatedIdentities: Set<Identity>,
    signalNames: [String],
    externalReasons: [String],
    triggeredDeadline: MonotonicInstant?,
    nextDeadline: MonotonicInstant?,
    forceRootEvaluation: Bool = false,
    animationRequest: AnimationRequest,
    animationBatchID: AnimationBatchID? = nil,
    supersededAnimationBatchIDs: [AnimationBatchID] = [],
    intentRequestCount: Int = 0
  ) {
    self.causes = causes
    self.invalidatedIdentities = invalidatedIdentities
    self.signalNames = signalNames
    self.externalReasons = externalReasons
    self.triggeredDeadline = triggeredDeadline
    self.nextDeadline = nextDeadline
    self.forceRootEvaluation = forceRootEvaluation
    self.animationRequest = animationRequest
    self.animationBatchID = animationBatchID
    self.supersededAnimationBatchIDs = supersededAnimationBatchIDs
    self.intentRequestCount = intentRequestCount
  }
}

/// Minimal invalidation interface used by state and lifecycle systems.
public protocol Invalidating: AnyObject {
  func requestInvalidation(of identities: Set<Identity>)
}

/// An ``Invalidating`` conformer whose `requestInvalidation` is safe to call
/// from any executor. ``FrameScheduler`` opts in; the Observation bridge's
/// off-main change marshal (F162) narrows its attached invalidator to this
/// so a background mutation can wake a sleeping run loop directly.
public protocol ThreadSafeInvalidating: Invalidating, Sendable {}

package protocol WakeNotifyingFrameScheduling: AnyObject {
  func setWakeHandler(_ handler: (@Sendable () -> Void)?)
}

package protocol CancelledFrameIntentReplaying: AnyObject {
  func replayCancelledFrameIntent(_ frame: ScheduledFrame)
}

package protocol PendingFrameAwaiting: AnyObject {
  func waitForPendingFrame(at now: MonotonicInstant) async
}

/// A drain-pass boundary for deadline consumption: deadlines armed at or after
/// the cut are withheld from `consumeReadyFrame(at:armedBefore:)` — deferred to
/// the next pass, never discarded. Captured by a frame driver at pass entry so
/// one drain is bounded to the work armed before it began (see
/// ``DrainPassDeadlineCutting``).
public struct DeadlineArmCut: Equatable, Sendable {
  public var rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

/// Bounds a drain-until-quiescent frame loop against deadline livelock (the
/// F41 reland shape, report 2026-07-07-008). The scheduler keeps every armed
/// deadline until due, so later deadlines survive nearer ones — but on a
/// machine whose per-frame cost meets or exceeds the animation cadence, each
/// frame's re-arm would be due again by the drain's re-check and the loop
/// would never quiesce. A driver captures ``deadlineArmCut`` once at pass
/// entry and consumes with it: deadlines armed during the pass only become
/// consumable on the next pass, so the pass's consumable set is finite and
/// strictly shrinking. `hasPendingFrame`/`nextWakeInstant` deliberately keep
/// the live view (withheld deadlines included) so the outer loop re-enters or
/// schedules its wake promptly.
///
/// Every ``FrameScheduling`` conformer must provide the cut (F95): the drain
/// drivers consume exclusively through it, with no ungated fallback — a
/// scheduler without cut semantics would silently revive the F41 livelock the
/// moment a drain outlives the deadline cadence. There is deliberately **no
/// default implementation**: forwarding to the ungated consume would be sound
/// only for schedulers that keep no deadline set, and silently wrong for any
/// that do; a conformer with no deadline set should forward explicitly and
/// say why (see `PerpetualSupersessionScheduler` in the tests).
public protocol DrainPassDeadlineCutting: AnyObject {
  /// The cut for one drain pass: a snapshot of the arm ordering. Deadlines
  /// armed after this read are withheld from consumes that pass this cut.
  var deadlineArmCut: DeadlineArmCut { get }

  /// `consumeReadyFrame(at:)` restricted to deadlines armed before `cut`.
  /// Pending causes (input, invalidation, signal, external) are unaffected.
  func consumeReadyFrame(
    at now: MonotonicInstant,
    armedBefore cut: DeadlineArmCut
  ) -> ScheduledFrame?
}

/// Scheduler contract used by the runtime event loop. Refines
/// ``DrainPassDeadlineCutting`` so a scheduler that cannot bound a drain pass
/// is unrepresentable — the type system, not a runtime cast, enforces the F41
/// livelock fix.
public protocol FrameScheduling: Invalidating, DrainPassDeadlineCutting {
  func requestInput()
  func requestSignal(named name: String)
  func requestExternalWake(reason: String)
  func requestDeadline(_ deadline: MonotonicInstant)
  func hasPendingFrame(at now: MonotonicInstant) -> Bool
  func nextWakeInstant(after now: MonotonicInstant) -> MonotonicInstant?
  func consumeReadyFrame(at now: MonotonicInstant) -> ScheduledFrame?
  func reset()
}

/// Coalesces invalidations, input, signals, and deadlines into frame work.
///
/// `FrameScheduler` is `Sendable` and genuinely thread-safe: its coalescing
/// state lives behind a lock so any thread may request a wake. This matters
/// because the `Invalidating`/`FrameScheduling` contract is `public` and
/// `nonisolated`, and at least one caller — the Observation `onChange` bridge —
/// can fire from an off-main mutation context. The previous design left the
/// coalescing sets lock-free and safe only "by convention" (every caller on the
/// main actor), which raced the run loop's `consumeReadyFrame` when that
/// convention was broken.
public final class FrameScheduler: FrameScheduling, ThreadSafeInvalidating, Sendable {
  /// The coalescing state mutated by every `request*` call and drained by
  /// `consumeReadyFrame`. Held behind `coalescingLock` so requests from any
  /// thread cannot race the main-actor run loop.
  /// One armed wake deadline. `armOrdinal` records arm ORDER (not time) so a
  /// drain pass can be bounded to the deadlines armed before it began — see
  /// ``DrainPassDeadlineCutting``.
  private struct PendingDeadline {
    var instant: MonotonicInstant
    var armOrdinal: UInt64
  }

  private struct CoalescingState {
    var pendingCauses: Set<WakeCause> = []
    var invalidatedIdentities: Set<Identity> = []
    var signalNames: Set<String> = []
    var externalReasons: Set<String> = []
    /// Every armed wake deadline, sorted ascending by instant and deduplicated
    /// by instant. This was a single min-coalesced slot, which silently
    /// DISCARDED any later deadline when a nearer one was armed — a long-press
    /// timer's 500 ms wake was eaten by any 33 ms animation/momentum tick, and
    /// the gesture only resolved via fallbacks (F41). Kept small in practice:
    /// an animation tick, at most a few gesture/momentum wakes. The survival
    /// semantics require the drivers' drain-pass cut (report 2026-07-07-008):
    /// without it, a machine slower than the animation cadence finds a due
    /// deadline at every drain re-check and never quiesces.
    var pendingDeadlines: [PendingDeadline] = []
    /// Monotonic arm counter backing ``DeadlineArmCut``. Never reset — a cut
    /// captured before `reset()` must stay meaningful.
    var nextDeadlineArmOrdinal: UInt64 = 0
    var pendingAnimationRequest: AnimationRequest = .inherit
    var pendingAnimationBatchID: AnimationBatchID?
    /// Batch IDs whose slot the latest-wins coalescing rule overwrote before
    /// a drain (F117). Carried on the produced frame so the runtime can park
    /// their `withAnimation` completions — a superseded batch's animations
    /// never retain it, so without this its completion would never fire.
    var pendingSupersededBatchIDs: [AnimationBatchID] = []
    /// Tally of `request*` calls received since the last `consumeReadyFrame`.
    /// Drained into the produced `ScheduledFrame` for cancellation-pressure
    /// diagnostics; reset to 0 on consume.
    var pendingIntentRequestCount: Int = 0
  }

  private let coalescingLock = OSAllocatedUnfairLock<CoalescingState>(
    uncheckedState: CoalescingState()
  )
  private let wakeHandlerLock = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(uncheckedState: nil)
  private struct PendingFrameRequestWaiters {
    var nextID: UInt64 = 0
    var waiters: [UInt64: CheckedContinuation<Void, Never>] = [:]
  }

  private let pendingFrameRequestWaitersLock = OSAllocatedUnfairLock<PendingFrameRequestWaiters>(
    uncheckedState: PendingFrameRequestWaiters()
  )

  public init() {}

  /// The invalidation identities coalesced since the last `consumeReadyFrame`.
  /// Read by the run loop to tell whether an action it just dispatched already
  /// requested a (reader-attributed) invalidation, so a redundant coarse
  /// post-action follow-up can be skipped.
  package var pendingInvalidatedIdentities: Set<Identity> {
    coalescingLock.withLock { $0.invalidatedIdentities }
  }

  public func requestInput() {
    coalescingLock.withLock { state in
      state.pendingCauses.insert(.input)
      state.pendingIntentRequestCount += 1
    }
    notifyPendingFrameRequestWaiters()
  }

  public func requestInvalidation(of identities: Set<Identity>) {
    coalescingLock.withLock { state in
      state.pendingCauses.insert(.invalidation)
      state.invalidatedIdentities.formUnion(identities)
      state.pendingIntentRequestCount += 1
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func requestSignal(named name: String) {
    coalescingLock.withLock { state in
      state.pendingCauses.insert(.signal)
      state.signalNames.insert(name)
      state.pendingIntentRequestCount += 1
    }
    notifyPendingFrameRequestWaiters()
  }

  public func requestExternalWake(reason: String) {
    coalescingLock.withLock { state in
      state.pendingCauses.insert(.external)
      state.externalReasons.insert(reason)
      state.pendingIntentRequestCount += 1
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func requestDeadline(_ deadline: MonotonicInstant) {
    coalescingLock.withLock { state in
      // Insert sorted by instant; a duplicate instant coalesces into the
      // EXISTING entry (keeping its earlier arm ordinal, so a re-arm of an
      // already-armed instant cannot push it behind a drain-pass cut it was
      // already inside).
      if let index = state.pendingDeadlines.firstIndex(where: { deadline <= $0.instant }) {
        if state.pendingDeadlines[index].instant != deadline {
          state.pendingDeadlines.insert(
            PendingDeadline(instant: deadline, armOrdinal: state.nextDeadlineArmOrdinal),
            at: index
          )
          state.nextDeadlineArmOrdinal += 1
        }
      } else {
        state.pendingDeadlines.append(
          PendingDeadline(instant: deadline, armOrdinal: state.nextDeadlineArmOrdinal)
        )
        state.nextDeadlineArmOrdinal += 1
      }
      state.pendingIntentRequestCount += 1
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func hasPendingFrame(at now: MonotonicInstant = .now()) -> Bool {
    coalescingLock.withLock { state in
      !state.pendingCauses.isEmpty
        || (state.pendingDeadlines.first.map { $0.instant <= now } ?? false)
    }
  }

  public func nextWakeInstant(
    after now: MonotonicInstant = .now()
  ) -> MonotonicInstant? {
    coalescingLock.withLock { state in
      if !state.pendingCauses.isEmpty {
        return now
      }

      guard let nextDeadline = state.pendingDeadlines.first?.instant else {
        return nil
      }
      return nextDeadline <= now ? now : nextDeadline
    }
  }

  public func consumeReadyFrame(
    at now: MonotonicInstant = .now()
  ) -> ScheduledFrame? {
    consumeReadyFrame(at: now, armOrdinalBelow: .max)
  }

  private func consumeReadyFrame(
    at now: MonotonicInstant,
    armOrdinalBelow cut: UInt64
  ) -> ScheduledFrame? {
    coalescingLock.withLock { state in
      // Every due deadline armed below the cut drains into this one frame;
      // later deadlines SURVIVE (they used to be discarded by the single-slot
      // min-coalesce — F41). The triggered instant is the LATEST consumed due
      // deadline so every consumer whose deadline passed (gesture drains,
      // momentum) sees itself due. Due deadlines at/after the cut are
      // WITHHELD, not lost: they stay pending for the next drain pass, which
      // is what bounds a drain on a machine slower than the animation cadence
      // (report 2026-07-07-008).
      let duePrefixCount = state.pendingDeadlines.prefix { $0.instant <= now }.count
      var triggeredDeadline: MonotonicInstant?
      if duePrefixCount > 0 {
        var withheld: [PendingDeadline] = []
        for pending in state.pendingDeadlines[..<duePrefixCount] {
          if pending.armOrdinal < cut {
            // Ascending instants: the last consumed entry is the latest due.
            triggeredDeadline = pending.instant
          } else {
            withheld.append(pending)
          }
        }
        if triggeredDeadline != nil {
          state.pendingDeadlines.replaceSubrange(0..<duePrefixCount, with: withheld)
        }
      }
      let deadlineDue = triggeredDeadline != nil
      guard !state.pendingCauses.isEmpty || deadlineDue else {
        return nil
      }

      var causes = state.pendingCauses
      if deadlineDue {
        causes.insert(.deadline)
      }

      let scheduled = ScheduledFrame(
        causes: causes,
        invalidatedIdentities: state.invalidatedIdentities,
        signalNames: state.signalNames.sorted(),
        externalReasons: state.externalReasons.sorted(),
        triggeredDeadline: triggeredDeadline,
        nextDeadline: state.pendingDeadlines.first?.instant,
        animationRequest: state.pendingAnimationRequest,
        animationBatchID: state.pendingAnimationBatchID,
        supersededAnimationBatchIDs: state.pendingSupersededBatchIDs,
        intentRequestCount: state.pendingIntentRequestCount
      )

      state.pendingCauses.removeAll(keepingCapacity: true)
      state.invalidatedIdentities.removeAll(keepingCapacity: true)
      state.signalNames.removeAll(keepingCapacity: true)
      state.externalReasons.removeAll(keepingCapacity: true)
      state.pendingAnimationRequest = .inherit
      state.pendingAnimationBatchID = nil
      state.pendingSupersededBatchIDs.removeAll(keepingCapacity: true)
      state.pendingIntentRequestCount = 0

      return scheduled
    }
  }

  public func reset() {
    coalescingLock.withLock { state in
      state.pendingCauses.removeAll(keepingCapacity: true)
      state.invalidatedIdentities.removeAll(keepingCapacity: true)
      state.signalNames.removeAll(keepingCapacity: true)
      state.externalReasons.removeAll(keepingCapacity: true)
      state.pendingAnimationRequest = .inherit
      state.pendingAnimationBatchID = nil
      state.pendingSupersededBatchIDs.removeAll(keepingCapacity: true)
      state.pendingIntentRequestCount = 0
      // The arm ordinal is deliberately NOT reset: a drain-pass cut captured
      // before a reset must keep excluding deadlines armed after it.
      state.pendingDeadlines.removeAll(keepingCapacity: true)
    }
  }

  private func notifyPendingFrameRequestWaiters() {
    let waiters = pendingFrameRequestWaitersLock.withLockUnchecked { state in
      let waiters = Array(state.waiters.values)
      state.waiters.removeAll(keepingCapacity: true)
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  private func waitForNextFrameRequest(
    timeout: Duration? = nil,
    unlessFramePending framePending: () -> Bool = { false }
  ) async {
    let waiterIDLock = OSAllocatedUnfairLock<UInt64?>(uncheckedState: nil)
    let timeoutTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(uncheckedState: nil)
    let pendingFrameRequestWaitersLock = pendingFrameRequestWaitersLock
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
          return
        }

        let waiterID = pendingFrameRequestWaitersLock.withLockUnchecked { state in
          let waiterID = state.nextID
          state.nextID &+= 1
          state.waiters[waiterID] = continuation
          return waiterID
        }
        waiterIDLock.withLockUnchecked { $0 = waiterID }
        if let timeout {
          let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            let continuation = pendingFrameRequestWaitersLock.withLockUnchecked { state in
              state.waiters.removeValue(forKey: waiterID)
            }
            continuation?.resume()
          }
          timeoutTaskLock.withLockUnchecked { $0 = timeoutTask }
        }
        if framePending() || Task.isCancelled {
          let continuation = pendingFrameRequestWaitersLock.withLockUnchecked { state in
            state.waiters.removeValue(forKey: waiterID)
          }
          timeoutTaskLock.withLockUnchecked { $0 }?.cancel()
          continuation?.resume()
        }
      }
    } onCancel: {
      timeoutTaskLock.withLockUnchecked { $0 }?.cancel()
      guard let waiterID = waiterIDLock.withLockUnchecked({ $0 }),
        let continuation = pendingFrameRequestWaitersLock.withLockUnchecked({
          state in state.waiters.removeValue(forKey: waiterID)
        })
      else {
        return
      }
      continuation.resume()
    }
    timeoutTaskLock.withLockUnchecked { $0 }?.cancel()
  }
}

extension FrameScheduler: WakeNotifyingFrameScheduling {
  package func setWakeHandler(_ handler: (@Sendable () -> Void)?) {
    wakeHandlerLock.withLockUnchecked { $0 = handler }
  }
}

// DrainPassDeadlineCutting conformance is inherited via FrameScheduling.
extension FrameScheduler {
  public var deadlineArmCut: DeadlineArmCut {
    DeadlineArmCut(rawValue: coalescingLock.withLock { $0.nextDeadlineArmOrdinal })
  }

  public func consumeReadyFrame(
    at now: MonotonicInstant,
    armedBefore cut: DeadlineArmCut
  ) -> ScheduledFrame? {
    consumeReadyFrame(at: now, armOrdinalBelow: cut.rawValue)
  }
}

extension FrameScheduler: PendingFrameAwaiting {
  package func waitForPendingFrame(at now: MonotonicInstant = .now()) async {
    var currentInstant = now
    while !Task.isCancelled {
      if hasPendingFrame(at: currentInstant) {
        return
      }

      if let nextWake = nextWakeInstant(after: currentInstant) {
        let sleepDuration = currentInstant.duration(to: nextWake)
        if sleepDuration > .zero {
          await waitForNextFrameRequest(timeout: sleepDuration) {
            hasPendingFrame(at: .now())
          }
        } else {
          return
        }
        currentInstant = .now()
        continue
      }

      await waitForNextFrameRequest {
        hasPendingFrame(at: .now())
      }
      currentInstant = .now()
    }
  }
}

extension FrameScheduler: AnimationAwareInvalidating {
  package func requestInvalidation(
    of identities: Set<Identity>,
    animation: AnimationRequest,
    batchID: AnimationBatchID?
  ) {
    coalescingLock.withLock { state in
      state.pendingCauses.insert(.invalidation)
      state.invalidatedIdentities.formUnion(identities)
      state.pendingIntentRequestCount += 1
      // Coalescing rule: latest explicit request wins; `.inherit` never
      // overrides an explicit pending request.  Batch ID coalesces the
      // same way — latest wins, a nil batch ID never overrides an
      // explicit one.
      if animation != .inherit {
        state.pendingAnimationRequest = animation
      }
      if let batchID {
        if let superseded = state.pendingAnimationBatchID,
          superseded != batchID,
          !state.pendingSupersededBatchIDs.contains(superseded)
        {
          state.pendingSupersededBatchIDs.append(superseded)
        }
        state.pendingAnimationBatchID = batchID
      }
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }
}

extension FrameScheduler: CancelledFrameIntentReplaying {
  package func replayCancelledFrameIntent(_ frame: ScheduledFrame) {
    let carriesInvalidationIntent =
      frame.causes.contains(.invalidation)
      || !frame.invalidatedIdentities.isEmpty
      || frame.animationRequest != .inherit
      || frame.animationBatchID != nil
    guard carriesInvalidationIntent else {
      return
    }

    coalescingLock.withLock { state in
      state.pendingCauses.insert(.invalidation)
      state.invalidatedIdentities.formUnion(frame.invalidatedIdentities)
      state.pendingIntentRequestCount += 1
      // Replay preserves the cancelled frame's one-shot animation intent only
      // when no newer explicit animation is already queued.
      if state.pendingAnimationRequest == .inherit, frame.animationRequest != .inherit {
        state.pendingAnimationRequest = frame.animationRequest
      }
      if state.pendingAnimationBatchID == nil {
        state.pendingAnimationBatchID = frame.animationBatchID
      } else if let dropped = frame.animationBatchID,
        dropped != state.pendingAnimationBatchID,
        !state.pendingSupersededBatchIDs.contains(dropped)
      {
        // A newer explicit batch already claimed the slot; the cancelled
        // frame's batch is superseded, not lost (F117).
        state.pendingSupersededBatchIDs.append(dropped)
      }
      for superseded in frame.supersededAnimationBatchIDs
      where !state.pendingSupersededBatchIDs.contains(superseded) {
        state.pendingSupersededBatchIDs.append(superseded)
      }
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }
}
