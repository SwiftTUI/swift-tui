import SwiftTUICore

func coalescedInputEvents(
  _ events: [InputEvent]
) -> [InputEvent] {
  guard !events.isEmpty else {
    return []
  }

  var coalesced: [InputEvent] = []
  coalesced.reserveCapacity(events.count)
  var pendingMouseEvent: MouseEvent?

  func flushPendingMouseEvent() {
    guard let currentPendingMouseEvent = pendingMouseEvent else {
      return
    }
    coalesced.append(.mouse(currentPendingMouseEvent))
    pendingMouseEvent = nil
  }

  for event in events {
    switch event {
    case .key:
      flushPendingMouseEvent()
      coalesced.append(event)
    case .paste, .drop:
      flushPendingMouseEvent()
      coalesced.append(event)
    case .mouse(let mouseEvent):
      guard mouseEvent.isCoalescible else {
        flushPendingMouseEvent()
        coalesced.append(.mouse(mouseEvent))
        continue
      }

      if let currentPendingMouseEvent = pendingMouseEvent,
        let mergedMouseEvent = currentPendingMouseEvent.merged(with: mouseEvent)
      {
        pendingMouseEvent = mergedMouseEvent
      } else {
        flushPendingMouseEvent()
        pendingMouseEvent = mouseEvent
      }
    }
  }

  flushPendingMouseEvent()
  return coalesced
}

enum InputReaderTiming {
  static let mouseEventFlushDelayMilliseconds = 1
}

/// Schedule-once-per-cluster state machine for the input reader's
/// pending-mouse-event flush.  Extracted from the dispatch-source-
/// based reader so the schedule invariant can be tested without
/// driving the dispatch source.
///
/// **The invariant**: only the FIRST event in a cluster arms the
/// flush timer.  Subsequent events appended while a flush is
/// already pending must NOT re-arm.  This caps flush latency at
/// `mouseEventFlushDelayMilliseconds` regardless of event rate.
///
/// The earlier reset-on-every-event behavior was the root cause
/// of the gallery's "scroll does nothing until I click" bug: a
/// continuous high-rate scroll burst kept pushing the flush
/// deadline forward, so the consumer never received any events
/// until the input stream went idle.
package final class MouseEventCoalescingState {
  package private(set) var pendingEvents: [InputEvent] = []
  package private(set) var isFlushScheduled = false

  package init() {}

  /// Appends `event` to the pending buffer.  Returns `true` when
  /// the caller is responsible for arming a flush timer (this
  /// is the first event in a new cluster); returns `false` when
  /// a flush is already scheduled and should be left alone.
  @discardableResult
  package func append(_ event: InputEvent) -> Bool {
    pendingEvents.append(event)
    guard !isFlushScheduled else {
      return false
    }
    isFlushScheduled = true
    return true
  }

  /// Drains the pending buffer and resets the scheduled-flush
  /// flag so the next appended event arms a fresh cluster.
  package func drain() -> [InputEvent] {
    let drained = pendingEvents
    pendingEvents.removeAll(keepingCapacity: true)
    isFlushScheduled = false
    return drained
  }
}

extension MouseEvent {
  var isCoalescible: Bool {
    switch kind {
    case .moved, .dragged, .scrolled:
      true
    case .down, .up:
      false
    }
  }

  func merged(
    with next: MouseEvent
  ) -> MouseEvent? {
    guard modifiers == next.modifiers,
      location.precision == next.location.precision
    else {
      return nil
    }

    switch (kind, next.kind) {
    case (.moved, .moved):
      return next
    case (.dragged(let lhsButton), .dragged(let rhsButton)) where lhsButton == rhsButton:
      return next
    case (.scrolled(let lhsDeltaX, let lhsDeltaY), .scrolled(let rhsDeltaX, let rhsDeltaY))
    where location.cell == next.location.cell && location.precision == next.location.precision:
      return .init(
        kind: .scrolled(
          deltaX: lhsDeltaX + rhsDeltaX,
          deltaY: lhsDeltaY + rhsDeltaY
        ),
        location: next.location,
        modifiers: modifiers
      )
    default:
      return nil
    }
  }
}
