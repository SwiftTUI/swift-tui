import SwiftTUICore

@_spi(Runners) public struct RunLoopProgressEvent: Equatable, Sendable {
  @_spi(Runners) public enum Kind: String, Equatable, Sendable {
    case frameIntent = "frame_intent"
    case frameAcquired = "frame_acquired"
    case frameSkipped = "frame_skipped"
    case frameCommitted = "frame_committed"
    case eventDrain = "event_drain"
    case schedulerIdle = "scheduler_idle"
  }

  @_spi(Runners) public var sequence: UInt64
  @_spi(Runners) public var kind: Kind
  @_spi(Runners) public var frameNumber: Int
  @_spi(Runners) public var desiredGeneration: UInt64?
  @_spi(Runners) public var renderGeneration: UInt64?
  @_spi(Runners) public var tailJobState: String?
  @_spi(Runners) public var eventCount: Int?
  @_spi(Runners) public var coalescedEventBatches: Int?

  @_spi(Runners) public init(
    sequence: UInt64,
    kind: Kind,
    frameNumber: Int,
    desiredGeneration: UInt64? = nil,
    renderGeneration: UInt64? = nil,
    tailJobState: String? = nil,
    eventCount: Int? = nil,
    coalescedEventBatches: Int? = nil
  ) {
    self.sequence = sequence
    self.kind = kind
    self.frameNumber = frameNumber
    self.desiredGeneration = desiredGeneration
    self.renderGeneration = renderGeneration
    self.tailJobState = tailJobState
    self.eventCount = eventCount
    self.coalescedEventBatches = coalescedEventBatches
  }
}

@_spi(Runners) @MainActor public final class RunLoopProgressProbe {
  private struct Waiter {
    var predicate: @MainActor (RunLoopProgressEvent) -> Bool
    var continuation: CheckedContinuation<RunLoopProgressEvent, Never>
  }

  private var nextSequence: UInt64 = 0
  private var recordedEvents: [RunLoopProgressEvent] = []
  private var waiters: [Waiter] = []

  @_spi(Runners) public init() {}

  @_spi(Runners) public var events: [RunLoopProgressEvent] {
    recordedEvents
  }

  @_spi(Runners) public func frameCommitted(
    where predicate: @escaping @MainActor (RunLoopProgressEvent) -> Bool = { _ in true }
  ) async -> RunLoopProgressEvent {
    await event { event in
      event.kind == .frameCommitted && predicate(event)
    }
  }

  @_spi(Runners) public func idle() async -> RunLoopProgressEvent {
    await event { event in
      event.kind == .schedulerIdle
    }
  }

  @_spi(Runners) public func event(
    where predicate: @escaping @MainActor (RunLoopProgressEvent) -> Bool
  ) async -> RunLoopProgressEvent {
    if let event = recordedEvents.first(where: predicate) {
      return event
    }

    return await withCheckedContinuation { continuation in
      waiters.append(
        Waiter(
          predicate: predicate,
          continuation: continuation
        )
      )
    }
  }

  package func record(
    _ kind: RunLoopProgressEvent.Kind,
    frameNumber: Int,
    desiredGeneration: UInt64? = nil,
    renderGeneration: UInt64? = nil,
    tailJobState: FrameTailJobState? = nil,
    eventCount: Int? = nil,
    coalescedEventBatches: Int? = nil
  ) {
    let event = RunLoopProgressEvent(
      sequence: nextSequence,
      kind: kind,
      frameNumber: frameNumber,
      desiredGeneration: desiredGeneration,
      renderGeneration: renderGeneration,
      tailJobState: tailJobState?.rawValue,
      eventCount: eventCount,
      coalescedEventBatches: coalescedEventBatches
    )
    nextSequence &+= 1
    recordedEvents.append(event)

    var resumedWaiters: [CheckedContinuation<RunLoopProgressEvent, Never>] = []
    waiters.removeAll { waiter in
      guard waiter.predicate(event) else {
        return false
      }
      resumedWaiters.append(waiter.continuation)
      return true
    }

    for continuation in resumedWaiters {
      continuation.resume(returning: event)
    }
  }
}
