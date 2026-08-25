/// Reasons that the runtime can schedule a new frame.
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
  package var animationSegments: [AnimationInvalidationSegment]
  /// Batch IDs whose every identity the segmented latest-wins coalescing
  /// displaced before this frame drained; the runtime parks their completions
  /// so they still fire.
  package var supersededAnimationBatchIDs: [AnimationBatchID]
  /// The total number of `request*` calls that the scheduler coalesced into this frame.
  /// These calls include input, invalidation, signal, external, and deadline requests.
  /// The `ASYNC_RENDER_GENERATION_SCHEDULER` Stage 3D rollout uses this value as a cancellation-pressure proxy.
  /// An `intentRequestCount > 1` value means that multiple intents merged into one render.
  /// In this state, a hypothetical pre-start cancellation can supersede an active tail job.
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
    self.animationSegments = []
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
    animationSegments: [AnimationInvalidationSegment] = [],
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
    self.animationSegments = AnimationInvalidationSegments.normalized(animationSegments)
    self.supersededAnimationBatchIDs = supersededAnimationBatchIDs
    self.intentRequestCount = intentRequestCount
  }

  package var hasExplicitAnimationTransactions: Bool {
    !animationSegments.isEmpty
  }

  package var liveAnimationBatchIDs: [AnimationBatchID] {
    AnimationInvalidationSegments.liveBatchIDs(in: animationSegments)
  }

  /// Rewrites invalidation identities and their animation segments together.
  /// Batches whose every identity the rewrite drops or displaces are promoted
  /// to the superseded list so their completions remain deliverable.
  @discardableResult
  package mutating func rewriteInvalidationIdentities(
    _ transform: (Set<Identity>) -> Set<Identity>
  ) -> [AnimationBatchID] {
    let originalBatchIDs = liveAnimationBatchIDs
    let segmentedIdentities = AnimationInvalidationSegments.identityUnion(animationSegments)
    let unsegmentedIdentities = invalidatedIdentities.subtracting(segmentedIdentities)
    animationSegments = AnimationInvalidationSegments.rewritingIdentities(
      in: animationSegments,
      transform
    )
    invalidatedIdentities = transform(unsegmentedIdentities).union(
      AnimationInvalidationSegments.identityUnion(animationSegments)
    )
    let displacedBatchIDs = originalBatchIDs.filter { !liveAnimationBatchIDs.contains($0) }
    for batchID in displacedBatchIDs where !supersededAnimationBatchIDs.contains(batchID) {
      supersededAnimationBatchIDs.append(batchID)
    }
    return displacedBatchIDs
  }
}

/// Minimal invalidation interface used by state and lifecycle systems.
public protocol Invalidating: AnyObject {
  func requestInvalidation(of identities: Set<Identity>)
}

/// An ``Invalidating`` conformer that accepts `requestInvalidation` calls from any executor.
/// ``FrameScheduler`` uses this protocol.
/// The Observation bridge narrows its invalidator to this protocol for off-main changes (F162).
/// Thus, a background mutation can directly wake a sleeping run loop.
public protocol ThreadSafeInvalidating: Invalidating, Sendable {}

package protocol WakeNotifyingFrameScheduling: AnyObject {
  func setWakeHandler(_ handler: (@Sendable () -> Void)?)
}

package protocol CancelledFrameIntentReplaying: AnyObject {
  func replayCancelledFrameIntent(_ frame: ScheduledFrame)
}

/// Releases a `waitForPendingFrame` wait early, without cancelling the
/// waiting task.
///
/// The frame tail's queued-cancellation wait used to be abandoned via task
/// cancellation, and a cancel that lands concurrently with a task's first
/// schedule or resume-enqueue can lose the wakeup inside the concurrency
/// runtime (`swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md` entry 14). A release
/// latch wakes the waiter through the same continuation registry as a frame request instead,
/// so the wait can be retired with no task cancellation anywhere on the seam.
package protocol PendingFrameWaitReleasing: AnyObject, Sendable {
  /// True once the wait no longer needs to hold; checked between waits.
  var isReleased: Bool { get }

  /// Registers a waker fired exactly once when the release trips. Fires
  /// inline, on the registering thread, when already released.
  func onRelease(_ waker: @escaping @Sendable () -> Void)
}

package protocol PendingFrameAwaiting: AnyObject {
  func waitForPendingFrame(
    at now: MonotonicInstant,
    releasedBy release: (any PendingFrameWaitReleasing)?
  ) async
}

extension PendingFrameAwaiting {
  package func waitForPendingFrame(at now: MonotonicInstant) async {
    await waitForPendingFrame(at: now, releasedBy: nil)
  }
}

/// Reads the scheduler's coalesced `request*` tally without consuming a frame.
///
/// The run loop's input-attribution probe brackets each input dispatch with
/// this read: an input whose dispatch raised the tally asked for scheduler
/// work — an input frame, an invalidation, a deadline arm — and therefore
/// belongs to the next committed frame's latency columns. `hasPendingFrame`
/// cannot serve here: during a scroll burst it is already `true`, so it
/// saturates and can never tell whether *this* input asked for anything.
///
/// Deliberately a narrow opt-in protocol reached by cast, like
/// ``WakeNotifyingFrameScheduling`` — a required member on the public
/// ``FrameScheduling`` would break out-of-tree conformers for a diagnostic.
/// A scheduler that does not conform simply reports no answered inputs.
package protocol IntentRequestTallying: AnyObject {
  /// `request*` calls coalesced since the last `consumeReadyFrame`. Reset to
  /// zero on consume, so only *differences* taken within one dispatch are
  /// meaningful.
  var coalescedIntentRequestCount: Int { get }
}

/// A drain-pass boundary for deadline consumption: deadlines armed at or after
/// the cut are withheld from `consumeReadyFrame(at:armedBefore:)`, deferred to
/// the next pass rather than discarded. Captured by a frame driver at pass
/// entry so one drain is bounded to the work armed before it began (see
/// ``DrainPassDeadlineCutting``).
public struct DeadlineArmCut: Equatable, Sendable {
  public var rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

/// Prevents a deadline livelock in a drain-until-quiescent frame loop (F41, report 2026-07-07-008).
/// The scheduler keeps each armed deadline until it is due.
/// Thus, later deadlines remain after nearer deadlines.
/// If the frame cost reaches the animation cadence, each frame re-arm is due at the next drain evaluation.
/// Without a limit, the loop cannot become quiescent.
/// A driver captures ``deadlineArmCut`` one time when a pass starts.
/// It uses this cut to consume deadlines.
/// Deadlines armed during the pass become consumable on the next pass.
/// Thus, the consumable set for a pass is finite and decreases after each consumption.
/// `hasPendingFrame` and `nextWakeInstant` retain the live view, including withheld deadlines.
/// This behavior lets the outer loop enter again or schedule its next wake promptly.
///
/// Each ``FrameScheduling`` conformer must provide the cut (F95).
/// The drain drivers consume deadlines only through this cut. They have no fallback without a gate.
/// Without cut semantics, a drain that exceeds the deadline cadence causes the F41 livelock.
/// This protocol has no default implementation.
/// An ungated implementation is correct only for schedulers that keep no deadline set.
/// A conformer with no deadline set must implement forwarding and explain the reason.
/// See `PerpetualSupersessionScheduler` in the tests.
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

/// Scheduler contract for the runtime event loop.
/// It refines ``DrainPassDeadlineCutting`` to require a bound for each drain pass.
/// Thus, the type system enforces the F41 livelock correction without a runtime cast.
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
/// `FrameScheduler` is `Sendable` and thread-safe.
/// A lock protects its coalescing state, and any thread can request a wake.
/// The `Invalidating` and `FrameScheduling` contracts are `public` and `nonisolated`.
/// The Observation `onChange` bridge can run for an off-main mutation.
/// The previous design had no lock for the coalescing sets.
/// It relied on all callers to run on the main actor.
/// An off-main caller caused a race with `consumeReadyFrame` in the run loop.
public final class FrameScheduler: FrameScheduling, ThreadSafeInvalidating, IntentRequestTallying,
  Sendable
{
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
    var pendingAnimationSegments: [AnimationInvalidationSegment] = []
    /// Every batch observed since the last drain, in first-observed order.
    /// Supersession is derived at drain time so a partially displaced batch
    /// remains live while any segment still carries it.
    var pendingObservedAnimationBatchIDs: [AnimationBatchID] = []
    /// Tally of `request*` calls received since the last `consumeReadyFrame`.
    /// Drained into the produced `ScheduledFrame` for cancellation-pressure
    /// diagnostics; reset to 0 on consume.
    var pendingIntentRequestCount: Int = 0
    /// Monotonic count of `requestInvalidation` calls. Never reset — a
    /// generation captured before an event dispatch must stay meaningful
    /// regardless of frame consumes, so "did the dispatch request an
    /// invalidation of its own" is a generation compare rather than a
    /// pending-SET compare (whose equality lied exactly when the dispatch
    /// re-requested an identity already pending — the coalesced
    /// focus-flip + scroll-write backstop accident, flip plan
    /// 2026-08-12-004 Stage 2).
    var invalidationRequestGeneration: UInt64 = 0
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

  package var coalescedIntentRequestCount: Int {
    coalescingLock.withLock { $0.pendingIntentRequestCount }
  }

  /// Monotonic count of `requestInvalidation` calls over the scheduler's
  /// lifetime (never reset). The run loop captures it before dispatching an
  /// event and compares after: an unchanged generation proves the dispatch
  /// requested no invalidation of its own, which is the dispatch backstop's
  /// firing condition.
  package var invalidationRequestGeneration: UInt64 {
    coalescingLock.withLock { $0.invalidationRequestGeneration }
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
      state.invalidationRequestGeneration &+= 1
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

      let liveAnimationBatchIDs = AnimationInvalidationSegments.liveBatchIDs(
        in: state.pendingAnimationSegments
      )
      let scheduled = ScheduledFrame(
        causes: causes,
        invalidatedIdentities: state.invalidatedIdentities,
        signalNames: state.signalNames.sorted(),
        externalReasons: state.externalReasons.sorted(),
        triggeredDeadline: triggeredDeadline,
        nextDeadline: state.pendingDeadlines.first?.instant,
        animationSegments: state.pendingAnimationSegments,
        supersededAnimationBatchIDs: state.pendingObservedAnimationBatchIDs.filter {
          !liveAnimationBatchIDs.contains($0)
        },
        intentRequestCount: state.pendingIntentRequestCount
      )

      state.pendingCauses.removeAll(keepingCapacity: true)
      state.invalidatedIdentities.removeAll(keepingCapacity: true)
      state.signalNames.removeAll(keepingCapacity: true)
      state.externalReasons.removeAll(keepingCapacity: true)
      state.pendingAnimationSegments.removeAll(keepingCapacity: true)
      state.pendingObservedAnimationBatchIDs.removeAll(keepingCapacity: true)
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
      state.pendingAnimationSegments.removeAll(keepingCapacity: true)
      state.pendingObservedAnimationBatchIDs.removeAll(keepingCapacity: true)
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
    releasedBy release: (any PendingFrameWaitReleasing)? = nil,
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
        // The release waker resumes through the same registry as a frame
        // request, so a released waiter needs no task cancellation. The
        // timeout task is deliberately left to expire on its own: it finds
        // the waiter gone and no-ops, and this seam must not add a cancel
        // that could land concurrently with an enqueue (entry 14).
        if let release {
          release.onRelease {
            let continuation = pendingFrameRequestWaitersLock.withLockUnchecked { state in
              state.waiters.removeValue(forKey: waiterID)
            }
            continuation?.resume()
          }
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
  package func waitForPendingFrame(
    at now: MonotonicInstant = .now(),
    releasedBy release: (any PendingFrameWaitReleasing)? = nil
  ) async {
    var currentInstant = now
    while !Task.isCancelled, release?.isReleased != true {
      if hasPendingFrame(at: currentInstant) {
        return
      }

      if let nextWake = nextWakeInstant(after: currentInstant) {
        let sleepDuration = currentInstant.duration(to: nextWake)
        if sleepDuration > .zero {
          await waitForNextFrameRequest(timeout: sleepDuration, releasedBy: release) {
            hasPendingFrame(at: .now())
          }
        } else {
          return
        }
        currentInstant = .now()
        continue
      }

      await waitForNextFrameRequest(releasedBy: release) {
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
    batchID: AnimationBatchID?,
    isContinuous: Bool,
    customValues: [ObjectIdentifier: AnyHashableSendable],
    tracksVelocity: Bool
  ) {
    coalescingLock.withLock { state in
      state.pendingCauses.insert(.invalidation)
      state.invalidatedIdentities.formUnion(identities)
      state.pendingIntentRequestCount += 1
      state.invalidationRequestGeneration &+= 1
      AnimationInvalidationSegments.append(
        AnimationInvalidationSegment(
          identities: identities,
          animationRequest: animation,
          animationBatchID: batchID,
          isContinuous: isContinuous,
          customValues: customValues,
          tracksVelocity: tracksVelocity
        ),
        to: &state.pendingAnimationSegments
      )
      if let batchID, !state.pendingObservedAnimationBatchIDs.contains(batchID) {
        state.pendingObservedAnimationBatchIDs.append(batchID)
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
      || frame.hasExplicitAnimationTransactions
    guard carriesInvalidationIntent else {
      return
    }

    coalescingLock.withLock { state in
      state.pendingCauses.insert(.invalidation)
      state.invalidatedIdentities.formUnion(frame.invalidatedIdentities)
      state.pendingIntentRequestCount += 1
      // A cancelled frame is older than intent already pending at replay time.
      // Restore it first, then reapply the pending segments so newer intent
      // wins only for exact contested identities.
      let newerSegments = state.pendingAnimationSegments
      let newerObservedBatchIDs = state.pendingObservedAnimationBatchIDs
      state.pendingAnimationSegments = frame.animationSegments
      for segment in newerSegments {
        AnimationInvalidationSegments.append(
          segment,
          to: &state.pendingAnimationSegments
        )
      }

      state.pendingObservedAnimationBatchIDs.removeAll(keepingCapacity: true)
      let observedBatchIDs =
        frame.liveAnimationBatchIDs
        + frame.supersededAnimationBatchIDs
        + newerObservedBatchIDs
      for batchID in observedBatchIDs
      where !state.pendingObservedAnimationBatchIDs.contains(batchID) {
        state.pendingObservedAnimationBatchIDs.append(batchID)
      }
    }
    notifyPendingFrameRequestWaiters()
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }
}
