import SwiftTUICore

/// The event pump's side of a ``SynchronousInputPulling`` reader: where the
/// reader delivers parsed events, how it reports the end of its source, and
/// where it records source reads for the ingress diagnostics.
///
/// Every closure is main-actor isolated. The reader calls them synchronously
/// from ``SynchronousInputPulling/pullPendingInput()`` — whether that pull was
/// the run loop's own turn-boundary pull or the reader's idle poll — so
/// delivery order is the parse order by construction and one actor owns the
/// parser.
package struct InputPullDeliverySink: Sendable {
  /// Delivers one parsed input event to the pump, in source order.
  package var deliver: @MainActor @Sendable (InputEvent) -> Void
  /// Reports that the source has ended (EOF or a non-retryable read error).
  /// The reader calls this at most once.
  package var inputEnded: @MainActor @Sendable () -> Void
  /// Records one source read that returned data: how many bytes it read and
  /// how many input events they parsed to.
  package var recordSourceRead: @MainActor @Sendable (_ bytes: Int, _ events: Int) -> Void

  package init(
    deliver: @escaping @MainActor @Sendable (InputEvent) -> Void,
    inputEnded: @escaping @MainActor @Sendable () -> Void,
    recordSourceRead: @escaping @MainActor @Sendable (_ bytes: Int, _ events: Int) -> Void
  ) {
    self.deliver = deliver
    self.inputEnded = inputEnded
    self.recordSourceRead = recordSourceRead
  }
}

/// A terminal input reader whose source is a non-blocking, immediately
/// visible queue — the WASI stdin ring, the main-thread JSPI queue — that the
/// run loop can drain synchronously at its own turn boundaries.
///
/// The stream adapter (``TerminalInputReading/inputEvents()``) suits blocking
/// readers: a detached task reads, yields to an `AsyncStream`, and the pump's
/// copy task moves each event into the buffer. On a cooperative
/// single-threaded executor those two hops run only while the run-loop task
/// is suspended, and under sustained rendering the one dependable suspension
/// per frame admits about one event per frame however many are queued (plan
/// 2026-09-24-001 §2/§4D, STUI-618). A pulling reader removes the hops: the
/// run loop calls ``pullPendingInput()`` at the start of each outer-loop turn
/// and before each frame acquisition in a drain pass, and the read, parse,
/// and enqueue happen right there, synchronously on the main actor.
///
/// The reader keeps an idle polling task so a quiet loop still wakes when
/// input arrives; that task is main-actor isolated and calls the same pull,
/// so both paths serialize on one actor, the parser has one owner, FIFO order
/// holds across them, and `inputEnded` fires exactly once. Application
/// dispatch stays on the run loop; neither path preempts a running raster
/// operation — the pull is a service opportunity, not a preemption.
///
/// A conforming reader must not also be consumed through
/// ``TerminalInputReading/inputEvents()`` while a pull delivery is installed:
/// the pump uses exactly one path per reader.
package protocol SynchronousInputPulling: TerminalInputReading {
  /// Installs the delivery sink and starts the reader's idle polling. After
  /// this returns the reader delivers only through `sink`.
  @MainActor func installPullDelivery(_ sink: InputPullDeliverySink)

  /// Reads everything the source holds right now, parses it, and delivers
  /// the events in order through the installed sink. Never suspends. Returns
  /// the number of input events delivered; `0` when nothing was pending or
  /// no sink is installed.
  @MainActor @discardableResult func pullPendingInput() -> Int

  /// Stops idle polling and releases the sink.
  @MainActor func uninstallPullDelivery()
}
