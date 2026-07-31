import SwiftTUICore

/// Arrival bookkeeping for one event enqueued on the run loop's event pump.
///
/// Minted at the reader→pump seam so *every* runtime event kind carries a
/// read-time instant without adding a field to a public payload type
/// (``InputEvent`` and its cases stay untouched). ``MouseEvent/timestamp`` is
/// parse-time and feeds momentum velocity; it is deliberately not reused as
/// the latency origin, because keys, paste, drop, and signals would stay
/// unmeasured.
///
/// A single enqueue mints a span of one. When the pump buffer merges a
/// coalescible pointer event into its predecessor the spans fuse: `count`
/// grows and `last` advances. A three-notch wheel burst that reaches the run
/// loop as one summed `.scrolled` event therefore still reports three
/// answered inputs bracketed by the true first and last arrival instants.
/// Without the fusion the coalescing rate this instrumentation exists to
/// measure would undercount exactly the back-pressure it is looking for.
package struct InputArrival: Sendable, Equatable {
  /// Identifier of the earliest raw arrival in this span, from a per-session
  /// monotonic counter. Ordering key only; never reused within a session.
  package var id: UInt64
  /// How many raw arrivals this envelope represents — `1` unless fused.
  package var count: Int
  /// Enqueue instant of the earliest arrival in the span.
  package var first: MonotonicInstant
  /// Enqueue instant of the latest arrival in the span.
  package var last: MonotonicInstant

  package init(id: UInt64, arrival: MonotonicInstant) {
    self.id = id
    count = 1
    first = arrival
    last = arrival
  }

  package init(
    id: UInt64,
    count: Int,
    first: MonotonicInstant,
    last: MonotonicInstant
  ) {
    self.id = id
    self.count = count
    self.first = first
    self.last = last
  }

  /// Fuses `next` into this span, for the pump buffer's in-place merge of two
  /// coalescible pointer events into one.
  package func fused(with next: InputArrival) -> InputArrival {
    InputArrival(
      id: Swift.min(id, next.id),
      count: count + next.count,
      first: Swift.min(first, next.first),
      last: Swift.max(last, next.last)
    )
  }
}

/// One event drained from the pump together with the arrival envelope minted
/// for it at enqueue.
package struct PumpedEvent: Sendable {
  package var event: RuntimeEvent
  package var arrival: InputArrival

  package init(event: RuntimeEvent, arrival: InputArrival) {
    self.event = event
    self.arrival = arrival
  }
}

/// The inputs a committed frame answered: how many, and the arrival edges that
/// bracket them.
///
/// Accumulated during dispatch (one fold per input whose dispatch asked the
/// scheduler for work) and transferred into the frame at acquisition. The
/// frame's two latency columns are `commit − first` and `commit − last`: the
/// oldest input the frame answered and the newest.
package struct AnsweredInputs: Sendable, Equatable {
  package var count: Int
  package var first: MonotonicInstant
  package var last: MonotonicInstant

  package init(_ arrival: InputArrival) {
    count = arrival.count
    first = arrival.first
    last = arrival.last
  }

  package init(count: Int, first: MonotonicInstant, last: MonotonicInstant) {
    self.count = count
    self.first = first
    self.last = last
  }

  package mutating func fold(_ arrival: InputArrival) {
    count += arrival.count
    first = Swift.min(first, arrival.first)
    last = Swift.max(last, arrival.last)
  }

  package mutating func fold(_ other: AnsweredInputs) {
    count += other.count
    first = Swift.min(first, other.first)
    last = Swift.max(last, other.last)
  }
}

extension Optional where Wrapped == AnsweredInputs {
  /// Folds `arrival` into the accumulator, starting one if none exists.
  package mutating func fold(_ arrival: InputArrival) {
    switch self {
    case .none:
      self = AnsweredInputs(arrival)
    case .some(var existing):
      existing.fold(arrival)
      self = existing
    }
  }

  /// Folds another accumulator in — used to carry unanswered inputs forward
  /// when a frame is skipped or elided and therefore presented nothing.
  package mutating func fold(_ other: AnsweredInputs?) {
    guard let other else {
      return
    }
    switch self {
    case .none:
      self = other
    case .some(var existing):
      existing.fold(other)
      self = existing
    }
  }
}
