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
    self.intentRequestCount = intentRequestCount
  }
}

/// Minimal invalidation interface used by state and lifecycle systems.
public protocol Invalidating: AnyObject {
  func requestInvalidation(of identities: Set<Identity>)
}

package protocol WakeNotifyingFrameScheduling: AnyObject {
  func setWakeHandler(_ handler: (@Sendable () -> Void)?)
}

package protocol CancelledFrameIntentReplaying: AnyObject {
  func replayCancelledFrameIntent(_ frame: ScheduledFrame)
}

package protocol PendingFrameAwaiting: AnyObject {
  func waitForPendingFrame(at now: MonotonicInstant) async
}

/// Scheduler contract used by the runtime event loop.
public protocol FrameScheduling: Invalidating {
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
public final class FrameScheduler: FrameScheduling, Sendable {
  /// The coalescing state mutated by every `request*` call and drained by
  /// `consumeReadyFrame`. Held behind `coalescingLock` so requests from any
  /// thread cannot race the main-actor run loop.
  private struct CoalescingState {
    var pendingCauses: Set<WakeCause> = []
    var invalidatedIdentities: Set<Identity> = []
    var signalNames: Set<String> = []
    var externalReasons: Set<String> = []
    /// Every armed wake deadline, sorted ascending and deduplicated. This was
    /// a single min-coalesced slot, which silently DISCARDED any later
    /// deadline when a nearer one was armed — a long-press timer's 500 ms
    /// wake was eaten by any 33 ms animation/momentum tick, and the gesture
    /// only resolved via fallbacks (F41). Kept small in practice: an
    /// animation tick, at most a few gesture/momentum wakes.
    var pendingDeadlines: [MonotonicInstant] = []
    var pendingAnimationRequest: AnimationRequest = .inherit
    var pendingAnimationBatchID: AnimationBatchID?
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
      if let index = state.pendingDeadlines.firstIndex(where: { deadline <= $0 }) {
        if state.pendingDeadlines[index] != deadline {
          state.pendingDeadlines.insert(deadline, at: index)
        }
      } else {
        state.pendingDeadlines.append(deadline)
      }
      state.pendingIntentRequestCount += 1
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func hasPendingFrame(at now: MonotonicInstant = .now()) -> Bool {
    coalescingLock.withLock { state in
      !state.pendingCauses.isEmpty
        || (state.pendingDeadlines.first.map { $0 <= now } ?? false)
    }
  }

  public func nextWakeInstant(
    after now: MonotonicInstant = .now()
  ) -> MonotonicInstant? {
    coalescingLock.withLock { state in
      if !state.pendingCauses.isEmpty {
        return now
      }

      guard let nextDeadline = state.pendingDeadlines.first else {
        return nil
      }
      return nextDeadline <= now ? now : nextDeadline
    }
  }

  public func consumeReadyFrame(
    at now: MonotonicInstant = .now()
  ) -> ScheduledFrame? {
    coalescingLock.withLock { state in
      // Every due deadline drains into this one frame; later deadlines
      // SURVIVE (they used to be discarded by the single-slot min-coalesce).
      // The triggered instant is the LATEST due deadline so every consumer
      // whose deadline passed (gesture drains, momentum) sees itself due.
      let dueCount = state.pendingDeadlines.prefix { $0 <= now }.count
      let deadlineDue = dueCount > 0
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
        triggeredDeadline: deadlineDue ? state.pendingDeadlines[dueCount - 1] : nil,
        nextDeadline: dueCount < state.pendingDeadlines.count
          ? state.pendingDeadlines[dueCount]
          : nil,
        animationRequest: state.pendingAnimationRequest,
        animationBatchID: state.pendingAnimationBatchID,
        intentRequestCount: state.pendingIntentRequestCount
      )

      state.pendingCauses.removeAll(keepingCapacity: true)
      state.invalidatedIdentities.removeAll(keepingCapacity: true)
      state.signalNames.removeAll(keepingCapacity: true)
      state.externalReasons.removeAll(keepingCapacity: true)
      state.pendingAnimationRequest = .inherit
      state.pendingAnimationBatchID = nil
      state.pendingIntentRequestCount = 0
      if deadlineDue {
        state.pendingDeadlines.removeFirst(dueCount)
      }

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
      state.pendingIntentRequestCount = 0
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
      }
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }
}
