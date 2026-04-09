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
  package var animationRequest: AnimationRequest

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
    self.animationRequest = .inherit
  }

  package init(
    causes: Set<WakeCause>,
    invalidatedIdentities: Set<Identity>,
    signalNames: [String],
    externalReasons: [String],
    triggeredDeadline: MonotonicInstant?,
    nextDeadline: MonotonicInstant?,
    animationRequest: AnimationRequest
  ) {
    self.causes = causes
    self.invalidatedIdentities = invalidatedIdentities
    self.signalNames = signalNames
    self.externalReasons = externalReasons
    self.triggeredDeadline = triggeredDeadline
    self.nextDeadline = nextDeadline
    self.animationRequest = animationRequest
  }
}

/// Minimal invalidation interface used by state and lifecycle systems.
public protocol Invalidating: AnyObject {
  func requestInvalidation(of identities: Set<Identity>)
}

package protocol WakeNotifyingFrameScheduling: AnyObject {
  func setWakeHandler(_ handler: (@Sendable () -> Void)?)
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
  private let wakeHandlerLock = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(uncheckedState: nil)

  public init() {}

  public func requestInput() {
    pendingCauses.insert(.input)
  }

  public func requestInvalidation(of identities: Set<Identity>) {
    pendingCauses.insert(.invalidation)
    invalidatedIdentities.formUnion(identities)
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func requestSignal(named name: String) {
    pendingCauses.insert(.signal)
    signalNames.insert(name)
  }

  public func requestExternalWake(reason: String) {
    pendingCauses.insert(.external)
    externalReasons.insert(reason)
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }

  public func requestDeadline(_ deadline: MonotonicInstant) {
    if let existing = nextDeadline {
      nextDeadline = min(existing, deadline)
    } else {
      nextDeadline = deadline
    }
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
      animationRequest: pendingAnimationRequest
    )

    pendingCauses.removeAll(keepingCapacity: true)
    invalidatedIdentities.removeAll(keepingCapacity: true)
    signalNames.removeAll(keepingCapacity: true)
    externalReasons.removeAll(keepingCapacity: true)
    pendingAnimationRequest = .inherit
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
    nextDeadline = nil
  }
}

extension FrameScheduler: WakeNotifyingFrameScheduling {
  package func setWakeHandler(_ handler: (@Sendable () -> Void)?) {
    wakeHandlerLock.withLockUnchecked { $0 = handler }
  }
}

extension FrameScheduler: AnimationAwareInvalidating {
  package func requestInvalidation(
    of identities: Set<Identity>,
    animation: AnimationRequest
  ) {
    pendingCauses.insert(.invalidation)
    invalidatedIdentities.formUnion(identities)
    // Coalescing rule: latest explicit request wins; `.inherit` never
    // overrides an explicit pending request.
    if animation != .inherit {
      pendingAnimationRequest = animation
    }
    wakeHandlerLock.withLockUnchecked { $0 }?()
  }
}
