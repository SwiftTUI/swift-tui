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
public final class FrameScheduler: FrameScheduling {
  private var pendingCauses: Set<WakeCause> = []
  private var invalidatedIdentities: Set<Identity> = []
  private var signalNames: Set<String> = []
  private var externalReasons: Set<String> = []
  private var nextDeadline: MonotonicInstant?
  private var pendingAnimationRequest: AnimationRequest = .inherit
  private var pendingAnimationBatchID: AnimationBatchID?
  /// Tally of `request*` calls received since the last
  /// `consumeReadyFrame`.  Drained into the produced `ScheduledFrame`
  /// for cancellation-pressure diagnostics; reset to 0 on consume.
  private var pendingIntentRequestCount: Int = 0
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
    invalidatedIdentities
  }

  public func requestInput() {
    pendingCauses.insert(.input)
    pendingIntentRequestCount += 1
    notifyPendingFrameRequestWaiters()
  }

  public func requestInvalidation(of identities: Set<Identity>) {
    pendingCauses.insert(.invalidation)
    invalidatedIdentities.formUnion(identities)
    pendingIntentRequestCount += 1
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func requestSignal(named name: String) {
    pendingCauses.insert(.signal)
    signalNames.insert(name)
    pendingIntentRequestCount += 1
    notifyPendingFrameRequestWaiters()
  }

  public func requestExternalWake(reason: String) {
    pendingCauses.insert(.external)
    externalReasons.insert(reason)
    pendingIntentRequestCount += 1
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func requestDeadline(_ deadline: MonotonicInstant) {
    if let existing = nextDeadline {
      nextDeadline = min(existing, deadline)
    } else {
      nextDeadline = deadline
    }
    pendingIntentRequestCount += 1
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func hasPendingFrame(at now: MonotonicInstant = .now()) -> Bool {
    !pendingCauses.isEmpty || (nextDeadline.map { $0 <= now } ?? false)
  }

  public func nextWakeInstant(
    after now: MonotonicInstant = .now()
  ) -> MonotonicInstant? {
    if !pendingCauses.isEmpty {
      return now
    }

    guard let nextDeadline else {
      return nil
    }
    return nextDeadline <= now ? now : nextDeadline
  }

  public func consumeReadyFrame(
    at now: MonotonicInstant = .now()
  ) -> ScheduledFrame? {
    let deadlineDue = nextDeadline.map { $0 <= now } ?? false
    guard !pendingCauses.isEmpty || deadlineDue else {
      return nil
    }

    var causes = pendingCauses
    if deadlineDue {
      causes.insert(.deadline)
    }

    let scheduled = ScheduledFrame(
      causes: causes,
      invalidatedIdentities: invalidatedIdentities,
      signalNames: signalNames.sorted(),
      externalReasons: externalReasons.sorted(),
      triggeredDeadline: deadlineDue ? nextDeadline : nil,
      nextDeadline: deadlineDue ? nil : nextDeadline,
      animationRequest: pendingAnimationRequest,
      animationBatchID: pendingAnimationBatchID,
      intentRequestCount: pendingIntentRequestCount
    )

    pendingCauses.removeAll(keepingCapacity: true)
    invalidatedIdentities.removeAll(keepingCapacity: true)
    signalNames.removeAll(keepingCapacity: true)
    externalReasons.removeAll(keepingCapacity: true)
    pendingAnimationRequest = .inherit
    pendingAnimationBatchID = nil
    pendingIntentRequestCount = 0
    if deadlineDue {
      nextDeadline = nil
    }

    return scheduled
  }

  public func reset() {
    pendingCauses.removeAll(keepingCapacity: true)
    invalidatedIdentities.removeAll(keepingCapacity: true)
    signalNames.removeAll(keepingCapacity: true)
    externalReasons.removeAll(keepingCapacity: true)
    pendingAnimationRequest = .inherit
    pendingAnimationBatchID = nil
    pendingIntentRequestCount = 0
    nextDeadline = nil
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
    pendingCauses.insert(.invalidation)
    invalidatedIdentities.formUnion(identities)
    pendingIntentRequestCount += 1
    // Coalescing rule: latest explicit request wins; `.inherit` never
    // overrides an explicit pending request.  Batch ID coalesces the
    // same way — latest wins, a nil batch ID never overrides an
    // explicit one.
    if animation != .inherit {
      pendingAnimationRequest = animation
    }
    if let batchID {
      pendingAnimationBatchID = batchID
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

    pendingCauses.insert(.invalidation)
    invalidatedIdentities.formUnion(frame.invalidatedIdentities)
    pendingIntentRequestCount += 1
    // Replay preserves the cancelled frame's one-shot animation intent only
    // when no newer explicit animation is already queued.
    if pendingAnimationRequest == .inherit, frame.animationRequest != .inherit {
      pendingAnimationRequest = frame.animationRequest
    }
    if pendingAnimationBatchID == nil {
      pendingAnimationBatchID = frame.animationBatchID
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }
}
